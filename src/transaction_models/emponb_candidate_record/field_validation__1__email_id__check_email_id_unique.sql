/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: field_validation
function_name: check_email_id_unique
form_no: 1
field_name: email_id
language: plpgsql
description: Validate Email ID uniqueness only when it changed
functional_specification: Validate that the entered EMAIL_ID is not already used by another candidate. On add, return an error when any EMPONB_CANDIDATE_RECORD row already has the same EMAIL_ID (case-insensitive, trimmed). On edit, first compare the incoming EMAIL_ID with the stored value for the same CANDIDATE_ID and return no error when it has not changed; otherwise check for another row with the same EMAIL_ID excluding the current CANDIDATE_ID and return an error if one exists.
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
--   3. SKIP-WHEN-UNCHANGED: on edit (CANDIDATE_ID present) the stored
--      EMAIL_ID is fetched with a single primary-key lookup. When it
--      equals the submitted value (case-insensitive, trimmed) the
--      function returns immediately - the uniqueness scan and any
--      external e-mail verification service are BOTH skipped. Re-saving
--      an existing candidate whose e-mail was not edited must never pay
--      for that work, and must never fail on an address that was
--      already accepted once.
--   4. New record, or the address actually changed -> run the real
--      uniqueness check against EMPONB_CANDIDATE_RECORD, excluding the
--      candidate's own row. A hit returns EMAIL_ID_DUPLICATE.
--
-- Return contract: {'errors': [ {code, field, type, message}, ... ]}.
-- An empty 'errors' array means the value is valid.
-- =====================================================================
CREATE OR REPLACE FUNCTION check_email_id_unique(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_cand_id      text;     -- key of the record being saved (NULL on add)
    v_email        text;     -- submitted e-mail address
    v_stored_email text;     -- e-mail currently persisted for v_cand_id
    v_exists       boolean;  -- another candidate already uses v_email?
BEGIN
    -- (1) Submitted header values, payload casing agnostic.
    v_cand_id := NULLIF(btrim(COALESCE(p->'header'->>'CANDIDATE_ID',
                                       p->'header'->>'candidate_id', '')), '');
    v_email   := NULLIF(btrim(COALESCE(p->'header'->>'EMAIL_ID',
                                       p->'header'->>'email_id', '')), '');

    -- (2) Nothing entered -> the mandatory check reports it, not us.
    IF v_email IS NULL THEN
        RETURN jsonb_build_object('errors', '[]'::jsonb);
    END IF;

    -- ---------------------------------------------------------------
    -- (3) Edit-mode short circuit: the address did not change.
    --     One lookup by primary key - the only DB access allowed on
    --     the unchanged path. No uniqueness scan, and no call to any
    --     external e-mail-validation REST API below this point.
    -- ---------------------------------------------------------------
    IF v_cand_id IS NOT NULL THEN
        SELECT btrim(EMAIL_ID)
          INTO v_stored_email
          FROM EMPONB_CANDIDATE_RECORD
         WHERE CANDIDATE_ID = v_cand_id;

        IF FOUND AND lower(v_stored_email) = lower(v_email) THEN
            RETURN jsonb_build_object('errors', '[]'::jsonb);
        END IF;
    END IF;

    -- ---------------------------------------------------------------
    -- (4) New record, or the address really changed -> real check.
    --     The candidate's own row is excluded so an edit never clashes
    --     with itself.
    -- ---------------------------------------------------------------
    SELECT EXISTS (SELECT 1
                     FROM EMPONB_CANDIDATE_RECORD
                    WHERE lower(btrim(EMAIL_ID)) = lower(v_email)
                      AND (v_cand_id IS NULL OR CANDIDATE_ID <> v_cand_id))
      INTO v_exists;

    IF v_exists THEN
        RETURN jsonb_build_object(
            'errors', jsonb_build_array(
                jsonb_build_object(
                    'code',    'EMAIL_ID_DUPLICATE',
                    'field',   'EMAIL_ID',
                    'type',    'E',
                    'message', 'This Email ID is already used by another candidate record.'
                )
            )
        );
    END IF;

    RETURN jsonb_build_object('errors', '[]'::jsonb);
END;
$$;
