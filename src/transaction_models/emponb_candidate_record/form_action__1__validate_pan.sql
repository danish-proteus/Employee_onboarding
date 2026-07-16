/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: form_action
function_name: validate_pan
form_no: 1
action_name: Validate PAN
language: plpgsql
description: Call IOFLOW event EmpOnboardingValidate to validate the candidate PAN
functional_specification: On-record action for a single loaded candidate. Read CANDIDATE_ID and PAN_NO from the loaded EMPONB_CANDIDATE_RECORD row. Call the IOFLOW event EmpOnboardingValidate (operation='ValidatePAN') to validate the candidate PAN. Return a result message; surface any IOFLOW error to the user.
business_logic: Call IOFLOW event EmpOnboardingValidate to validate the candidate PAN
*/

CREATE OR REPLACE FUNCTION validate_pan(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    -- Header columns off the currently loaded candidate row.
    v_candidate_id char(10)     := p->>'candidate_id';
    v_pan_no       char(10)     := p->>'pan_no';
    v_ioflow       jsonb;        -- raw IOFLOW response
    v_success      boolean;      -- did EmpOnboardingValidate report success?
    v_error_msg    text;         -- error text returned by IOFLOW (if any)
    v_pan_name     varchar(100); -- name as per PAN, when validated
BEGIN
    -- Guard: candidate must be identified from the loaded row.
    IF v_candidate_id IS NULL OR TRIM(v_candidate_id) = '' THEN
        RETURN jsonb_build_object('error', 'Candidate not identified.');
    END IF;

    -- If PAN_NO was not sent on the header envelope, read it from the loaded row.
    IF v_pan_no IS NULL OR TRIM(v_pan_no) = '' THEN
        SELECT PAN_NO
          INTO v_pan_no
          FROM EMPONB_CANDIDATE_RECORD
         WHERE CANDIDATE_ID = v_candidate_id;
    END IF;

    -- Edge case: PAN is mandatory to validate. Ask the user to enter one first.
    IF v_pan_no IS NULL OR TRIM(v_pan_no) = '' THEN
        RETURN jsonb_build_object(
            'error', 'Please enter a PAN number before validating.'
        );
    END IF;

    -- Invoke the IOFLOW event EmpOnboardingValidate to validate the PAN.
    -- Mirrors the external-integration call in action__send_candidate_link
    -- (api.emit_event there); the plpgsql equivalent is the project's standard
    -- ioflow_call(<event>, <payload>) helper, which returns a jsonb response.
    v_ioflow := ioflow_call(
        'EmpOnboardingValidate',
        jsonb_build_object(
            'operation',    'ValidatePAN',
            'candidate_id', v_candidate_id,
            'pan_no',       v_pan_no
        )
    );

    -- Interpret the response. Treat an explicit success/valid flag as success;
    -- a missing/false flag (or an error key) is a non-success response.
    v_success := COALESCE(v_ioflow->>'success', v_ioflow->>'valid', 'N')
                 IN ('Y', 'y', 'true', 'TRUE', 'True', '1');
    v_error_msg := COALESCE(v_ioflow->>'error', v_ioflow->>'message');

    -- On a non-success response, surface the returned error message to the user.
    IF v_ioflow IS NULL OR NOT v_success THEN
        RETURN jsonb_build_object(
            'error',
            COALESCE(NULLIF(TRIM(v_error_msg), ''), 'PAN validation failed.')
        );
    END IF;

    -- Success: persist the validated flag and the name as per PAN, then confirm.
    v_pan_name := v_ioflow->>'name';

    UPDATE EMPONB_CANDIDATE_RECORD
       SET PAN_VALIDATED      = 'Y',
           PAN_VALIDATED_NAME = v_pan_name,
           PAN_ATTEMPTS       = COALESCE(PAN_ATTEMPTS, 0) + 1
     WHERE CANDIDATE_ID = v_candidate_id;

    RETURN jsonb_build_object(
        'message',
        'PAN validated successfully.' ||
        CASE
            WHEN COALESCE(TRIM(v_pan_name), '') <> ''
            THEN ' Name as per PAN: ' || v_pan_name
            ELSE ''
        END
    );
END;
$$;
