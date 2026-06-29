/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: action
function_name: revalidate_bank
action_name: Re-validate Bank
language: plpgsql
description: Re-validate bank via IOFLOW
functional_specification: Invoke the IOFLOW Bank endpoint with BANK_ACCOUNT_NO and BANK_IFSC_CODE; store BANK_VALIDATED and BANK_VALIDATED_NAME and increment BANK_ATTEMPTS. Block if BANK_ATTEMPTS has reached :max_validation_attempts. Return the outcome message.
business_logic: Re-validate bank via IOFLOW
*/

CREATE OR REPLACE FUNCTION emponb_candidate_record__revalidate_bank(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id char(10) := p->>'CANDIDATE_ID';
    v_account      varchar(20);
    v_ifsc         char(11);
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

    SELECT BANK_ACCOUNT_NO, BANK_IFSC_CODE, COALESCE(BANK_ATTEMPTS, 0)
      INTO v_account, v_ifsc, v_attempts
      FROM EMPONB_CANDIDATE_RECORD
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found.');
    END IF;

    IF v_account IS NULL OR btrim(v_account) = '' OR v_ifsc IS NULL OR btrim(v_ifsc) = '' THEN
        RETURN jsonb_build_object('error', 'Bank account number and IFSC code are required.');
    END IF;

    -- Onboarding configuration (single settings row).
    SELECT MAX_VALIDATION_ATTEMPTS, IOFLOW_BASE_URL, IOFLOW_BANK_ENDPOINT, IOFLOW_AUTH_TOKEN
      INTO v_max_attempts, v_base_url, v_endpoint, v_token
      FROM EMPONB_ONBOARDING_SETTINGS
     ORDER BY SETTINGS_ID
     LIMIT 1;

    IF v_max_attempts IS NULL THEN
        RETURN jsonb_build_object('error', 'Onboarding settings are not configured.');
    END IF;

    IF v_attempts >= v_max_attempts THEN
        RETURN jsonb_build_object('error',
            'Maximum bank validation attempts (' || v_max_attempts || ') reached.');
    END IF;

    -- Invoke the IOFLOW Bank endpoint.
    SELECT content::jsonb
      INTO v_resp
      FROM http((
            'POST',
            rtrim(v_base_url, '/') || '/' || ltrim(v_endpoint, '/'),
            ARRAY[http_header('Authorization', 'Bearer ' || v_token)],
            'application/json',
            jsonb_build_object('account_no', v_account, 'ifsc_code', v_ifsc)::text
        )::http_request);

    v_validated := CASE WHEN upper(COALESCE(v_resp->>'validated','N')) IN ('Y','TRUE','VALID')
                        THEN 'Y' ELSE 'N' END;
    v_val_name  := v_resp->>'name';

    UPDATE EMPONB_CANDIDATE_RECORD
       SET BANK_VALIDATED      = v_validated,
           BANK_VALIDATED_NAME = v_val_name,
           BANK_ATTEMPTS       = v_attempts + 1
     WHERE CANDIDATE_ID = v_candidate_id;

    RETURN jsonb_build_object('prompts',
             jsonb_build_array(jsonb_build_object(
                 'code', 'BNKV01', 'type', 'P',
                 'message', CASE WHEN v_validated = 'Y'
                                 THEN 'Bank account validated successfully' ||
                                      COALESCE(' (' || v_val_name || ')', '') || '.'
                                 ELSE 'Bank account could not be validated.' END)));
END;
$$;
