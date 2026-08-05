/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: form_validation
function_name: check_candidate_self_email_unique
form_no: 1
language: plpgsql
description: Validate EMAIL_ID uniqueness across candidate records
functional_specification: On add, or on edit only when EMAIL_ID has changed from the stored value, check that EMAIL_ID does not already exist on another row of EMPONB_CANDIDATE_SELF or EMPONB_CANDIDATE_RECORD (excluding the current CANDIDATE_ID). Return an error if a duplicate is found. Skip the check entirely on edit when EMAIL_ID is unchanged from the existing record.
business_logic: Validate EMAIL_ID uniqueness across candidate records
*/

CREATE OR REPLACE FUNCTION check_candidate_self_email_unique(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id text := p->>'CANDIDATE_ID';
    v_email        text := p->>'EMAIL_ID';
    v_stored_email text;
    v_dup          boolean;
BEGIN
    -- EMAIL_ID is mandatory; if not supplied there is nothing to check here
    IF v_email IS NULL OR btrim(v_email) = '' THEN
        RETURN NULL;
    END IF;

    -- On edit, skip entirely when the email has not changed from what is stored
    IF p->>'_action' = 'edit' THEN
        SELECT EMAIL_ID
        INTO v_stored_email
        FROM EMPONB_CANDIDATE_SELF
        WHERE CANDIDATE_ID = v_candidate_id;

        IF FOUND AND v_stored_email IS NOT DISTINCT FROM v_email THEN
            RETURN NULL;  -- unchanged, no need to re-validate uniqueness
        END IF;
    END IF;

    -- Duplicate if the email is used by any OTHER candidate in either table.
    -- EMPONB_CANDIDATE_RECORD.CANDIDATE_ID is CHAR(10): pad the value side (never
    -- the column) so the current candidate's own record row is correctly excluded.
    SELECT EXISTS (
        SELECT 1
        FROM EMPONB_CANDIDATE_SELF
        WHERE EMAIL_ID     = v_email
          AND CANDIDATE_ID <> v_candidate_id
        UNION ALL
        SELECT 1
        FROM EMPONB_CANDIDATE_RECORD
        WHERE EMAIL_ID     = v_email
          AND CANDIDATE_ID <> rpad(v_candidate_id, 10)
    ) INTO v_dup;

    IF v_dup THEN
        RETURN jsonb_build_object('error',
            'This email address is already registered for another candidate.');
    END IF;

    RETURN NULL;
END;
$$;
