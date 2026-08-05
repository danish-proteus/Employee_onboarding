/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_item_change
function_name: load_candidate_self_header
form_no: 1
field_name: candidate_id
language: plpgsql
description: Load header from self record, fallback to candidate record
functional_specification: On change of CANDIDATE_ID: first SELECT the row from EMPONB_CANDIDATE_SELF for this CANDIDATE_ID. If found, return its columns as updates so the form is populated with the candidate's own previously-saved self-service data (personal, contact, statutory, financial fields). If no EMPONB_CANDIDATE_SELF row exists yet for this CANDIDATE_ID, SELECT the row from EMPONB_CANDIDATE_RECORD for the same CANDIDATE_ID and return its comparable columns (CANDIDATE_NAME, GENDER, DESIGN_CODE, EMAIL_ID, NAME_PREFIX, EMP_FNAME, EMP_MNAME, EMP_LNAME, BIRTHDATE, NATIONALITY, MARITAL_STATUS, MARRIAGE_ANNIVERSARY, BLOOD_GROUP, RELIGION, CAST_CATEGORY, MOTHER_TONGUE, PHYSICAL_HANDICAP, HOBBY1, HOBBY2, TOTAL_EXPERIENCE, address/contact/statutory/financial fields) as updates so the candidate sees HR's initial capture as a starting point. Return {"updates": {...}}.
business_logic: Load header from self record, fallback to candidate record
*/

CREATE OR REPLACE FUNCTION load_candidate_self_header(p jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id text := btrim(COALESCE(p->>'CANDIDATE_ID', ''));
    v_updates      jsonb;
BEGIN
    -- No candidate chosen yet -> nothing to load.
    IF v_candidate_id = '' THEN
        RETURN NULL;
    END IF;

    -- 1) Prefer the candidate's own previously-saved self-service row.
    --    Cast the value to the column's CHAR type so the CHAR/CHAR compare stays
    --    blank-insensitive and index-friendly (column left un-wrapped).
    SELECT jsonb_object_agg(upper(key), value)
      INTO v_updates
      FROM jsonb_each(
             (SELECT to_jsonb(s) FROM EMPONB_CANDIDATE_SELF s
               WHERE s.CANDIDATE_ID = v_candidate_id::char(10))
           );

    IF v_updates IS NOT NULL THEN
        RETURN jsonb_build_object('updates', v_updates);
    END IF;

    -- 2) Fallback: seed the form from HR's initial capture in the candidate record.
    SELECT jsonb_build_object(
               'CANDIDATE_NAME',        r.CANDIDATE_NAME,
               'GENDER',                r.GENDER,
               'DESIGN_CODE',           r.DESIGN_CODE,
               'EMAIL_ID',              r.EMAIL_ID,
               'NAME_PREFIX',           r.NAME_PREFIX,
               'EMP_FNAME',             r.EMP_FNAME,
               'EMP_MNAME',             r.EMP_MNAME,
               'EMP_LNAME',             r.EMP_LNAME,
               'BIRTHDATE',             r.BIRTHDATE,
               'NATIONALITY',           r.NATIONALITY,
               'MARITAL_STATUS',        r.MARITAL_STATUS,
               'MARRIAGE_ANNIVERSARY',  r.MARRIAGE_ANNIVERSARY,
               'BLOOD_GROUP',           r.BLOOD_GROUP,
               'RELIGION',              r.RELIGION,
               'CAST_CATEGORY',         r.CAST_CATEGORY,
               'MOTHER_TONGUE',         r.MOTHER_TONGUE,
               'PHYSICAL_HANDICAP',     r.PHYSICAL_HANDICAP,
               'HOBBY1',                r.HOBBY1,
               'HOBBY2',                r.HOBBY2,
               'TOTAL_EXPERIENCE',      r.TOTAL_EXPERIENCE,
               'CURRENT_ADDRESS',       r.CURRENT_ADDRESS,
               'CURRENT_PIN',           r.CURRENT_PIN,
               'CURRENT_CITY',          r.CURRENT_CITY,
               'CURRENT_STATE',         r.CURRENT_STATE,
               'PERMANENT_ADDRESS',     r.PERMANENT_ADDRESS,
               'PERMANENT_PIN',         r.PERMANENT_PIN,
               'PERMANENT_CITY',        r.PERMANENT_CITY,
               'PERMANENT_STATE',       r.PERMANENT_STATE,
               'MOBILE',                r.MOBILE,
               'ALTERNATE_TELEPHONE',   r.ALTERNATE_TELEPHONE,
               'CONTACT_PERSON',        r.CONTACT_PERSON,
               'CONTACT_PERSON_MOBILE', r.CONTACT_PERSON_MOBILE,
               'CONTACT_PERSON_EMAIL',  r.CONTACT_PERSON_EMAIL,
               'PAN_NO',                r.PAN_NO,
               'PAN_DOC',               r.PAN_DOC,
               'AADHAR_NO',             r.AADHAR_NO,
               'AADHAR_DOC',            r.AADHAR_DOC,
               'PASSPORT_NO',           r.PASSPORT_NO,
               'PASSPORT_DOC',          r.PASSPORT_DOC,
               'DRIVING_LIC_NO',        r.DRIVING_LIC_NO,
               'DRIVING_LIC_DOC',       r.DRIVING_LIC_DOC,
               'PF_NO',                 r.PF_NO,
               'PF_DOC',                r.PF_DOC,
               'ESIC_NO',               r.ESIC_NO,
               'ESIC_DOC',              r.ESIC_DOC,
               'BANK_ACCOUNT_NO',       r.BANK_ACCOUNT_NO,
               'BANK_IFSC_CODE',        r.BANK_IFSC_CODE,
               'BANK_NAME',             r.BANK_NAME,
               'BANK_DOC',              r.BANK_DOC
           )
      INTO v_updates
      FROM EMPONB_CANDIDATE_RECORD r
     WHERE r.CANDIDATE_ID = v_candidate_id::char(10);

    IF v_updates IS NOT NULL THEN
        RETURN jsonb_build_object('updates', v_updates);
    END IF;

    -- No source row anywhere -> leave the form as-is.
    RETURN NULL;
END;
$$;
