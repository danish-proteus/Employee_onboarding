/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: action
function_name: revalidate_aadhar
action_name: Re-validate Aadhar
language: plpgsql
description: Re-validate Aadhar via IOFLOW
functional_specification: Invoke the IOFLOW Aadhar endpoint with AADHAR_NO; store AADHAR_VALIDATED and AADHAR_VALIDATED_NAME and increment AADHAR_ATTEMPTS. Block if AADHAR_ATTEMPTS has reached :max_validation_attempts. Return the outcome message.
business_logic: Re-validate Aadhar via IOFLOW
*/

CREATE OR REPLACE FUNCTION emponb_candidate_record__revalidate_aadhar(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id char(10) := p->>'CANDIDATE_ID';
    v_aadhar       char(12);
    v_attempts     integer;
    v_max_attempts integer;
    v_base_url     varchar(500);
    v_endpoint     varchar(500);
    v_token        varchar(500);
    v_resp         jsonb;
    v_validated    char(1);
    v_val_name     varchar(100);
BEGIN
    IF v_candidate_id IS NULL OR btrim(v_candidate_id) = '' THEN
        RETURN jsonb_build_object('error', 'Candidate id is required.');
    END IF;

    SELECT AADHAR_NO, COALESCE(AADHAR_ATTEMPTS, 0)
      INTO v_aadhar, v_attempts
      FROM EMPONB_CANDIDATE_RECORD
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found.');
    END IF;

    IF v_aadhar IS NULL OR btrim(v_aadhar) = '' THEN
        RETURN jsonb_build_object('error', 'Aadhar number is not entered.');
    END IF;

    -- Onboarding configuration (single settings row).
    SELECT MAX_VALIDATION_ATTEMPTS, IOFLOW_BASE_URL, IOFLOW_AADHAR_ENDPOINT, IOFLOW_AUTH_TOKEN
      INTO v_max_attempts, v_base_url, v_endpoint, v_token
      FROM EMPONB_ONBOARDING_SETTINGS
     ORDER BY SETTINGS_ID
     LIMIT 1;

    IF v_max_attempts IS NULL THEN
        RETURN jsonb_build_object('error', 'Onboarding settings are not configured.');
    END IF;

    IF v_attempts >= v_max_attempts THEN
        RETURN jsonb_build_object('error',
            'Maximum Aadhar validation attempts (' || v_max_attempts || ') reached.');
    END IF;

    -- Invoke the IOFLOW Aadhar endpoint.
    SELECT content::jsonb
      INTO v_resp
      FROM http((
            'POST',
            rtrim(v_base_url, '/') || '/' || ltrim(v_endpoint, '/'),
            ARRAY[http_header('Authorization', 'Bearer ' || v_token)],
            'application/json',
            jsonb_build_object('aadhar_no', v_aadhar)::text
        )::http_request);

    v_validated := CASE WHEN upper(COALESCE(v_resp->>'validated','N')) IN ('Y','TRUE','VALID')
                        THEN 'Y' ELSE 'N' END;
    v_val_name  := v_resp->>'name';

    UPDATE EMPONB_CANDIDATE_RECORD
       SET AADHAR_VALIDATED      = v_validated,
           AADHAR_VALIDATED_NAME = v_val_name,
           AADHAR_ATTEMPTS       = v_attempts + 1
     WHERE CANDIDATE_ID = v_candidate_id;

    RETURN jsonb_build_object('prompts',
             jsonb_build_array(jsonb_build_object(
                 'code', 'AADV01', 'type', 'P',
                 'message', CASE WHEN v_validated = 'Y'
                                 THEN 'Aadhar validated successfully' ||
                                      COALESCE(' (' || v_val_name || ')', '') || '.'
                                 ELSE 'Aadhar could not be validated.' END)));
END;
$$;
