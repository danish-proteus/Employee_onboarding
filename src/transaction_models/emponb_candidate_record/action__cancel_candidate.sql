/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: action
function_name: cancel_candidate
action_name: Cancel
language: plpgsql
description: Cancel the candidate record
functional_specification: Set STATUS='Cancelled', invalidate the access key (KEY_VALID_FLAG='N'), stamp STATUS_DATE. Return a confirmation message.
business_logic: Cancel the candidate record
*/

CREATE OR REPLACE FUNCTION emponb_candidate_record__cancel_candidate(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id char(10) := p->>'CANDIDATE_ID';
    v_status       varchar(20);
BEGIN
    IF v_candidate_id IS NULL OR btrim(v_candidate_id) = '' THEN
        RETURN jsonb_build_object('error', 'Candidate id is required.');
    END IF;

    SELECT STATUS INTO v_status
      FROM EMPONB_CANDIDATE_RECORD
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found.');
    END IF;

    -- A confirmed/pushed candidate must not be cancelled.
    IF v_status = 'Confirmed' THEN
        RETURN jsonb_build_object('error', 'A confirmed candidate cannot be cancelled.');
    END IF;

    UPDATE EMPONB_CANDIDATE_RECORD
       SET STATUS         = 'Cancelled',
           KEY_VALID_FLAG = 'N',
           STATUS_DATE    = now()
     WHERE CANDIDATE_ID = v_candidate_id;

    RETURN jsonb_build_object('prompts',
             jsonb_build_array(jsonb_build_object(
                 'code', 'CANC01', 'type', 'P',
                 'message', 'Candidate record cancelled and access link invalidated.')));
END;
$$;
