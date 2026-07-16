/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: form_action
function_name: revalidate_pan
form_no: 1
action_name: Re-validate PAN
language: plpgsql
description: Re-validate PAN via IOFLOW
functional_specification: Invoke the IOFLOW PAN endpoint with PAN_NO; store PAN_VALIDATED and PAN_VALIDATED_NAME from the response and increment PAN_ATTEMPTS. Block the call and return an error if PAN_ATTEMPTS has already reached :max_validation_attempts. Return a result message.
business_logic: Re-validate PAN via IOFLOW
*/

CREATE OR REPLACE FUNCTION revalidate_pan(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_candidate_id   char(10) := p->>'candidate_id';
    v_pan_no         char(10) := p->>'pan_no';
    v_attempts       integer;
    v_max_attempts   integer  := COALESCE((p->>'max_validation_attempts')::integer, 3);
    v_ioflow         jsonb;
    v_validated      char(1);
    v_validated_name varchar(100);
BEGIN
    -- Guard: candidate must be identified
    IF v_candidate_id IS NULL THEN
        RETURN jsonb_build_object('error', 'Candidate not identified.');
    END IF;

    -- PAN is mandatory for validation
    IF v_pan_no IS NULL OR TRIM(v_pan_no) = '' THEN
        RETURN jsonb_build_object('error', 'PAN number is not available to validate.');
    END IF;

    -- Read the current attempt count from the record
    SELECT COALESCE(PAN_ATTEMPTS, 0)
      INTO v_attempts
      FROM EMPONB_CANDIDATE_RECORD
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found.');
    END IF;

    -- Block once the maximum number of attempts has been reached
    IF v_attempts >= v_max_attempts THEN
        RETURN jsonb_build_object(
            'error',
            'Maximum PAN validation attempts (' || v_max_attempts || ') already reached.'
        );
    END IF;

    -- Invoke the IOFLOW PAN endpoint with the PAN number.
    -- ioflow_call(<endpoint>, <request-payload>) returns a jsonb response.
    v_ioflow := ioflow_call('PAN', jsonb_build_object('PAN_NO', v_pan_no));

    -- Map the response into stored columns
    v_validated      := CASE
                            WHEN COALESCE(v_ioflow->>'valid', 'N') IN ('Y', 'true', 'TRUE', '1')
                            THEN 'Y' ELSE 'N'
                        END;
    v_validated_name := v_ioflow->>'name';

    -- Persist the result and increment the attempt counter
    UPDATE EMPONB_CANDIDATE_RECORD
       SET PAN_VALIDATED      = v_validated,
           PAN_VALIDATED_NAME = v_validated_name,
           PAN_ATTEMPTS       = COALESCE(PAN_ATTEMPTS, 0) + 1
     WHERE CANDIDATE_ID = v_candidate_id;

    -- Return a user-facing result message
    IF v_validated = 'Y' THEN
        RETURN jsonb_build_object(
            'message',
            'PAN validated successfully. Name as per PAN: ' || COALESCE(v_validated_name, '')
        );
    ELSE
        RETURN jsonb_build_object(
            'message',
            'PAN could not be validated. Attempt ' || (v_attempts + 1) || ' of ' || v_max_attempts || '.'
        );
    END IF;
END;
$$;
