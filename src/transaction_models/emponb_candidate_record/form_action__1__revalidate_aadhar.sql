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
