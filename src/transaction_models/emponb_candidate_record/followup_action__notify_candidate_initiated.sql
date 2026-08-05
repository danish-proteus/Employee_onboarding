/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: followup_action
function_name: notify_candidate_initiated
action_name: candidate_initiated_notice
condition: on-add
language: plpgsql
description: Notify HR that a candidate record was initiated
functional_specification: After a new candidate record is added, send a confirmation notification to INITIATED_BY summarizing the new CANDIDATE_ID and CANDIDATE_NAME.
business_logic: Notify HR that a candidate record was initiated
*/

CREATE OR REPLACE FUNCTION notify_candidate_initiated(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_candidate_id   varchar(10) := NULLIF(TRIM(COALESCE(p->>'CANDIDATE_ID', p->>'candidate_id')), '');
    v_candidate_name varchar(100);
    v_initiated_by   varchar(10);
    v_design_code    varchar(10);
    v_email_id       varchar(120);
    v_ioflow         jsonb;
BEGIN
    -- Nothing to notify about without a candidate key.
    IF v_candidate_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Read the persisted row so the notice reflects what was actually saved
    -- (defaults such as INITIATED_BY are stamped by the engine at insert).
    SELECT CANDIDATE_NAME, INITIATED_BY, DESIGN_CODE, EMAIL_ID
      INTO v_candidate_name, v_initiated_by, v_design_code, v_email_id
      FROM EMPONB_CANDIDATE_RECORD
     WHERE CANDIDATE_ID = v_candidate_id;

    -- No row (or no recipient) — a follow-up notice must never block the save.
    IF NOT FOUND OR COALESCE(TRIM(v_initiated_by), '') = '' THEN
        RETURN NULL;
    END IF;

    -- Send the confirmation to the HR user who initiated the record.
    v_ioflow := ioflow_call(
        'EmpOnboardingNotify',
        jsonb_build_object(
            'operation',      'CandidateInitiated',
            'to_user',        TRIM(v_initiated_by),
            'candidate_id',   v_candidate_id,
            'candidate_name', v_candidate_name,
            'design_code',    v_design_code,
            'email_id',       v_email_id,
            'subject',        'Candidate onboarding initiated: ' || v_candidate_id,
            'message',        'Candidate ' || v_candidate_id || ' (' ||
                              COALESCE(v_candidate_name, '') ||
                              ') has been initiated for onboarding.'
        )
    );

    -- Follow-up actions are informational only: swallow a delivery failure so a
    -- notification problem can never roll back or block the candidate record.
    RETURN NULL;
END;
$$;
