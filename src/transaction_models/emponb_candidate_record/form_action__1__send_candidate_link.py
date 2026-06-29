# project: Employee_onboarding
# object_type: T
# object_name: emponb_candidate_record
# event_type: form_action
# function_name: send_candidate_link
# form_no: 1
# action_name: Send/Resend Link
# language: python
# description: Generate access key and email the candidate link
# functional_specification: Generate a unique ACCESS_KEY, set KEY_GENERATED_ON = now() and KEY_EXPIRY_DATETIME = KEY_GENERATED_ON + :key_validity_days days, set KEY_VALID_FLAG='Y', build FORM_URL (external candidate form + key), set STATUS='Link Generated', stamp STATUS_DATE and LINK_SENT_ON, then send-email the candidate the link using the configured template. Return a confirmation message.
# business_logic: Generate access key and email the candidate link
