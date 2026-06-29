# project: Employee_onboarding
# object_type: T
# object_name: emponb_candidate_record
# event_type: action
# function_name: send_candidate_link
# action_name: Send/Resend Link
# language: python
# description: Generate key and send onboarding link
# functional_specification: Generate a unique ACCESS_KEY, set KEY_GENERATED_ON=now(),
#   compute KEY_EXPIRY_DATETIME = KEY_GENERATED_ON + :key_validity_days days, set
#   KEY_VALID_FLAG='Y', build FORM_URL (external candidate form + key), set
#   STATUS='Link Generated', stamp STATUS_DATE and LINK_SENT_ON. Send an email to the
#   candidate (EMAIL_ID) with the link. Return a confirmation message.
# business_logic: Generate key and send onboarding link


def run(args):
    """Send / resend the candidate onboarding link.

    `args` is a case-insensitive dict of the current row's columns plus any
    project variables referenced by the action (`:key_validity_days`,
    `:ioflow_base_url`). The function computes the access-key fields and returns
    them as `updates` for the engine to persist on the row, an `email` request
    for the notification listener to dispatch, and a confirmation `message`.
    """
    candidate_id = coalesce(args.get("candidate_id"), "")
    email = coalesce(args.get("email_id"), "")
    status = coalesce(args.get("status"), "")

    # --- Guards (mirror the pre-action validations) ---------------------------
    if is_empty(candidate_id):
        return {"error": "Candidate id is required."}
    if in_list(status, "Confirmed,Cancelled"):
        return {"error": "Cannot send a link for a confirmed or cancelled candidate."}
    if is_empty(email):
        return {"error": "Candidate email id is required to send the link."}

    # --- Configuration --------------------------------------------------------
    # Validity (days) and the external form base URL come in as project
    # variables on the payload; fall back to safe defaults if unset.
    validity_days = to_number(coalesce(args.get("key_validity_days"), 7))
    base_url = coalesce(args.get("ioflow_base_url"), "").rstrip("/")

    # --- Derive key / expiry / form url --------------------------------------
    now = datetime.datetime.now()
    expiry = now + datetime.timedelta(days=float(validity_days))

    # Unique, non-guessable token built from time entropy + the candidate id.
    seed = "{}-{}".format(now.strftime("%Y%m%d%H%M%S%f"), candidate_id)
    access_key = re.sub(r"[^0-9a-f]", "", json.dumps(seed).encode("utf-8").hex())

    form_url = "{}/candidate-form?key={}".format(base_url, access_key)

    # --- Field updates the engine persists on the row -------------------------
    updates = {
        "ACCESS_KEY": access_key,
        "KEY_GENERATED_ON": now,
        "KEY_EXPIRY_DATETIME": expiry,
        "KEY_VALID_FLAG": "Y",
        "FORM_URL": form_url,
        "STATUS": "Link Generated",
        "STATUS_DATE": now,
        "LINK_SENT_ON": now,
    }

    # --- Onboarding email request (dispatched by the notification listener) ---
    email_request = {
        "type": "candidate_link",
        "candidate_id": candidate_id,
        "to": email,
        "form_url": form_url,
        "expires_on": expiry.isoformat(),
    }

    return {
        "updates": updates,
        "email": email_request,
        "message": "Onboarding link generated and emailed to {}.".format(email),
    }
