/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_validation
function_name: validate_self_email_unique
form_no: 1
field_name: email_id
language: plpgsql
description: Skip when unchanged in edit mode, else check uniqueness
functional_specification: On save of EMPONB_CANDIDATE_SELF: if _action = 'edit' and the submitted EMAIL_ID equals the EMAIL_ID already stored for this CANDIDATE_ID, pass (return NULL) without re-checking. Otherwise check that no OTHER row in EMPONB_CANDIDATE_SELF (excluding this CANDIDATE_ID) and no row in EMPONB_CANDIDATE_RECORD (excluding this CANDIDATE_ID) already has this EMAIL_ID; if one does, return an error.
business_logic: Skip when unchanged in edit mode, else check uniqueness
*/

CREATE OR REPLACE FUNCTION validate_self_email_unique(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id text := p->>'CANDIDATE_ID';
    v_email        text := p->>'EMAIL_ID';
    v_stored_email text;
    v_exists       boolean;
BEGIN
    -- Nothing to check without an email value
    IF v_email IS NULL OR btrim(v_email) = '' THEN
        RETURN NULL;
    END IF;

    -- In edit mode, if the email is unchanged for this candidate, pass immediately
    IF p->>'_action' = 'edit' THEN
        SELECT EMAIL_ID
          INTO v_stored_email
          FROM EMPONB_CANDIDATE_SELF
         WHERE CANDIDATE_ID = v_candidate_id;

        IF FOUND AND v_stored_email = v_email THEN
            RETURN NULL;
        END IF;
    END IF;

    -- Duplicate in another candidate-self row (exclude this candidate)
    SELECT EXISTS (
             SELECT 1
               FROM EMPONB_CANDIDATE_SELF
              WHERE EMAIL_ID = v_email
                AND CANDIDATE_ID <> v_candidate_id
           )
        OR EXISTS (
             SELECT 1
               FROM EMPONB_CANDIDATE_RECORD
              WHERE EMAIL_ID = v_email
                AND CANDIDATE_ID <> v_candidate_id
           )
      INTO v_exists;

    IF v_exists THEN
        RETURN jsonb_build_object('error',
            'Email ID ' || v_email || ' is already used by another candidate.');
    END IF;

    RETURN NULL;
END;
$$;
