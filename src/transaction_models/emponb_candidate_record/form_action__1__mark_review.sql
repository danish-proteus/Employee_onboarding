/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: form_action
function_name: mark_review
form_no: 1
action_name: Review
language: plpgsql
description: Move candidate to Review
functional_specification: Set STATUS='Review' and stamp STATUS_DATE = now(). Return a confirmation message.
business_logic: Move candidate to Review
*/

CREATE OR REPLACE FUNCTION emponb_candidate_record__mark_review(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_candidate_id CHAR(10);
BEGIN
    -- Identify the candidate from the form payload
    v_candidate_id := p->>'candidate_id';

    IF v_candidate_id IS NULL OR TRIM(v_candidate_id) = '' THEN
        RETURN jsonb_build_object('error', 'Candidate ID is missing.');
    END IF;

    -- Move candidate to Review and stamp the status change timestamp
    UPDATE EMPONB_CANDIDATE_RECORD
       SET STATUS      = 'Review',
           STATUS_DATE = now()
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found.');
    END IF;

    RETURN jsonb_build_object('message', 'Candidate moved to Review.');
END;
$$;
