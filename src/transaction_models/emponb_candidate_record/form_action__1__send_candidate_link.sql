/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: form_action
function_name: send_candidate_link
form_no: 1
action_name: Send Candidate Link
language: plpgsql
description: Send/resend the onboarding link email to the candidate and carry over Past Experience rows
functional_specification: Set LINK_SENT_ON = now(). Send an email to EMAIL_ID with the FORM_URL using the CANDIDATE_SUBMIT_EMAIL_TEMPLATE/onboarding link template. Idempotently copy every EMPONB_CAND_EXPERIENCE row for this CANDIDATE_ID into EMPONB_CAND_SELF_EXPERIENCE for the same CANDIDATE_ID (matching by CANDIDATE_ID + LINE_NO, insert if missing, update if present) ONLY while STATUS is 'Link Generated' or 'Link Accessed'; do nothing to the self-service rows once STATUS is 'DataSubmitted', 'Review' or 'Confirmed'. Return a confirmation message.
business_logic: Send/resend the onboarding link email to the candidate and carry over Past Experience rows
*/

CREATE OR REPLACE FUNCTION send_candidate_link(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    -- Identify the loaded candidate from the action envelope.
    v_candidate_id   varchar(10) := p->>'candidate_id';
    v_candidate_name varchar(100);
    v_email_id       varchar(120);
    v_form_url       varchar(500);
    v_status         varchar(20);
    v_ioflow         jsonb;      -- raw response of the mail integration
    v_error_msg      text;
    v_success        boolean;
    v_copied         integer := 0;  -- number of experience rows carried over
BEGIN
    -- Guard: candidate must be identified from the loaded row.
    IF v_candidate_id IS NULL OR TRIM(v_candidate_id) = '' THEN
        RETURN jsonb_build_object('error', 'Candidate not identified.');
    END IF;

    -- Always work off the stored row: the mail must reflect what is persisted.
    SELECT CANDIDATE_NAME, EMAIL_ID, FORM_URL, STATUS
      INTO v_candidate_name, v_email_id, v_form_url, v_status
      FROM EMPONB_CANDIDATE_RECORD
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found.');
    END IF;

    -- The link can only be mailed once it has been generated.
    IF COALESCE(TRIM(v_form_url), '') = '' THEN
        RETURN jsonb_build_object(
            'error', 'No onboarding link is available yet. Generate the link first.'
        );
    END IF;

    IF COALESCE(TRIM(v_email_id), '') = '' THEN
        RETURN jsonb_build_object(
            'error', 'Candidate email id is missing. Enter an email id before sending the link.'
        );
    END IF;

    -- Carry the HR-captured Past Experience rows over to the self-service form,
    -- but ONLY while the candidate has not submitted yet. Once STATUS has moved
    -- to DataSubmitted / Review / Confirmed the candidate's own rows are the
    -- source of truth and must never be overwritten by a link re-send.
    IF v_status IN ('Link Generated', 'Link Accessed') THEN
        -- Update the rows that already exist on the self-service side.
        UPDATE EMPONB_CAND_SELF_EXPERIENCE s
           SET ORGANISATION = e.ORGANISATION,
               DESIGNATION  = e.DESIGNATION,
               FROM_DATE    = e.FROM_DATE,
               TO_DATE      = e.TO_DATE,
               GROSS_AMT    = e.GROSS_AMT
          FROM EMPONB_CAND_EXPERIENCE e
         WHERE e.CANDIDATE_ID = v_candidate_id
           AND s.CANDIDATE_ID = e.CANDIDATE_ID
           AND s.LINE_NO      = e.LINE_NO;

        -- Insert the ones that are still missing (idempotent on CANDIDATE_ID + LINE_NO).
        INSERT INTO EMPONB_CAND_SELF_EXPERIENCE
            (CANDIDATE_ID, LINE_NO, ORGANISATION, DESIGNATION, FROM_DATE, TO_DATE, GROSS_AMT)
        SELECT e.CANDIDATE_ID, e.LINE_NO, e.ORGANISATION, e.DESIGNATION,
               e.FROM_DATE, e.TO_DATE, e.GROSS_AMT
          FROM EMPONB_CAND_EXPERIENCE e
         WHERE e.CANDIDATE_ID = v_candidate_id
           AND NOT EXISTS (
                   SELECT 1
                     FROM EMPONB_CAND_SELF_EXPERIENCE s
                    WHERE s.CANDIDATE_ID = e.CANDIDATE_ID
                      AND s.LINE_NO      = e.LINE_NO
               );

        -- Rows now mirrored on the self-service side (used only for the message).
        SELECT count(*)::integer
          INTO v_copied
          FROM EMPONB_CAND_SELF_EXPERIENCE
         WHERE CANDIDATE_ID = v_candidate_id;
    END IF;

    -- Send (or re-send) the onboarding link mail through the project's standard
    -- integration helper, using the onboarding link template.
    v_ioflow := ioflow_call(
        'EmpOnboardingSendMail',
        jsonb_build_object(
            'template',       'CANDIDATE_SUBMIT_EMAIL_TEMPLATE',
            'candidate_id',   v_candidate_id,
            'candidate_name', v_candidate_name,
            'to_email',       v_email_id,
            'form_url',       v_form_url
        )
    );

    v_success := COALESCE(v_ioflow->>'success', v_ioflow->>'sent', 'N')
                 IN ('Y', 'y', 'true', 'TRUE', 'True', '1');
    v_error_msg := COALESCE(v_ioflow->>'error', v_ioflow->>'message');

    IF v_ioflow IS NULL OR NOT v_success THEN
        RETURN jsonb_build_object(
            'error',
            COALESCE(NULLIF(TRIM(v_error_msg), ''), 'Could not send the onboarding link email.')
        );
    END IF;

    -- Stamp the send. STATUS itself is not advanced here: a re-send must not
    -- pull an already-accessed / submitted candidate back to an earlier stage.
    UPDATE EMPONB_CANDIDATE_RECORD
       SET LINK_SENT_ON = now()
     WHERE CANDIDATE_ID = v_candidate_id;

    RETURN jsonb_build_object(
        'message',
        'Onboarding link sent to ' || v_email_id || '.' ||
        CASE WHEN v_status IN ('Link Generated', 'Link Accessed')
             THEN ' ' || v_copied || ' past experience row(s) carried over to the candidate form.'
             ELSE ''
        END
    );
END;
$$;
