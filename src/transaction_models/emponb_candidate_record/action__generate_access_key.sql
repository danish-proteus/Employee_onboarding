/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: action
function_name: generate_access_key_action
form_no: 1
action_name: Generate Key
language: plpgsql
description: Generate a new access key and update all related columns
functional_specification: Object-level action variant of the Generate Key form action. Generate a new unique ACCESS_KEY, set KEY_GENERATED_ON = now() and KEY_EXPIRY_DATETIME = KEY_GENERATED_ON + KEY_VALIDITY_DAYS days (from EMPONB_ONBOARDING_SETTINGS), set KEY_VALID_FLAG='Y', build FORM_URL as the full absolute URL of the public candidate onboarding portal (external site slug 'onboarding') with the generated key appended, set STATUS='Link Generated', stamp STATUS_DATE, and persist all of these on the candidate record. Return a confirmation message with the generated link. Does NOT raise the send-link event.
business_logic: Generate a new access key and update all related columns
*/

CREATE OR REPLACE FUNCTION generate_access_key_action(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id  text := TRIM(COALESCE(p->>'CANDIDATE_ID', ''));
    v_status        text;
    v_validity_days numeric;
    v_base_url      text;
    v_now           timestamp := now();
    v_key           text;
    v_expiry        timestamp;
    v_form_url      text;
    v_issues        jsonb := '[]'::jsonb;
BEGIN
    IF v_candidate_id = '' THEN
        RETURN jsonb_build_object(
                 'error', 'Candidate record must be saved before generating an access key.',
                 'errors', jsonb_build_array(jsonb_build_object(
                     'code', 'AGK001', 'field', 'CANDIDATE_ID', 'type', 'E',
                     'message', 'Candidate record must be saved before generating an access key.')));
    END IF;

    -- Read the persisted status (the action may be fired from a list, where the
    -- payload can carry only the key columns).
    SELECT c.STATUS
      INTO v_status
      FROM EMPONB_CANDIDATE_RECORD c
     WHERE c.CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found: ' || v_candidate_id);
    END IF;

    IF TRIM(COALESCE(v_status, '')) IN ('Confirmed', 'Cancelled') THEN
        v_issues := v_issues || jsonb_build_object(
                        'code', 'AGK002', 'field', 'STATUS', 'type', 'E',
                        'message', 'Access key cannot be generated for a ' || TRIM(v_status) || ' candidate.');
    END IF;

    SELECT s.KEY_VALIDITY_DAYS, s.IOFLOW_BASE_URL
      INTO v_validity_days, v_base_url
      FROM EMPONB_ONBOARDING_SETTINGS s
     ORDER BY s.SETTINGS_ID
     LIMIT 1;

    IF NOT FOUND THEN
        v_issues := v_issues || jsonb_build_object(
                        'code', 'AGK003', 'type', 'E',
                        'message', 'Onboarding settings are not configured. Please set up Onboarding Settings first.');
    END IF;

    IF jsonb_array_length(v_issues) > 0 THEN
        RETURN jsonb_build_object('errors', v_issues)
               || jsonb_build_object('error', v_issues->0->>'message');
    END IF;

    v_key    := replace(gen_random_uuid()::text, '-', '');
    v_expiry := v_now + (COALESCE(v_validity_days, 7)::text || ' days')::interval;

    -- Absolute URL of the public candidate onboarding portal (site slug 'onboarding').
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

    -- Refresh the candidate self-service header + all four detail sections
    -- (Past Experience, Education, Family, Pay) from the recruiter-side lines, so
    -- the copied data actually appears on the candidate form each time a link is
    -- (re)generated. seed_self_experience internally skips once the candidate owns
    -- the data (STATUS in DataSubmitted/Review/Confirmed/Cancelled), so this is
    -- safe on every resend and never overwrites candidate-entered data.
    PERFORM seed_self_experience(jsonb_build_object('CANDIDATE_ID', v_candidate_id));

    RETURN jsonb_build_object('prompts', jsonb_build_array(jsonb_build_object(
               'code', 'AGK900', 'type', 'P',
               'message', 'Access key generated. Onboarding link: ' || v_form_url
                          || ' (valid till ' || to_char(v_expiry, 'DD-Mon-YYYY HH24:MI') || ').')));
END;
$$;
