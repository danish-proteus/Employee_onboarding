/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: field_validation
function_name: validate_email_uniqueness
form_no: 1
field_name: email_id
language: plpgsql
description: Check EMAIL_ID uniqueness, skipping the check when the record is opened in edit mode and the email is unchanged
functional_specification: On add, or on edit when EMAIL_ID has changed from the stored value, verify no other EMPONB_CANDIDATE_RECORD row (excluding the current CANDIDATE_ID on edit) has the same EMAIL_ID; return an error if found. On edit when EMAIL_ID is unchanged (matches the stored value), skip the check and pass.
business_logic: Check EMAIL_ID uniqueness, skipping the check when the record is opened in edit mode and the email is unchanged
*/

CREATE OR REPLACE FUNCTION validate_email_uniqueness(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_email_id     varchar(120) := NULLIF(TRIM(COALESCE(p->>'EMAIL_ID', p->>'email_id')), '');
    v_candidate_id varchar(10)  := NULLIF(TRIM(COALESCE(p->>'CANDIDATE_ID', p->>'candidate_id')), '');
    v_is_edit      boolean      := (p->>'_action' = 'edit');
    v_stored_email varchar(120);
    v_dup_id       varchar(10);
BEGIN
    -- Nothing entered yet: leave the mandatory-field check to the engine.
    IF v_email_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Edit mode: if the email still matches what is stored, the value was not
    -- changed by the user — skip the duplicate check entirely so simply opening
    -- and re-saving an existing record never flags itself.
    IF v_is_edit AND v_candidate_id IS NOT NULL THEN
        SELECT EMAIL_ID
          INTO v_stored_email
          FROM EMPONB_CANDIDATE_RECORD
         WHERE CANDIDATE_ID = v_candidate_id;

        IF FOUND AND LOWER(COALESCE(TRIM(v_stored_email), '')) = LOWER(v_email_id) THEN
            RETURN NULL;
        END IF;
    END IF;

    -- Add, or edit with a changed email: the address must not belong to any
    -- other candidate. On edit the current row is excluded by primary key.
    SELECT CANDIDATE_ID
      INTO v_dup_id
      FROM EMPONB_CANDIDATE_RECORD
     WHERE EMAIL_ID = v_email_id
       AND (v_candidate_id IS NULL OR CANDIDATE_ID <> v_candidate_id)
     LIMIT 1;

    IF FOUND THEN
        RETURN jsonb_build_object(
            'error',
            'Email id ' || v_email_id || ' is already used by candidate ' || v_dup_id || '.'
        );
    END IF;

    RETURN NULL;
END;
$$;
