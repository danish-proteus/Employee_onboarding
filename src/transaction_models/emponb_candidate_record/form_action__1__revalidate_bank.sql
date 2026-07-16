/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: form_action
function_name: revalidate_bank
form_no: 1
action_name: Re-validate Bank
language: plpgsql
description: Re-validate bank via IOFLOW
functional_specification: Invoke the IOFLOW bank endpoint with BANK_ACCOUNT_NO and BANK_IFSC_CODE; store BANK_VALIDATED and BANK_VALIDATED_NAME and increment BANK_ATTEMPTS. Block beyond :max_validation_attempts. Return a result message.
business_logic: Re-validate bank via IOFLOW
*/

CREATE OR REPLACE FUNCTION revalidate_bank(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_candidate_id   char(10);
    v_account_no     varchar(20);
    v_ifsc_code      char(11);
    v_attempts       integer;
    v_max_attempts   integer;
    v_validated      char(1);
    v_validated_name varchar(100);
    v_ioflow         jsonb;
BEGIN
    -- Read inputs from the form payload
    v_candidate_id := p->>'CANDIDATE_ID';
    v_account_no   := p->>'BANK_ACCOUNT_NO';
    v_ifsc_code    := p->>'BANK_IFSC_CODE';

    -- Maximum permitted validation attempts (bind param, sensible default)
    v_max_attempts := COALESCE(NULLIF(p->>'max_validation_attempts','')::integer, 3);

    -- Basic input guards
    IF v_candidate_id IS NULL OR TRIM(v_candidate_id) = '' THEN
        RETURN jsonb_build_object('error', 'Candidate record must be saved before bank re-validation.');
    END IF;

    IF v_account_no IS NULL OR TRIM(v_account_no) = ''
       OR v_ifsc_code IS NULL OR TRIM(v_ifsc_code) = '' THEN
        RETURN jsonb_build_object('error', 'Bank Account No and IFSC Code are required to re-validate the bank.');
    END IF;

    -- Current attempt count for this candidate
    SELECT COALESCE(BANK_ATTEMPTS, 0)
      INTO v_attempts
      FROM EMPONB_CANDIDATE_RECORD
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found.');
    END IF;

    -- Block once the maximum number of attempts has been exhausted
    IF v_attempts >= v_max_attempts THEN
        RETURN jsonb_build_object(
            'error',
            format('Maximum bank validation attempts (%s) reached. Please contact HR.', v_max_attempts)
        );
    END IF;

    -- Invoke the IOFLOW bank validation endpoint with account no + IFSC code.
    -- ioflow(<endpoint>, <request payload>) returns the validation response as jsonb.
    v_ioflow := ioflow(
        'bank',
        jsonb_build_object(
            'BANK_ACCOUNT_NO', v_account_no,
            'BANK_IFSC_CODE',  v_ifsc_code
        )
    );

    -- Interpret the IOFLOW response
    v_validated      := CASE WHEN COALESCE(v_ioflow->>'valid', 'false')::boolean THEN 'Y' ELSE 'N' END;
    v_validated_name := v_ioflow->>'name';

    -- Persist the outcome and record this attempt
    UPDATE EMPONB_CANDIDATE_RECORD
       SET BANK_VALIDATED      = v_validated,
           BANK_VALIDATED_NAME = v_validated_name,
           BANK_ATTEMPTS       = COALESCE(BANK_ATTEMPTS, 0) + 1
     WHERE CANDIDATE_ID = v_candidate_id;

    -- Report the result to the user
    IF v_validated = 'Y' THEN
        RETURN jsonb_build_object(
            'updates', jsonb_build_object(
                'BANK_VALIDATED', v_validated,
                'BANK_VALIDATED_NAME', v_validated_name,
                'BANK_ATTEMPTS', v_attempts + 1
            ),
            'message', format('Bank account verified successfully. Name on account: %s',
                              COALESCE(v_validated_name, 'N/A'))
        );
    ELSE
        RETURN jsonb_build_object(
            'updates', jsonb_build_object(
                'BANK_VALIDATED', v_validated,
                'BANK_VALIDATED_NAME', v_validated_name,
                'BANK_ATTEMPTS', v_attempts + 1
            ),
            'message', format('Bank validation failed. Attempt %s of %s.', v_attempts + 1, v_max_attempts)
        );
    END IF;
END;
$$;
