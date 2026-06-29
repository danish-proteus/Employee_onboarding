/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: form_action
function_name: cancel_candidate
form_no: 1
action_name: Cancel
language: plpgsql
description: Cancel the candidate record
functional_specification: Set STATUS='Cancelled', stamp STATUS_DATE, set KEY_VALID_FLAG='N' to invalidate any outstanding link. Return a confirmation message.
business_logic: Cancel the candidate record
*/
