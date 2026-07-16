/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: form_action
function_name: submit_to_candidate_record
form_no: 1
action_name: Submit
language: plpgsql
description: Submit candidate self-service data to the Candidate Onboarding Record
functional_specification: Push the candidate's self-service data into the HR Candidate Onboarding Record for the CANDIDATE_ID on the current form, replacing any existing record with delete-then-insert semantics because the data received from the Candidate Website must fully overwrite whatever is already held. Read candidate_id from the input payload. An existing EMPONB_CANDIDATE_RECORD row is NOT required. (1) Header: DELETE the existing EMPONB_CANDIDATE_RECORD row for this CANDIDATE_ID (if any), then INSERT a fresh row from EMPONB_CANDIDATE_SELF carrying CANDIDATE_ID plus every candidate-supplied header field held on EMPONB_CANDIDATE_SELF that also exists on EMPONB_CANDIDATE_RECORD - the personal identity fields (NAME_PREFIX, EMP_FNAME, EMP_MNAME, EMP_LNAME, BIRTHDATE, MARITAL_STATUS, MARRIAGE_ANNIVERSARY, BLOOD_GROUP, RELIGION, CAST_CATEGORY, MOTHER_TONGUE, PHYSICAL_HANDICAP, HOBBY1, HOBBY2, TOTAL_EXPERIENCE), the contact/address block (CURRENT_ADDRESS, CURRENT_PIN, CURRENT_CITY, CURRENT_STATE, PERMANENT_ADDRESS, PERMANENT_PIN, PERMANENT_CITY, PERMANENT_STATE, MOBILE, ALTERNATE_TELEPHONE, CONTACT_PERSON, CONTACT_PERSON_MOBILE, CONTACT_PERSON_EMAIL), and the statutory/financial block (PAN_NO, AADHAR_NO, PASSPORT_NO, DRIVING_LIC_NO, PF_NO, ESIC_NO, BANK_ACCOUNT_NO, BANK_IFSC_CODE, BANK_NAME) - copying the values that currently sit on the EMPONB_CANDIDATE_SELF row for that CANDIDATE_ID. Also stamp the record lifecycle: STATUS = 'DataSubmitted', STATUS_DATE = now(), SUBMITTED_ON = now(). Only carry columns that actually exist on BOTH tables; do NOT insert HR-owned columns the candidate does not supply (access-key/link/initiation and validation-status columns are left out entirely, defaulting on insert). (2) Refresh ALL detail tables: for each self detail table -> record detail table pair (EMPONB_CAND_SELF_EXPERIENCE -> EMPONB_CAND_EXPERIENCE, EMPONB_CAND_SELF_EDUCATION -> EMPONB_CAND_EDUCATION, EMPONB_CAND_SELF_FAMILY -> EMPONB_CAND_FAMILY, EMPONB_CAND_SELF_PAY -> EMPONB_CAND_PAY), delete the existing rows in the record detail table for this CANDIDATE_ID and re-insert one row per corresponding self detail row, mapping the columns common to both tables and carrying CANDIDATE_ID and LINE_NO so the parent-detail linkage is preserved. Return {"message": "..."} confirming the candidate data was submitted to the onboarding record (mention the CANDIDATE_ID and how many experience/education/family/pay rows were copied). The whole operation must be atomic - any failure rolls the action back.
business_logic: Submit candidate self-service data to the Candidate Onboarding Record
*/

CREATE OR REPLACE FUNCTION submit_to_candidate_record(p jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
    -- CANDIDATE_ID from the current form (lowercase form-col key; fall back to upper)
    v_candidate_id CHAR(10) := COALESCE(p->>'candidate_id', p->>'CANDIDATE_ID');
    v_exp_cnt      integer := 0;   -- experience rows copied
    v_edu_cnt      integer := 0;   -- education rows copied
    v_fam_cnt      integer := 0;   -- family rows copied
    v_pay_cnt      integer := 0;   -- pay rows copied
BEGIN
    IF v_candidate_id IS NULL OR btrim(v_candidate_id) = '' THEN
        RETURN jsonb_build_object('error', 'No candidate id supplied on the form.');
    END IF;

    -- (1) Header: delete-then-insert. Data from the Candidate Website must fully
    --     replace any existing header row, so remove the current EMPONB_CANDIDATE_RECORD
    --     row for this candidate (if any) and insert a fresh one from EMPONB_CANDIDATE_SELF.
    --     Only candidate-supplied columns that exist on BOTH tables are carried; the
    --     HR-owned access-key/link/initiation and validation-status columns are left out
    --     of the INSERT and default on their own.
    DELETE FROM EMPONB_CANDIDATE_RECORD WHERE CANDIDATE_ID = v_candidate_id;

    INSERT INTO EMPONB_CANDIDATE_RECORD
        (CANDIDATE_ID,
         NAME_PREFIX, EMP_FNAME, EMP_MNAME, EMP_LNAME, CANDIDATE_NAME, BIRTHDATE,
         EMAIL_ID, GENDER, DESIGN_CODE,
         MARITAL_STATUS, MARRIAGE_ANNIVERSARY, BLOOD_GROUP, RELIGION,
         CAST_CATEGORY, MOTHER_TONGUE, PHYSICAL_HANDICAP, HOBBY1, HOBBY2,
         TOTAL_EXPERIENCE,
         CURRENT_ADDRESS, CURRENT_PIN, CURRENT_CITY, CURRENT_STATE,
         PERMANENT_ADDRESS, PERMANENT_PIN, PERMANENT_CITY, PERMANENT_STATE,
         MOBILE, ALTERNATE_TELEPHONE, CONTACT_PERSON, CONTACT_PERSON_MOBILE,
         CONTACT_PERSON_EMAIL,
         PAN_NO, AADHAR_NO, PASSPORT_NO, DRIVING_LIC_NO, PF_NO, ESIC_NO,
         BANK_ACCOUNT_NO, BANK_IFSC_CODE, BANK_NAME,
         -- document uploads
         PAN_DOC, AADHAR_DOC, BANK_DOC, PASSPORT_DOC, DRIVING_LIC_DOC, PF_DOC, ESIC_DOC,
         STATUS, STATUS_DATE, SUBMITTED_ON)
    SELECT s.CANDIDATE_ID,
           s.NAME_PREFIX, s.EMP_FNAME, s.EMP_MNAME, s.EMP_LNAME,
           -- personal identity: derive the NOT-NULL CANDIDATE_NAME by joining first,
           -- middle and last name with single spaces (skipping any blank/null part)
           btrim(regexp_replace(concat_ws(' ', btrim(s.EMP_FNAME), btrim(s.EMP_MNAME), btrim(s.EMP_LNAME)), '\s+', ' ', 'g')),
           s.BIRTHDATE,
           -- candidate contact/classification: EMAIL_ID is NOT NULL on the record and
           -- is always supplied (mandatory, email-format-validated on the self form)
           s.EMAIL_ID, s.GENDER, s.DESIGN_CODE,
           s.MARITAL_STATUS, s.MARRIAGE_ANNIVERSARY, s.BLOOD_GROUP, s.RELIGION,
           s.CAST_CATEGORY, s.MOTHER_TONGUE, s.PHYSICAL_HANDICAP, s.HOBBY1, s.HOBBY2,
           s.TOTAL_EXPERIENCE,
           s.CURRENT_ADDRESS, s.CURRENT_PIN, s.CURRENT_CITY, s.CURRENT_STATE,
           s.PERMANENT_ADDRESS, s.PERMANENT_PIN, s.PERMANENT_CITY, s.PERMANENT_STATE,
           s.MOBILE, s.ALTERNATE_TELEPHONE, s.CONTACT_PERSON, s.CONTACT_PERSON_MOBILE,
           s.CONTACT_PERSON_EMAIL,
           s.PAN_NO, s.AADHAR_NO, s.PASSPORT_NO, s.DRIVING_LIC_NO, s.PF_NO, s.ESIC_NO,
           s.BANK_ACCOUNT_NO, s.BANK_IFSC_CODE, s.BANK_NAME,
           -- document uploads
           s.PAN_DOC, s.AADHAR_DOC, s.BANK_DOC, s.PASSPORT_DOC, s.DRIVING_LIC_DOC, s.PF_DOC, s.ESIC_DOC,
           'DataSubmitted', now(), now()
    FROM EMPONB_CANDIDATE_SELF s
    WHERE s.CANDIDATE_ID = v_candidate_id;

    -- (2) Refresh each detail table: clear the record-side rows for this candidate
    --     and re-insert one row per self-side row, preserving CANDIDATE_ID/LINE_NO.

    -- Past experience
    DELETE FROM EMPONB_CAND_EXPERIENCE WHERE CANDIDATE_ID = v_candidate_id;
    INSERT INTO EMPONB_CAND_EXPERIENCE
        (CANDIDATE_ID, LINE_NO, ORGANISATION, DESIGNATION, FROM_DATE, TO_DATE,
         GROSS_AMT, CURRENCY_CODE, COUNTRY_CODE)
    SELECT CANDIDATE_ID, LINE_NO, ORGANISATION, DESIGNATION, FROM_DATE, TO_DATE,
           GROSS_AMT, CURRENCY_CODE, COUNTRY_CODE
    FROM EMPONB_CAND_SELF_EXPERIENCE
    WHERE CANDIDATE_ID = v_candidate_id;
    GET DIAGNOSTICS v_exp_cnt = ROW_COUNT;

    -- Education
    DELETE FROM EMPONB_CAND_EDUCATION WHERE CANDIDATE_ID = v_candidate_id;
    INSERT INTO EMPONB_CAND_EDUCATION
        (CANDIDATE_ID, LINE_NO, QLF_CODE, QLF_TYPE, INSTITUTE, PASS_YEAR, CLASS,
         PERCENTAGE, COUNTRY_CODE, COURSE_TYPE, COURSE_DURATION)
    SELECT CANDIDATE_ID, LINE_NO, QLF_CODE, QLF_TYPE, INSTITUTE, PASS_YEAR, CLASS,
           PERCENTAGE, COUNTRY_CODE, COURSE_TYPE, COURSE_DURATION
    FROM EMPONB_CAND_SELF_EDUCATION
    WHERE CANDIDATE_ID = v_candidate_id;
    GET DIAGNOSTICS v_edu_cnt = ROW_COUNT;

    -- Family
    DELETE FROM EMPONB_CAND_FAMILY WHERE CANDIDATE_ID = v_candidate_id;
    INSERT INTO EMPONB_CAND_FAMILY
        (CANDIDATE_ID, LINE_NO, MEMBER_NAME, DATE_BIRTH, GENDER, RELATION)
    SELECT CANDIDATE_ID, LINE_NO, MEMBER_NAME, DATE_BIRTH, GENDER, RELATION
    FROM EMPONB_CAND_SELF_FAMILY
    WHERE CANDIDATE_ID = v_candidate_id;
    GET DIAGNOSTICS v_fam_cnt = ROW_COUNT;

    -- Candidate pay
    DELETE FROM EMPONB_CAND_PAY WHERE CANDIDATE_ID = v_candidate_id;
    INSERT INTO EMPONB_CAND_PAY
        (CANDIDATE_ID, LINE_NO, AD_CODE, AMOUNT, AMOUNT_TYPE, FREQUENCY,
         RES_FORMULA, AMOUNT_CALC, UPD_PAYSTRU, APPL_MODE)
    SELECT CANDIDATE_ID, LINE_NO, AD_CODE, AMOUNT, AMOUNT_TYPE, FREQUENCY,
           RES_FORMULA, AMOUNT_CALC, UPD_PAYSTRU, APPL_MODE
    FROM EMPONB_CAND_SELF_PAY
    WHERE CANDIDATE_ID = v_candidate_id;
    GET DIAGNOSTICS v_pay_cnt = ROW_COUNT;

    RETURN jsonb_build_object('message',
        'Candidate ' || v_candidate_id ||
        ' data submitted to the Candidate Onboarding Record.');
END;
$$;
