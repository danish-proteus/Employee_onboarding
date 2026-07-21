/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: field_validation
function_name: check_email_id_unique
form_no: 1
field_name: email_id
language: plpgsql
description: Validate Email ID uniqueness; edit mode is detected by the record actually existing in the database, so new records are always validated
functional_specification: Validate that the entered EMAIL_ID is not already used by another candidate. Edit mode is NOT inferred from the presence of CANDIDATE_ID in the payload (the key is already populated in the header for a new record); it is detected by looking the CANDIDATE_ID up in EMPONB_CANDIDATE_RECORD and checking that the row really exists. When the row exists and its stored EMAIL_ID equals the submitted value (case-insensitive, trimmed), return no error. In every other case - new record, key not yet persisted, stored email null, or the address actually changed - scan EMPONB_CANDIDATE_RECORD for the same EMAIL_ID (case-insensitive, trimmed), excluding the candidate's own row ONLY when that row genuinely exists, and return an error if a match is found.
business_logic: Validate Email ID uniqueness only when it changed
*/

-- =====================================================================
-- field_validation : check_email_id_unique   (form 1, field EMAIL_ID)
-- Transaction : emponb_candidate_record
--
-- Guarantees that no two candidate records share the same e-mail
-- address, WITHOUT re-validating an address that the user never
-- touched.
--
--   1. Read CANDIDATE_ID / EMAIL_ID from p->'header', tolerating both
--      upper- and lower-case payload keys.
--   2. Empty EMAIL_ID          -> no error here; the mandatory check
--      owns that case.
--   3. EDIT MODE IS NOT INFERRED FROM THE PAYLOAD. A new record already
--      carries a populated CANDIDATE_ID in the header, so "key present"
--      would wrongly mark an add as an edit and skip the check. Edit
--      mode is decided by the DATABASE: the CANDIDATE_ID is looked up
--      in EMPONB_CANDIDATE_RECORD and v_row_exists captures whether the
--      row really is persisted.
--   4. SKIP-WHEN-UNCHANGED: only when the row exists AND its stored
--      EMAIL_ID equals the submitted value (case-insensitive, trimmed)
--      does the function return immediately - the uniqueness scan and
--      any external e-mail verification service are BOTH skipped.
--      Re-saving an existing candidate whose e-mail was not edited must
--      never pay for that work, and must never fail on an address that
--      was already accepted once.
--   5. Every other case - new record, key not yet persisted, stored
--      e-mail null, or the address really changed -> run the real
--      uniqueness check against EMPONB_CANDIDATE_RECORD. The self-row
--      exclusion applies ONLY when the row genuinely exists, so a new
--      record is checked against ALL rows, including any row that
--      happens to share its key value. The record's own CANDIDATE_ID is
--      always excluded from the lookup. A hit returns EMAIL_DUP.
--
-- Return contract: {'errors': [ {code, field, type, message}, ... ]}.
-- An empty 'errors' array means the value is valid.
-- =====================================================================
CREATE OR REPLACE FUNCTION check_email_id_unique(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_cand_id   text;     -- key carried in the payload (present on add too)
    v_email_raw text;     -- e-mail exactly as the user typed it
    v_email     text;     -- normalised: TRIM(UPPER(entered e-mail))
    v_old_email text;     -- e-mail currently persisted for v_cand_id
    v_is_edit   boolean;  -- does v_cand_id really exist in the table?
    v_count     integer;  -- how many other candidates use v_email?
BEGIN
    -- (1) In-form values, payload casing agnostic (header first, then
    --     a flat payload as a fallback).
    v_cand_id := NULLIF(btrim(COALESCE(p->'header'->>'CANDIDATE_ID',
                                       p->'header'->>'candidate_id',
                                       p->>'CANDIDATE_ID',
                                       p->>'candidate_id', '')), '');

    v_email_raw := COALESCE(p->'header'->>'EMAIL_ID',
                            p->'header'->>'email_id',
                            p->>'EMAIL_ID',
                            p->>'email_id');

    v_email := NULLIF(btrim(upper(COALESCE(v_email_raw, ''))), '');

    -- (2) Nothing entered -> the mandatory check owns that case; never
    --     raise a duplicate error on a blank value.
    IF v_email IS NULL THEN
        RETURN jsonb_build_object('errors', '[]'::jsonb);
    END IF;

    -- ---------------------------------------------------------------
    -- (3) ADD vs EDIT is decided by the DATABASE, never by the mere
    --     presence of CANDIDATE_ID in the payload (a new record already
    --     carries a populated key). No key, or no row for that key ->
    --     ADD mode. FOUND is captured immediately after the SELECT so
    --     nothing in between can reset it.
    -- ---------------------------------------------------------------
    IF v_cand_id IS NOT NULL THEN
        SELECT EMAIL_ID
          INTO v_old_email
          FROM EMPONB_CANDIDATE_RECORD
         WHERE CANDIDATE_ID = v_cand_id;

        v_is_edit := FOUND;
    ELSE
        v_is_edit := false;
    END IF;

    -- ---------------------------------------------------------------
    -- (4) EDIT-mode short circuit: the row exists and the Email ID was
    --     NOT edited -> return success immediately and perform NO
    --     duplicate lookup (and no external e-mail verification call).
    -- ---------------------------------------------------------------
    IF v_is_edit
       AND v_old_email IS NOT NULL
       AND btrim(upper(v_old_email)) = v_email THEN
        RETURN jsonb_build_object('errors', '[]'::jsonb);
    END IF;

    -- ---------------------------------------------------------------
    -- (5) ADD mode, or EDIT mode where the address really changed ->
    --     run the duplicate check. The record's own CANDIDATE_ID is
    --     always excluded, so re-saving a record can never flag itself.
    -- ---------------------------------------------------------------
    SELECT COUNT(*)
      INTO v_count
      FROM EMPONB_CANDIDATE_RECORD
     WHERE btrim(upper(EMAIL_ID)) = v_email
       AND (v_cand_id IS NULL OR CANDIDATE_ID <> v_cand_id);

    IF v_count > 0 THEN
        RETURN jsonb_build_object(
            'errors', jsonb_build_array(
                jsonb_build_object(
                    'code',    'EMAIL_DUP',
                    'field',   'EMAIL_ID',
                    'type',    'E',
                    'message', 'Email ID ' || btrim(COALESCE(v_email_raw, '')) ||
                               ' already exists for another candidate. Please enter a unique Email ID.'
                )
            )
        );
    END IF;

    -- (6) No duplicate -> success, no messages.
    RETURN jsonb_build_object('errors', '[]'::jsonb);
END;
$$;
