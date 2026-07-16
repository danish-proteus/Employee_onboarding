/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: form_action
function_name: revalidate_aadhar
form_no: 1
action_name: Re-validate Aadhar
language: plpgsql
description: Re-validate Aadhaar via IOFLOW
functional_specification: Invoke the IOFLOW Aadhaar endpoint with AADHAR_NO; store AADHAR_VALIDATED and AADHAR_VALIDATED_NAME and increment AADHAR_ATTEMPTS. Block beyond :max_validation_attempts. Return a result message.
business_logic: Re-validate Aadhaar via IOFLOW
*/

CREATE OR REPLACE FUNCTION revalidate_aadhar(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_candidate_id   char(10) := p->>'candidate_id';
    v_aadhar_no      char(12) := p->>'aadhar_no';
    v_attempts       integer  := COALESCE((p->>'aadhar_attempts')::integer, 0);
    v_max_attempts   integer  := COALESCE((p->>'max_validation_attempts')::integer, 3);
    v_ioflow         jsonb;
    v_valid          char(1);
    v_valid_name     text;
BEGIN
    -- Nothing to validate without an Aadhaar number
    IF v_aadhar_no IS NULL OR btrim(v_aadhar_no) = '' THEN
        RETURN jsonb_build_object('message', 'Please enter an Aadhaar number before re-validating.');
    END IF;

    -- Block once the configured maximum number of attempts has been reached
    IF v_attempts >= v_max_attempts THEN
        RETURN jsonb_build_object(
            'message',
            'Maximum Aadhaar validation attempts (' || v_max_attempts || ') reached. Please contact HR.'
        );
    END IF;

    -- Invoke the IOFLOW Aadhaar validation endpoint with the Aadhaar number.
    -- ioflow_call(<endpoint>, <request payload>) returns the provider response as jsonb,
    -- e.g. {"valid":"Y","name":"<name on Aadhaar>"}.
    v_ioflow := ioflow_call(
                    'aadhaar/validate',
                    jsonb_build_object('aadhar_no', v_aadhar_no)
                );

    v_valid      := COALESCE(UPPER(v_ioflow->>'valid'), 'N');
    IF v_valid <> 'Y' THEN
        v_valid := 'N';
    END IF;
    v_valid_name := v_ioflow->>'name';

    -- Increment attempt counter, and persist the validation outcome on the candidate record.
    v_attempts := v_attempts + 1;

    UPDATE emponb_candidate_record
       SET aadhar_validated      = v_valid,
           aadhar_validated_name = v_valid_name,
           aadhar_attempts       = v_attempts
     WHERE candidate_id = v_candidate_id;

    RETURN jsonb_build_object(
        'updates', jsonb_build_object(
            'aadhar_validated',      v_valid,
            'aadhar_validated_name', v_valid_name,
            'aadhar_attempts',       v_attempts
        ),
        'message',
        CASE
            WHEN v_valid = 'Y'
                THEN 'Aadhaar validated successfully' ||
                     CASE WHEN v_valid_name IS NOT NULL
                          THEN ' (' || v_valid_name || ').'
                          ELSE '.' END
            ELSE 'Aadhaar validation failed. ' ||
                 (v_max_attempts - v_attempts) || ' attempt(s) remaining.'
        END
    );
END;
$$;
