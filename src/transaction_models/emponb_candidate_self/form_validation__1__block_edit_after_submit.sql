/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: form_validation
function_name: block_edit_after_submit
form_no: 1
language: plpgsql
description: Prevent any changes to the header once the self record status is Submit
functional_specification: On save of the header form (add or edit), look up the CURRENTLY STORED STATUS on EMPONB_CANDIDATE_SELF for this CANDIDATE_ID (the value in the database BEFORE this save is applied, not the incoming form value). If the stored STATUS = 'Submit', return an error blocking the save with message 'This record has already been submitted and cannot be changed.'. If no stored row exists yet (first-time add) or stored STATUS is anything else, pass with no error.
business_logic: Prevent any changes to the header once the self record status is Submit
*/

CREATE OR REPLACE FUNCTION block_edit_after_submit(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id text := NULLIF(btrim(COALESCE(p->>'CANDIDATE_ID', '')), '');
    v_stored_status text;
BEGIN
    -- No key on the payload yet -> nothing stored to compare against
    IF v_candidate_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Status as it stands in the database BEFORE this save is applied
    SELECT STATUS
      INTO v_stored_status
      FROM EMPONB_CANDIDATE_SELF
     WHERE CANDIDATE_ID = v_candidate_id;

    -- First-time add: no stored row, allow the save
    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    IF btrim(COALESCE(v_stored_status, '')) = 'Submit' THEN
        RETURN jsonb_build_object(
            'error', 'This record has already been submitted and cannot be changed.',
            'error_code', 'SELF_LOCKED_AFTER_SUBMIT'
        );
    END IF;

    RETURN NULL;
END;
$$;
