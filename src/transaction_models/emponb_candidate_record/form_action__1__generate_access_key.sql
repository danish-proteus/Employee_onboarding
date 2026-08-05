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

CREATE OR REPLACE FUNCTION generate_access_key(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id  text := TRIM(COALESCE(p->>'CANDIDATE_ID', ''));
    v_status        text := TRIM(COALESCE(p->>'STATUS', ''));
    v_validity_days numeric;
    v_base_url      text;
    v_now           timestamp := now();
    v_key           text;
    v_expiry        timestamp;
    v_form_url      text;
    v_issues        jsonb := '[]'::jsonb;
BEGIN
    -- Basic guard: the record must already exist to be updated.
    IF v_candidate_id = '' THEN
        RETURN jsonb_build_object(
                 'error', 'Candidate record must be saved before generating an access key.',
                 'errors', jsonb_build_array(jsonb_build_object(
                     'code', 'GAK001', 'field', 'CANDIDATE_ID', 'type', 'E',
                     'message', 'Candidate record must be saved before generating an access key.')));
    END IF;

    -- A confirmed or cancelled candidate must never receive a fresh link.
    IF v_status IN ('Confirmed', 'Cancelled') THEN
        v_issues := v_issues || jsonb_build_object(
                        'code', 'GAK002', 'field', 'STATUS', 'type', 'E',
                        'message', 'Access key cannot be generated for a ' || v_status || ' candidate.');
    END IF;

    -- Onboarding settings (single configuration row) holds validity + portal base URL.
    SELECT s.KEY_VALIDITY_DAYS, s.IOFLOW_BASE_URL
      INTO v_validity_days, v_base_url
      FROM EMPONB_ONBOARDING_SETTINGS s
     ORDER BY s.SETTINGS_ID
     LIMIT 1;

    IF NOT FOUND THEN
        v_issues := v_issues || jsonb_build_object(
                        'code', 'GAK003', 'type', 'E',
                        'message', 'Onboarding settings are not configured. Please set up Onboarding Settings first.');
    END IF;

    IF jsonb_array_length(v_issues) > 0 THEN
        RETURN jsonb_build_object('errors', v_issues)
               || jsonb_build_object('error', v_issues->0->>'message');
    END IF;

    -- UUID based key: unique, collision free and URL safe.
    v_key    := replace(gen_random_uuid()::text, '-', '');
    v_expiry := v_now + (COALESCE(v_validity_days, 7)::text || ' days')::interval;

    -- Absolute URL of the public candidate onboarding portal (external site slug 'onboarding').
    v_form_url := rtrim(COALESCE(TRIM(v_base_url), ''), '/') || '/onboarding?key=' || v_key;

    UPDATE EMPONB_CANDIDATE_RECORD
       SET ACCESS_KEY          = v_key,
           KEY_GENERATED_ON    = v_now,
           KEY_EXPIRY_DATETIME = v_expiry,
           KEY_VALID_FLAG      = 'Y',
           FORM_URL            = v_form_url,
           STATUS              = 'Link Generated',
           STATUS_DATE         = v_now,
           CHG_DATE            = v_now
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found: ' || v_candidate_id);
    END IF;

    -- Non-blocking confirmation carrying the generated link back to the user.
    RETURN jsonb_build_object('prompts', jsonb_build_array(jsonb_build_object(
               'code', 'GAK900', 'type', 'P',
               'message', 'Access key generated. Onboarding link: ' || v_form_url
                          || ' (valid till ' || to_char(v_expiry, 'DD-Mon-YYYY HH24:MI') || ').')));
END;
$$;
