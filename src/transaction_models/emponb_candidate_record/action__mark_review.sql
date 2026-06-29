/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: action
function_name: mark_review
action_name: Review
language: plpgsql
description: Move record to Review
functional_specification: Set STATUS='Review' and stamp STATUS_DATE=now(). Return a confirmation message.
business_logic: Move record to Review
*/

CREATE OR REPLACE FUNCTION emponb_candidate_record__mark_review(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id char(10) := p->>'CANDIDATE_ID';
BEGIN
    IF v_candidate_id IS NULL OR btrim(v_candidate_id) = '' THEN
        RETURN jsonb_build_object('error', 'Candidate id is required.');
    END IF;

    UPDATE EMPONB_CANDIDATE_RECORD
       SET STATUS      = 'Review',
           STATUS_DATE = now()
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found.');
    END IF;

    RETURN jsonb_build_object('prompts',
             jsonb_build_array(jsonb_build_object(
                 'code', 'MRVW01', 'type', 'P',
                 'message', 'Candidate moved to Review.')));
END;
$$;
