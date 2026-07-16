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

    -- (1) Header: merge the candidate's self-service values into the existing
    --     EMPONB_CANDIDATE_RECORD row for this candidate. Instead of blanket-
    --     overwriting, apply ONLY the values the candidate actually supplied: every
    --     common column falls back to its current record value via COALESCE, and
    --     blank ('') text is treated as 'no change' via NULLIF so an empty field
    --     never blanks out data already held. The HR-owned access-key/link/
    --     initiation and validation-status columns are left untouched. The record
    --     lifecycle stamps (STATUS / STATUS_DATE / SUBMITTED_ON) are ALWAYS refreshed.
    UPDATE EMPONB_CANDIDATE_RECORD r
       SET NAME_PREFIX           = COALESCE(NULLIF(s.NAME_PREFIX, ''), r.NAME_PREFIX),
           EMP_FNAME             = COALESCE(NULLIF(s.EMP_FNAME, ''), r.EMP_FNAME),
           EMP_MNAME             = COALESCE(NULLIF(s.EMP_MNAME, ''), r.EMP_MNAME),
           EMP_LNAME             = COALESCE(NULLIF(s.EMP_LNAME, ''), r.EMP_LNAME),
           -- keep CANDIDATE_NAME (NOT NULL) in sync when name parts are provided,
           -- otherwise preserve the existing name
           CANDIDATE_NAME        = COALESCE(NULLIF(btrim(regexp_replace(concat_ws(' ', btrim(s.EMP_FNAME), btrim(s.EMP_MNAME), btrim(s.EMP_LNAME)), '\s+', ' ', 'g')), ''), r.CANDIDATE_NAME),
           BIRTHDATE             = COALESCE(s.BIRTHDATE, r.BIRTHDATE),
           EMAIL_ID              = COALESCE(NULLIF(s.EMAIL_ID, ''), r.EMAIL_ID),
           GENDER                = COALESCE(NULLIF(s.GENDER, ''), r.GENDER),
           DESIGN_CODE           = COALESCE(NULLIF(s.DESIGN_CODE, ''), r.DESIGN_CODE),
           NATIONALITY           = COALESCE(NULLIF(s.NATIONALITY, ''), r.NATIONALITY),
           MARITAL_STATUS        = COALESCE(NULLIF(s.MARITAL_STATUS, ''), r.MARITAL_STATUS),
           MARRIAGE_ANNIVERSARY  = COALESCE(s.MARRIAGE_ANNIVERSARY, r.MARRIAGE_ANNIVERSARY),
           BLOOD_GROUP           = COALESCE(NULLIF(s.BLOOD_GROUP, ''), r.BLOOD_GROUP),
           RELIGION              = COALESCE(NULLIF(s.RELIGION, ''), r.RELIGION),
           CAST_CATEGORY         = COALESCE(NULLIF(s.CAST_CATEGORY, ''), r.CAST_CATEGORY),
           MOTHER_TONGUE         = COALESCE(NULLIF(s.MOTHER_TONGUE, ''), r.MOTHER_TONGUE),
           PHYSICAL_HANDICAP     = COALESCE(NULLIF(s.PHYSICAL_HANDICAP, ''), r.PHYSICAL_HANDICAP),
           HOBBY1                = COALESCE(NULLIF(s.HOBBY1, ''), r.HOBBY1),
           HOBBY2                = COALESCE(NULLIF(s.HOBBY2, ''), r.HOBBY2),
           TOTAL_EXPERIENCE      = COALESCE(s.TOTAL_EXPERIENCE, r.TOTAL_EXPERIENCE),
           CURRENT_ADDRESS       = COALESCE(NULLIF(s.CURRENT_ADDRESS, ''), r.CURRENT_ADDRESS),
           CURRENT_PIN           = COALESCE(NULLIF(s.CURRENT_PIN, ''), r.CURRENT_PIN),
           CURRENT_CITY          = COALESCE(NULLIF(s.CURRENT_CITY, ''), r.CURRENT_CITY),
           CURRENT_STATE         = COALESCE(NULLIF(s.CURRENT_STATE, ''), r.CURRENT_STATE),
           PERMANENT_ADDRESS     = COALESCE(NULLIF(s.PERMANENT_ADDRESS, ''), r.PERMANENT_ADDRESS),
           PERMANENT_PIN         = COALESCE(NULLIF(s.PERMANENT_PIN, ''), r.PERMANENT_PIN),
           PERMANENT_CITY        = COALESCE(NULLIF(s.PERMANENT_CITY, ''), r.PERMANENT_CITY),
           PERMANENT_STATE       = COALESCE(NULLIF(s.PERMANENT_STATE, ''), r.PERMANENT_STATE),
           MOBILE                = COALESCE(NULLIF(s.MOBILE, ''), r.MOBILE),
           ALTERNATE_TELEPHONE   = COALESCE(NULLIF(s.ALTERNATE_TELEPHONE, ''), r.ALTERNATE_TELEPHONE),
           CONTACT_PERSON        = COALESCE(NULLIF(s.CONTACT_PERSON, ''), r.CONTACT_PERSON),
           CONTACT_PERSON_MOBILE = COALESCE(NULLIF(s.CONTACT_PERSON_MOBILE, ''), r.CONTACT_PERSON_MOBILE),
           CONTACT_PERSON_EMAIL  = COALESCE(NULLIF(s.CONTACT_PERSON_EMAIL, ''), r.CONTACT_PERSON_EMAIL),
           PAN_NO                = COALESCE(NULLIF(s.PAN_NO, ''), r.PAN_NO),
           AADHAR_NO             = COALESCE(NULLIF(s.AADHAR_NO, ''), r.AADHAR_NO),
           PASSPORT_NO           = COALESCE(NULLIF(s.PASSPORT_NO, ''), r.PASSPORT_NO),
           DRIVING_LIC_NO        = COALESCE(NULLIF(s.DRIVING_LIC_NO, ''), r.DRIVING_LIC_NO),
           PF_NO                 = COALESCE(NULLIF(s.PF_NO, ''), r.PF_NO),
           ESIC_NO               = COALESCE(NULLIF(s.ESIC_NO, ''), r.ESIC_NO),
           BANK_ACCOUNT_NO       = COALESCE(NULLIF(s.BANK_ACCOUNT_NO, ''), r.BANK_ACCOUNT_NO),
           BANK_IFSC_CODE        = COALESCE(NULLIF(s.BANK_IFSC_CODE, ''), r.BANK_IFSC_CODE),
           BANK_NAME             = COALESCE(NULLIF(s.BANK_NAME, ''), r.BANK_NAME),
           -- document uploads: preserve existing docs when no new upload is supplied
           PAN_DOC               = COALESCE(NULLIF(s.PAN_DOC, ''), r.PAN_DOC),
           AADHAR_DOC            = COALESCE(NULLIF(s.AADHAR_DOC, ''), r.AADHAR_DOC),
           BANK_DOC              = COALESCE(NULLIF(s.BANK_DOC, ''), r.BANK_DOC),
           PASSPORT_DOC          = COALESCE(NULLIF(s.PASSPORT_DOC, ''), r.PASSPORT_DOC),
           DRIVING_LIC_DOC       = COALESCE(NULLIF(s.DRIVING_LIC_DOC, ''), r.DRIVING_LIC_DOC),
           PF_DOC                = COALESCE(NULLIF(s.PF_DOC, ''), r.PF_DOC),
           ESIC_DOC              = COALESCE(NULLIF(s.ESIC_DOC, ''), r.ESIC_DOC),
           -- lifecycle stamps are always applied, never conditional
           STATUS                = 'DataSubmitted',
           STATUS_DATE           = now(),
           SUBMITTED_ON          = now()
      FROM EMPONB_CANDIDATE_SELF s
     WHERE s.CANDIDATE_ID = v_candidate_id
       AND r.CANDIDATE_ID = v_candidate_id;

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
