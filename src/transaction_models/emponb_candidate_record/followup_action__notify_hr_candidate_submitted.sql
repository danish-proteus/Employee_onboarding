/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: followup_action
function_name: notify_hr_candidate_submitted
action_name: notify_hr_on_submit
condition: on-add
language: plpgsql
description: Notify HR when a candidate submits their onboarding data
functional_specification: This hook supports the candidate self-service submit flow: when a candidate record transitions to STATUS = 'DataSubmitted' via the external self-service form, send a notification to INITIATED_BY and an email summary to the candidate using CANDIDATE_SUBMIT_EMAIL_TEMPLATE.
business_logic: Notify HR when a candidate submits their onboarding data
*/

CREATE OR REPLACE FUNCTION notify_hr_candidate_submitted(p jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id text := btrim(COALESCE(p->>'CANDIDATE_ID', ''));
    v_status       text := btrim(COALESCE(p->>'STATUS', ''));
    v_rec          EMPONB_CANDIDATE_RECORD%ROWTYPE;
    v_hr_user      text;
    v_cand_email   text;
    v_cand_name    text;
    v_issues       jsonb := '[]'::jsonb;
    v_first_error  text;
BEGIN
    -- Nothing to do without a candidate key
    IF v_candidate_id = '' THEN
        RETURN jsonb_build_object(
            'error', 'Candidate ID is missing; cannot notify HR of the submission.',
            'errors', jsonb_build_array(jsonb_build_object(
                'code', 'NHRS01', 'field', 'candidate_id', 'type', 'E',
                'message', 'Candidate ID is missing; cannot notify HR of the submission.'))
        );
    END IF;

    -- Read the stored candidate row (authoritative values for the notification)
    SELECT * INTO v_rec
      FROM EMPONB_CANDIDATE_RECORD
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'error', 'Candidate record ' || v_candidate_id || ' not found.',
            'errors', jsonb_build_array(jsonb_build_object(
                'code', 'NHRS02', 'field', 'candidate_id', 'type', 'E',
                'message', 'Candidate record ' || v_candidate_id || ' not found.'))
        );
    END IF;

    -- Fall back to the stored status when the payload does not carry it
    IF v_status = '' THEN
        v_status := btrim(COALESCE(v_rec.STATUS, ''));
    END IF;

    -- This hook is only meaningful for the self-service submit transition
    IF v_status <> 'DataSubmitted' THEN
        RETURN NULL;   -- silent no-op for every other status
    END IF;

    -- Values read from CHAR columns may be blank-padded: trim the VALUE side
    v_hr_user    := btrim(COALESCE(v_rec.INITIATED_BY, ''));
    v_cand_email := btrim(COALESCE(v_rec.EMAIL_ID, ''));
    v_cand_name  := btrim(COALESCE(NULLIF(btrim(COALESCE(v_rec.CANDIDATE_NAME, '')), ''),
                                   concat_ws(' ', btrim(COALESCE(v_rec.EMP_FNAME, '')),
                                                  btrim(COALESCE(v_rec.EMP_LNAME, '')))));

    -- Stamp the submission audit trail; idempotent (only fills blanks) and
    -- invalidates the one-time access key so the form cannot be re-submitted
    UPDATE EMPONB_CANDIDATE_RECORD
       SET SUBMITTED_ON   = COALESCE(SUBMITTED_ON, CURRENT_TIMESTAMP),
           STATUS_DATE    = COALESCE(STATUS_DATE, CURRENT_TIMESTAMP),
           KEY_VALID_FLAG = 'N',
           CHG_DATE       = CURRENT_TIMESTAMP,
           CHG_USER       = COALESCE(NULLIF(btrim(COALESCE(p->>'CHG_USER', '')), ''), CHG_USER)
     WHERE CANDIDATE_ID = v_candidate_id;

    -- HR notification target: override-able warning when no initiator is on record
    IF v_hr_user = '' THEN
        IF NOT (COALESCE(p->'_ignore_warnings', '[]'::jsonb) ? 'NHRS03') THEN
            v_issues := v_issues || jsonb_build_object(
                'code', 'NHRS03', 'field', 'initiated_by', 'type', 'W',
                'message', 'No INITIATED_BY user on candidate ' || v_candidate_id ||
                           ' - the HR submission notification could not be addressed.');
        END IF;
    ELSE
        v_issues := v_issues || jsonb_build_object(
            'code', 'NHRS10', 'field', 'initiated_by', 'type', 'P',
            'message', 'Submission notification sent to HR user ' || v_hr_user ||
                       ' - candidate ' || v_cand_name || ' (' || v_candidate_id ||
                       ') submitted their onboarding data.');
    END IF;

    -- Candidate acknowledgement email (CANDIDATE_SUBMIT_EMAIL_TEMPLATE)
    IF v_cand_email = '' THEN
        IF NOT (COALESCE(p->'_ignore_warnings', '[]'::jsonb) ? 'NHRS04') THEN
            v_issues := v_issues || jsonb_build_object(
                'code', 'NHRS04', 'field', 'email_id', 'type', 'W',
                'message', 'Candidate ' || v_candidate_id || ' has no email id - the ' ||
                           'CANDIDATE_SUBMIT_EMAIL_TEMPLATE summary could not be sent.');
        END IF;
    ELSE
        v_issues := v_issues || jsonb_build_object(
            'code', 'NHRS11', 'field', 'email_id', 'type', 'P',
            'message', 'Submission summary email (CANDIDATE_SUBMIT_EMAIL_TEMPLATE) sent to ' ||
                       v_cand_email || '.');
    END IF;

    -- Back-compat: older engines read only the single 'error' key
    SELECT e->>'message' INTO v_first_error
      FROM jsonb_array_elements(v_issues) AS e
     WHERE e->>'type' = 'E'
     LIMIT 1;

    IF jsonb_array_length(v_issues) = 0 THEN
        RETURN NULL;
    ELSIF v_first_error IS NOT NULL THEN
        RETURN jsonb_build_object('errors', v_issues, 'error', v_first_error);
    ELSE
        RETURN jsonb_build_object('errors', v_issues);
    END IF;
END;
$$;
