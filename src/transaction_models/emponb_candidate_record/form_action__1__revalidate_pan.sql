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
