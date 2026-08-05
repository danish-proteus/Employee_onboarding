/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: form_action
function_name: emponb_candidate_record__mark_review
form_no: 1
action_name: Review
language: plpgsql
description: Move candidate to Review
functional_specification: Set STATUS='Review' and stamp STATUS_DATE = now(). Return a confirmation message.
business_logic: Move candidate to Review
*/

CREATE OR REPLACE FUNCTION emponb_candidate_record__mark_review(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id text := TRIM(COALESCE(p->>'CANDIDATE_ID', ''));
    v_name         text;
    v_status       text;
    v_now          timestamp := now();
BEGIN
    IF v_candidate_id = '' THEN
        RETURN jsonb_build_object(
                 'error', 'Candidate record must be saved before it can be moved to Review.',
                 'errors', jsonb_build_array(jsonb_build_object(
                     'code', 'MRV001', 'field', 'CANDIDATE_ID', 'type', 'E',
                     'message', 'Candidate record must be saved before it can be moved to Review.')));
    END IF;

    SELECT TRIM(COALESCE(c.STATUS, '')), c.CANDIDATE_NAME
      INTO v_status, v_name
      FROM EMPONB_CANDIDATE_RECORD c
     WHERE c.CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found: ' || v_candidate_id);
    END IF;

    -- A confirmed or cancelled candidate can no longer be pulled back into Review.
    IF v_status IN ('Confirmed', 'Cancelled') THEN
        RETURN jsonb_build_object(
                 'error', 'A ' || v_status || ' candidate cannot be moved to Review.',
                 'errors', jsonb_build_array(jsonb_build_object(
                     'code', 'MRV002', 'field', 'STATUS', 'type', 'E',
                     'message', 'A ' || v_status || ' candidate cannot be moved to Review.')));
    END IF;

    IF v_status = 'Review' THEN
        -- Already in Review: nothing to change, just inform the user.
        RETURN jsonb_build_object('prompts', jsonb_build_array(jsonb_build_object(
                   'code', 'MRV900', 'type', 'P',
                   'message', 'Candidate is already under Review.')));
    END IF;

    UPDATE EMPONB_CANDIDATE_RECORD
       SET STATUS      = 'Review',
           STATUS_DATE = v_now,
           CHG_DATE    = v_now
     WHERE CANDIDATE_ID = v_candidate_id;

    RETURN jsonb_build_object('prompts', jsonb_build_array(jsonb_build_object(
               'code', 'MRV901', 'type', 'P',
               'message', 'Candidate ' || COALESCE(TRIM(v_name), v_candidate_id)
                          || ' moved to Review on ' || to_char(v_now, 'DD-Mon-YYYY HH24:MI') || '.')));
END;
$$;
