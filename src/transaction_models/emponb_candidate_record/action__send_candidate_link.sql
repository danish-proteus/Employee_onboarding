/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: action
function_name: send_candidate_link
action_name: Send/Resend Link
language: plpgsql
description: Send the already-generated access link to the candidate via IOFlow
functional_specification: Do NOT generate a key. Validate that an ACCESS_KEY has already been generated (via the Generate Key action). Stamp LINK_SENT_ON = now() and set STATUS='Link Generated'. The Send/Resend Link event carries only the already-persisted CANDIDATE_ID, ACCESS_KEY and FORM_URL to IOFlow so the flow can deliver the onboarding link. Return a confirmation message.
business_logic: Send the already-generated onboarding link
*/

CREATE OR REPLACE FUNCTION emponb_candidate_record__send_candidate_link(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
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
    v_email       varchar(100);
    v_status      varchar(20);
    v_access_key  varchar(100);
    v_form_url    varchar(500);
    v_now         timestamp := now();
BEGIN
    IF v_candidate_id IS NULL OR btrim(v_candidate_id) = '' THEN
        RETURN jsonb_build_object('error', 'Candidate id is required.');
    END IF;

    SELECT EMAIL_ID, STATUS, ACCESS_KEY, FORM_URL
      INTO v_email, v_status, v_access_key, v_form_url
      FROM EMPONB_CANDIDATE_RECORD
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found.');
    END IF;

    -- Mirror the pre-action validations.
    IF v_status IN ('Confirmed', 'Cancelled') THEN
        RETURN jsonb_build_object('error', 'Cannot send a link for a confirmed or cancelled candidate.');
    END IF;
    IF v_email IS NULL OR btrim(v_email) = '' THEN
        RETURN jsonb_build_object('error', 'Candidate email id is required to send the link.');
    END IF;

    -- The key must already have been generated (Generate Key action). This action
    -- only sends the existing key; it never generates one.
    IF v_access_key IS NULL OR btrim(v_access_key) = '' THEN
        RETURN jsonb_build_object('error', 'Generate the access key first before sending the link.');
    END IF;

    -- Stamp only the send timestamp; ACCESS_KEY / FORM_URL are left as generated.
    UPDATE EMPONB_CANDIDATE_RECORD
       SET LINK_SENT_ON = v_now,
           STATUS       = 'Link Generated',
           STATUS_DATE  = v_now
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record could not be updated.');
    END IF;

    -- The Send/Resend Link event carries the already-persisted CANDIDATE_ID,
    -- ACCESS_KEY and FORM_URL (defined in Integration_Design/integration.json) to
    -- IOFlow, which delivers the onboarding link. Because the key was generated
    -- and committed by a prior Generate Key action, the row snapshot the event
    -- captures already holds the correct key -- no in-action fold-back needed.
    RETURN jsonb_build_object('message',
        'Onboarding link sent to ' || v_email || '.' || chr(10) || 'Link: ' || v_form_url);
END;
$$;
