# project: Employee_onboarding
# object_type: T
# object_name: emponb_candidate_record
# event_type: action
# function_name: send_candidate_link
# language: python
# description: Fresh-generate the access key, update all related fields, then raise
#   the IOFlow send-link event with the access key and website form URL.
# functional_specification: Fresh-generate a NEW unique ACCESS_KEY on every call.
#   Compute now = current timestamp and expiry = now + KEY_VALIDITY_DAYS days (from
#   EMPONB_ONBOARDING_SETTINGS). Build FORM_URL as the full absolute WEBSITE url of
#   the public candidate onboarding portal (external site slug 'candidate_website') with
#   the generated key appended. PERSIST on the candidate record: ACCESS_KEY,
#   KEY_GENERATED_ON, KEY_EXPIRY_DATETIME, KEY_VALID_FLAG='Y', FORM_URL,
#   STATUS='Link Generated', STATUS_DATE, LINK_SENT_ON. Then raise the IOFlow
#   send-link event (emponb_candidate_sendLink) passing the access key and form
#   (website) url. Return a confirmation message.
# business_logic: Generate the access key and send the onboarding link


def run(args):
    """Send / resend the candidate onboarding link (Python action).

    Runs as a ROW-scoped action button. Action buttons execute inside a
    COMMITTING transaction, so the engine binds:
      * ``db``  — a write-capable DbFacade whose INSERT/UPDATE/DELETE persist
                  (they roll back only if this action later returns/raises an
                  error), and
      * ``api`` — the runtime API whose ``emit_event`` enqueues an IOFlow event
                  atomically with this action's commit.
    So this function persists the key columns with ``db.update`` and fires the
    send-link flow with ``api.emit_event`` — the direct equivalent of the plpgsql
    sibling ``generate_access_key`` (which UPDATEs the same row).

    Identifiers: this project's tables/columns were deployed unquoted, so Postgres
    stores them lower-case and the DbFacade quotes them exactly — every table /
    column name passed to ``db`` is therefore lower-case, and ``db.update`` gets
    the BARE table name (it schema-qualifies internally).

    Row identity: for a row-scoped action the engine passes the selected row id as
    ``txn_id`` (the PK CANDIDATE_ID is a protected auto_generate() key, so it is
    NOT sent under its own name). We read ``txn_id`` first, then fall back to the
    header envelope and any explicit candidate id keys.
    """
    # --- Resolve the candidate id from the row envelope -----------------------
    header_values = args.get("header_values") or {}
    header = args.get("header") or {}
    candidate_id = _first_nonempty(
        args.get("txn_id"),
        args.get("candidate_id"),
        _get_ci(header_values, "candidate_id"),
        _get_ci(header, "candidate_id"),
    )
    if is_empty(candidate_id):
        return {"error": "Candidate id is required."}

    # --- Authoritative email + status straight from the row -------------------
    row = db.query_one(
        "SELECT email_id, status FROM " + db.t("emponb_candidate_record")
        + " WHERE candidate_id = :cid",
        {"cid": candidate_id},
    )
    if row is None:
        return {"error": "Candidate record not found."}
    email = coalesce(row.get("email_id"), "")
    status = coalesce(row.get("status"), "")

    # --- Guards (mirror the pre-action validations) ---------------------------
    if in_list(status, "Confirmed,Cancelled"):
        return {"error": "Cannot send a link for a confirmed or cancelled candidate."}
    if is_empty(email):
        return {"error": "Candidate email id is required to send the link."}

    # --- Key validity window (single settings row) ----------------------------
    settings = db.query_one(
        "SELECT key_validity_days"
        + " FROM " + db.t("emponb_onboarding_settings")
        + " ORDER BY settings_id LIMIT 1"
    )
    validity_days = to_number(coalesce((settings or {}).get("key_validity_days"), 7))
    if is_empty(validity_days) or float(validity_days) <= 0:
        validity_days = 7

    # --- Fresh, unique, non-guessable token -----------------------------------
    # Generated in the database (md5 of clock + random + id) so it is a one-way
    # hash — the SAME algorithm as the plpgsql sibling. (The Python sandbox has no
    # crypto/random import; delegating to Postgres keeps the token unforgeable.)
    now_ts = now()
    expiry = now_ts + timedelta(days=float(validity_days))
    access_key = db.scalar(
        "SELECT md5(clock_timestamp()::text || random()::text || :cid)",
        {"cid": candidate_id},
    )

    # FORM_URL: full absolute WEBSITE url of the public candidate onboarding
    # portal (external site slug 'candidate_website') with the fresh key appended,
    # so the candidate opens straight to their own key-validated form.
    form_url = (
        "http://dev.platform.twasta.ai:7079/site/"
        "7014e11e-1c26-4e50-b546-2c38c876bee0/Employee_onboarding"
        "/candidate_website?key=" + access_key
    )

    # --- Persist on the acted-on row (committing action → writes stick) -------
    updated = db.update(
        "emponb_candidate_record",
        {
            "access_key": access_key,
            "key_generated_on": now_ts,
            "key_expiry_datetime": expiry,
            "key_valid_flag": "Y",
            "form_url": form_url,
            "status": "Link Generated",
            "status_date": now_ts,
            "link_sent_on": now_ts,
        },
        {"candidate_id": candidate_id},
    )
    if not updated:
        return {"error": "Candidate record could not be updated."}

    # --- Re-read the PERSISTED row so IOFlow gets the committed values ---------
    # All relevant columns are now written on the row. We read them back and emit
    # the IOFlow event FROM the persisted values (not the in-memory locals), so
    # the event payload always carries exactly what was saved — this is why the
    # event fires only AFTER every relevant row has been updated.
    saved = db.query_one(
        "SELECT candidate_id, access_key, form_url"
        + " FROM " + db.t("emponb_candidate_record")
        + " WHERE candidate_id = :cid",
        {"cid": candidate_id},
    ) or {}
    saved_key = coalesce(saved.get("access_key"), access_key)
    saved_url = coalesce(saved.get("form_url"), form_url)

    # --- Raise the IOFlow send-link event -------------------------------------
    # 'emponb_candidate_sendLink' (Integration_Design/integration.json) is bound
    # to this action; it carries CANDIDATE_ID, ACCESS_KEY and FORM_URL to IOFlow,
    # which delivers the onboarding link. Being a committing action, the outbox
    # row is written on THIS connection — atomic with the update above — and is
    # raised only after the row update above has persisted every relevant column.
    api.emit_event(
        "emponb_candidate_sendLink",
        {
            "CANDIDATE_ID": candidate_id,
            "ACCESS_KEY": saved_key,
            "FORM_URL": saved_url,
        },
        record_pk=candidate_id,
    )

    return {"message": "Onboarding link sent to " + email + ".\nLink: " + saved_url}


def _get_ci(d, key):
    """Case-insensitive lookup in a plain dict (header envelopes are not the
    case-insensitive args dict)."""
    if not isinstance(d, dict):
        return None
    if key in d:
        return d[key]
    lk = key.lower()
    for k, v in d.items():
        if isinstance(k, str) and k.lower() == lk:
            return v
    return None


def _first_nonempty(*vals):
    for v in vals:
        if v is None:
            continue
        s = str(v).strip()
        if s != "":
            return s
    return ""
