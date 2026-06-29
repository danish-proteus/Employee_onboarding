/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: followup_action
function_name: init_candidate
action_name: init_candidate
condition: on-add
language: plpgsql
description: Initialise a new candidate
functional_specification: On add/initiate, ensure CANDIDATE_ID is generated, set STATUS='Initiated' and stamp STATUS_DATE, INITIATED_BY and INITIATED_ON if not already set.
business_logic: Initialise a new candidate
*/

CREATE OR REPLACE FUNCTION emponb_candidate_record__init_candidate(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id char(10) := p->>'CANDIDATE_ID';
    v_new_id       char(10);
BEGIN
    -- Generate a CANDIDATE_ID when the new record does not already carry one
    IF v_candidate_id IS NULL OR btrim(v_candidate_id) = '' THEN
        SELECT lpad((COALESCE(MAX((CANDIDATE_ID)::bigint), 0) + 1)::text, 10, '0')
          INTO v_new_id
          FROM EMPONB_CANDIDATE_RECORD
         WHERE CANDIDATE_ID ~ '^[0-9]+$';
        v_candidate_id := COALESCE(v_new_id, lpad('1', 10, '0'));
    END IF;

    -- Initialise status / initiation stamps only when not already populated.
    UPDATE EMPONB_CANDIDATE_RECORD
       SET STATUS       = COALESCE(STATUS, 'Initiated'),
           STATUS_DATE  = COALESCE(STATUS_DATE, now()),
           INITIATED_BY = COALESCE(INITIATED_BY, p->>'ADD_USER', p->>'CHG_USER'),
           INITIATED_ON = COALESCE(INITIATED_ON, now())
     WHERE CANDIDATE_ID = v_candidate_id;

    RETURN NULL;
END;
$$;
