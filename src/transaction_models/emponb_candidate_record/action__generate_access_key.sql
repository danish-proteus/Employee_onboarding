/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: action
function_name: generate_access_key
action_name: Generate Key
language: plpgsql
description: Generate a new access key and update all related columns
functional_specification: Generate a new unique ACCESS_KEY, set KEY_GENERATED_ON = now() and KEY_EXPIRY_DATETIME = KEY_GENERATED_ON + KEY_VALIDITY_DAYS days (from EMPONB_ONBOARDING_SETTINGS), set KEY_VALID_FLAG='Y', build FORM_URL as the full absolute URL of the public candidate onboarding portal (external site slug 'onboarding') with the generated key appended, set STATUS='Link Generated', stamp STATUS_DATE. Persist all of these on the candidate record. This action only generates/regenerates the key; it does NOT raise the send-link event (that is the Send/Resend Link action).
business_logic: Generate a new access key and update all related columns
*/

CREATE OR REPLACE FUNCTION emponb_candidate_record__generate_access_key(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    -- CANDIDATE_ID is a protected auto_generate() PK, so for a row-scoped action
    -- the engine passes the selected row id as txn_id; fall back to the header
    -- envelope for completeness.
    v_candidate_id  char(10) := COALESCE(
        NULLIF(btrim(p->>'txn_id'), ''),
        NULLIF(btrim(p->>'CANDIDATE_ID'), ''),
        NULLIF(btrim(p->>'candidate_id'), ''),
        NULLIF(btrim(p->'header_values'->>'CANDIDATE_ID'), ''),
        NULLIF(btrim(p->'header_values'->>'candidate_id'), ''),
        NULLIF(btrim(p->'header'->>'CANDIDATE_ID'), ''),
        NULLIF(btrim(p->'header'->>'candidate_id'), '')
    );
    v_email         varchar(100);
    v_status        varchar(20);
    v_validity_days integer;
    v_now           timestamp := now();
    v_access_key    varchar(100);
    v_form_url      varchar(500);
BEGIN
    IF v_candidate_id IS NULL OR btrim(v_candidate_id) = '' THEN
        RETURN jsonb_build_object('error', 'Candidate id is required.');
    END IF;

    SELECT EMAIL_ID, STATUS
      INTO v_email, v_status
      FROM EMPONB_CANDIDATE_RECORD
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found.');
    END IF;

    -- Mirror the pre-action validations.
    IF v_status IN ('Confirmed', 'Cancelled') THEN
        RETURN jsonb_build_object('error', 'Cannot generate a key for a confirmed or cancelled candidate.');
    END IF;
    IF v_email IS NULL OR btrim(v_email) = '' THEN
        RETURN jsonb_build_object('error', 'Candidate email id is required to generate a key.');
    END IF;

    -- Key validity window (single settings row).
    SELECT COALESCE(KEY_VALIDITY_DAYS, 7)
      INTO v_validity_days
      FROM EMPONB_ONBOARDING_SETTINGS
     ORDER BY SETTINGS_ID
     LIMIT 1;
    v_validity_days := COALESCE(v_validity_days, 7);

    -- Unique, non-guessable token. FORM_URL is the FULL absolute URL of the
    -- public candidate onboarding portal (external site, slug 'onboarding') with
    -- the freshly generated key appended, so the candidate can open the link
    -- straight to their own key-validated form and complete pending information.
    v_access_key := md5(clock_timestamp()::text || random()::text || v_candidate_id);
    v_form_url   := 'http://dev.platform.twasta.ai:7077/site/7014e11e-1c26-4e50-b546-2c38c876bee0/Employee_onboarding/onboarding?key=' || v_access_key;

    UPDATE EMPONB_CANDIDATE_RECORD
       SET ACCESS_KEY          = v_access_key,
           KEY_GENERATED_ON    = v_now,
           KEY_EXPIRY_DATETIME = v_now + (v_validity_days * INTERVAL '1 day'),
           KEY_VALID_FLAG      = 'Y',
           FORM_URL            = v_form_url,
           STATUS              = 'Link Generated',
           STATUS_DATE         = v_now
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record could not be updated.');
    END IF;

    RETURN jsonb_build_object('message',
        'Access key generated. Link: ' || v_form_url || chr(10)
        || 'Use "Send/Resend Link" to email it to the candidate.');
END;
$$;
