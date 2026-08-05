/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_validation
function_name: check_self_email_unique
form_no: 1
field_name: email_id
language: plpgsql
description: Validate email uniqueness, skip when unchanged in edit mode
functional_specification: If _action = 'edit' and the submitted EMAIL_ID equals the EMAIL_ID already stored on this CANDIDATE_ID's EMPONB_CANDIDATE_SELF row, pass (return NULL) without checking. Otherwise check whether EMAIL_ID already exists on any OTHER row of EMPONB_CANDIDATE_SELF (CANDIDATE_ID <> current) or on EMPONB_CANDIDATE_RECORD for a different CANDIDATE_ID; if found, return an error indicating the email address is already registered.
business_logic: Validate email uniqueness, skip when unchanged in edit mode
*/

CREATE OR REPLACE FUNCTION check_self_email_unique(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id text := p->>'CANDIDATE_ID';
    v_email        text := btrim(COALESCE(p->>'EMAIL_ID',''));
    v_stored_email text;
    v_exists       boolean;
BEGIN
    -- Nothing to validate until an email has been entered
    IF v_email = '' THEN
        RETURN NULL;
    END IF;

    -- On edit, if the email is unchanged from what is already stored, pass silently.
    IF p->>'_action' = 'edit' AND v_candidate_id IS NOT NULL THEN
        SELECT s.EMAIL_ID
        INTO v_stored_email
        FROM EMPONB_CANDIDATE_SELF s
        WHERE s.CANDIDATE_ID = v_candidate_id;

        IF FOUND AND btrim(COALESCE(v_stored_email,'')) = v_email THEN
            RETURN NULL;
        END IF;
    END IF;

    -- Registered on another self-onboarding row, or on a candidate record for a different candidate?
    SELECT EXISTS (
        SELECT 1
        FROM EMPONB_CANDIDATE_SELF s
        WHERE s.EMAIL_ID = v_email
          AND (v_candidate_id IS NULL OR s.CANDIDATE_ID <> v_candidate_id)
        UNION ALL
        SELECT 1
        FROM EMPONB_CANDIDATE_RECORD r
        WHERE r.EMAIL_ID = v_email
          AND (v_candidate_id IS NULL OR r.CANDIDATE_ID <> v_candidate_id)
    ) INTO v_exists;

    IF v_exists THEN
        RETURN jsonb_build_object('error',
            'The email address ' || v_email || ' is already registered.');
    END IF;

    RETURN NULL;
END;
$$;
