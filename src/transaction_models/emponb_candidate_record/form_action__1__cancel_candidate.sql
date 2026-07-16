/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: form_action
function_name: cancel_candidate
form_no: 1
action_name: Cancel
language: plpgsql
description: Cancel the candidate record
functional_specification: Set STATUS='Cancelled', stamp STATUS_DATE, set KEY_VALID_FLAG='N' to invalidate any outstanding link. Return a confirmation message.
business_logic: Cancel the candidate record
*/

CREATE OR REPLACE FUNCTION cancel_candidate(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_candidate_id CHAR(10);
    v_status       VARCHAR(20);
BEGIN
    -- Read the candidate key from the payload
    v_candidate_id := p->>'candidate_id';

    IF v_candidate_id IS NULL OR TRIM(v_candidate_id) = '' THEN
        RETURN jsonb_build_object('error', 'Candidate ID is required to cancel the record.');
    END IF;

    -- Fetch the current status (compare the key column directly to stay sargable)
    SELECT STATUS
      INTO v_status
      FROM EMPONB_CANDIDATE_RECORD
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found.');
    END IF;

    -- Guard against cancelling an already cancelled candidate
    IF v_status = 'Cancelled' THEN
        RETURN jsonb_build_object('message', 'Candidate is already cancelled.');
    END IF;

    -- Cancel the candidate: stamp status, status date and invalidate any outstanding link
    UPDATE EMPONB_CANDIDATE_RECORD
       SET STATUS         = 'Cancelled',
           STATUS_DATE    = CURRENT_TIMESTAMP,
           KEY_VALID_FLAG = 'N'
     WHERE CANDIDATE_ID = v_candidate_id;

    RETURN jsonb_build_object('message', 'Candidate record has been cancelled successfully.');
END;
$$;
