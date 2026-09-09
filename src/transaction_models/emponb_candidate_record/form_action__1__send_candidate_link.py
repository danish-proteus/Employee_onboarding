# project: Employee_onboarding
# object_type: T
# object_name: emponb_candidate_record
# event_type: form_action
# function_name: send_candidate_link
# form_no: 1
# action_name: Send/Resend Link
# language: python
# description: Fresh-generate the access key, update all related fields, then raise the IOFlow send-link event with the access key and form (website) URL
# functional_specification: Fresh-generate a new unique ACCESS_KEY. Compute now = current timestamp; expiry = now + KEY_VALIDITY_DAYS days (from EMPONB_ONBOARDING_SETTINGS). Build FORM_URL as the full absolute website URL of the public candidate onboarding portal (external site slug 'onboarding') with the generated access key appended. PERSIST all of these on the candidate record: ACCESS_KEY=access_key, KEY_GENERATED_ON=now, KEY_EXPIRY_DATETIME=expiry, KEY_VALID_FLAG='Y', FORM_URL=form_url, STATUS='Link Generated', STATUS_DATE=now, LINK_SENT_ON=now. Then call the IOFlow send-link event, passing the access_key and form_url (the website URL). Return a confirmation message with the generated link.
# business_logic: Fresh-generate the access key, update all related fields, then raise the IOFlow send-link event with the access key and form (website) URL


def run(args):
    """Send / resend the candidate onboarding link (Python form action).

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

    # --- Purge any previously captured Candidate Self data --------------------
    # Re-sending the link RESETS the candidate's self-service capture: a fresh key
    # re-opens the portal, so anything the candidate submitted against a prior link
    # must be wiped before a new link is issued. Delete the detail (child) rows
    # FIRST, then the header, all filtered by candidate_id (the CANDIDATE_SELF
    # tables key on candidate_id). Idempotent — no error if nothing matches.
    for _self_table in (
        "emponb_cand_self_experience",
        "emponb_cand_self_family",
        "emponb_cand_self_education",
        "emponb_candidate_self",
    ):
        db.execute(
            "DELETE FROM " + db.t(_self_table) + " WHERE candidate_id = :cid",
            {"cid": candidate_id},
        )

    # --- Seed the candidate's SELF record from HR's captured data --------------
    # The purge above cleared this candidate's SELF capture. Recreate it from the
    # HR candidate record so the self-service form opens PRE-FILLED with what HR
    # entered. The SELF *header* is recreated FIRST: the detail tables carry a FK
    # to emponb_candidate_self(candidate_id), so a header row must exist before any
    # child row can be inserted, and it also makes the header's personal fields
    # appear immediately. We carry FIN_ENTITY across so the SELF row belongs to the
    # same financial entity as the candidate record (the public portal has no
    # logged-in user to stamp it from). Beyond that we copy ONLY the personal /
    # contact / statutory / financial columns — the same vetted set the candidate_id item_change
    # (load_candidate_self_header) seeds — and deliberately NOT the SELF-side
    # workflow / validation columns (status, access_key, *_validated, key_*, …),
    # which must start fresh for the candidate's own submission.
    _self_header_cols = (
        "candidate_id", "fin_entity", "candidate_name", "gender", "position_code", "design_code", "email_id",
        "name_prefix", "emp_fname", "emp_mname", "emp_lname", "birthdate",
        "nationality", "marital_status", "marriage_anniversary", "blood_group",
        "religion", "cast_category", "mother_tongue", "physical_handicap",
        "hobby1", "hobby2", "total_experience", "current_address", "current_pin",
        "current_city", "current_state", "permanent_address", "permanent_pin",
        "permanent_city", "permanent_state", "mobile", "alternate_telephone",
        "contact_person", "contact_person_mobile", "contact_person_email",
        "pan_no", "pan_doc", "aadhar_no", "aadhar_doc", "passport_no",
        "passport_doc", "driving_lic_no", "driving_lic_doc", "pf_no", "pf_doc",
        "esic_no", "esic_doc", "bank_account_no", "bank_ifsc_code", "bank_name",
        "bank_doc",
    )
    _hdr_list = ", ".join(_self_header_cols)
    db.execute(
        "INSERT INTO " + db.t("emponb_candidate_self") + " (" + _hdr_list + ") "
        + "SELECT " + _hdr_list + " FROM " + db.t("emponb_candidate_record")
        + " WHERE candidate_id = :cid",
        {"cid": candidate_id},
    )

    # Then copy the four detail grids (record side -> matching SELF child tables).
    # The tables were just emptied above and the header now exists, so a straight
    # INSERT ... SELECT is enough. Record and self child tables share identical
    # columns, so the same list drives both sides.
    for _rec_table, _self_table, _cols in (
        ("emponb_cand_experience", "emponb_cand_self_experience",
         ("organisation", "designation", "from_date", "to_date",
          "gross_amt", "currency_code", "country_code")),
        ("emponb_cand_education", "emponb_cand_self_education",
         ("qlf_code", "qlf_type", "institute", "pass_year", "class",
          "percentage", "country_code", "course_type", "course_duration")),
        ("emponb_cand_family", "emponb_cand_self_family",
         ("member_name", "date_birth", "gender", "relation")),
    ):
        _col_list = ", ".join(("candidate_id", "line_no") + _cols)
        db.execute(
            "INSERT INTO " + db.t(_self_table) + " (" + _col_list + ") "
            + "SELECT " + _col_list + " FROM " + db.t(_rec_table)
            + " WHERE candidate_id = :cid",
            {"cid": candidate_id},
        )

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
    # to this action; it carries CANDIDATE_ID, ACCESS_KEY, FORM_URL and EMAIL_ID
    # to IOFlow, which delivers the onboarding link. Being a committing action, the
    # outbox row is written on THIS connection — atomic with the update above — and
    # is raised only after the row update above has persisted every relevant column.
    api.emit_event(
        "emponb_candidate_sendLink",
        {
            "CANDIDATE_ID": candidate_id,
            "ACCESS_KEY": saved_key,
            "FORM_URL": saved_url,
            "EMAIL_ID": email,
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
