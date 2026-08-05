/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_validation
function_name: validate_self_family_member_unique
form_no: 4
field_name: member_name
language: plpgsql
description: Block duplicate MEMBER_NAME within the same candidate's family lines
functional_specification: On save of an EMPONB_CAND_SELF_FAMILY row: if _action = 'edit', pass without re-checking when MEMBER_NAME is unchanged for this (CANDIDATE_ID, LINE_NO). Otherwise reject with 'Family member <name> is already added. Duplicate member names are not allowed.' if another row already exists in EMPONB_CAND_SELF_FAMILY for the same CANDIDATE_ID with the same MEMBER_NAME (case-insensitive, excluding this LINE_NO on edit).
business_logic: Block duplicate MEMBER_NAME within the same candidate's family lines
*/

CREATE OR REPLACE FUNCTION validate_self_family_member_unique(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id text    := p->>'CANDIDATE_ID';
    v_member_name  text    := p->>'MEMBER_NAME';
    v_line_no      numeric := NULLIF(p->>'LINE_NO', '')::numeric;
    v_stored_name  text;
    v_exists       boolean;
BEGIN
    -- Nothing to check without a member name
    IF v_member_name IS NULL OR btrim(v_member_name) = '' THEN
        RETURN NULL;
    END IF;

    -- In edit mode, pass if the name is unchanged for this exact line
    IF p->>'_action' = 'edit' THEN
        SELECT MEMBER_NAME
          INTO v_stored_name
          FROM EMPONB_CAND_SELF_FAMILY
         WHERE CANDIDATE_ID = v_candidate_id
           AND LINE_NO      = v_line_no;

        IF FOUND AND v_stored_name = v_member_name THEN
            RETURN NULL;
        END IF;
    END IF;

    -- Reject a case-insensitive duplicate within this candidate's family lines.
    -- CANDIDATE_ID (PK) drives the lookup; the name compare runs only over that
    -- candidate's few rows, so the case-fold does not defeat the index.
    SELECT EXISTS (
             SELECT 1
               FROM EMPONB_CAND_SELF_FAMILY
              WHERE CANDIDATE_ID = v_candidate_id
                AND UPPER(MEMBER_NAME) = UPPER(v_member_name)
                AND (v_line_no IS NULL OR LINE_NO <> v_line_no)
           )
      INTO v_exists;

    IF v_exists THEN
        RETURN jsonb_build_object('error',
            'Family member ' || v_member_name ||
            ' is already added. Duplicate member names are not allowed.');
    END IF;

    RETURN NULL;
END;
$$;
