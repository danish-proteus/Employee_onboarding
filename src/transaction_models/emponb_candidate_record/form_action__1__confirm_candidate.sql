/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: form_action
function_name: confirm_candidate
form_no: 1
action_name: Confirm
language: plpgsql
description: Push to IOFLOW Employee and confirm
functional_specification: Trigger the IOFLOW Employee-creation API with the consolidated payload (personal + finalization + pay-structure rows where UPD_PAYSTRU='Y'); store EMPLOYEE_PUSHED_FLAG='Y' and EMPLOYEE_PUSH_REF from the response; set STATUS='Confirmed' and stamp STATUS_DATE; send a notification email to the INITIATED_BY HR user. Roll back with an error if the IOFLOW call fails.
business_logic: Push to IOFLOW Employee and confirm
*/
