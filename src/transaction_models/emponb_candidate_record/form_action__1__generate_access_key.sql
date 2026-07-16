/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: form_action
function_name: generate_access_key
form_no: 1
action_name: Generate Key
language: plpgsql
description: Generate a new access key and update all related columns
functional_specification: Generate a new unique ACCESS_KEY, set KEY_GENERATED_ON = now() and KEY_EXPIRY_DATETIME = KEY_GENERATED_ON + KEY_VALIDITY_DAYS days (from EMPONB_ONBOARDING_SETTINGS), set KEY_VALID_FLAG='Y', build FORM_URL as the full absolute URL of the public candidate onboarding portal (external site slug 'onboarding') with the generated key appended, set STATUS='Link Generated', stamp STATUS_DATE. PERSIST all of these on the candidate record. Return a confirmation message with the generated link. This action only generates/regenerates the key; it does NOT raise the send-link event.
business_logic: Generate a new access key and update all related columns
*/
