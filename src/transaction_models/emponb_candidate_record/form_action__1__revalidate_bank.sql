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
