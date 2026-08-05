/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_validation
function_name: check_self_family_member_unique
form_no: 4
field_name: member_name
language: plpgsql
description: Block duplicate family member names for the same candidate
functional_specification: Excluding the row being edited when _action = 'edit' (match on CANDIDATE_ID and LINE_NO), check whether another EMPONB_CAND_SELF_FAMILY row for the same CANDIDATE_ID already has the same MEMBER_NAME (case-insensitive, trimmed). If found, return an error: 'Family member ' || MEMBER_NAME || ' is already added. Duplicate member names are not allowed.'
business_logic: Block duplicate family member names for the same candidate
*/

CREATE OR REPLACE FUNCTION check_self_family_member_unique(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id text    := p->>'CANDIDATE_ID';
    v_member_name  text    := btrim(COALESCE(p->>'MEMBER_NAME',''));
    v_line_no      numeric := NULLIF(p->>'LINE_NO','')::numeric;
    v_exists       boolean;
BEGIN
    -- Nothing to validate until candidate and member name are known
    IF v_candidate_id IS NULL OR v_member_name = '' THEN
        RETURN NULL;
    END IF;

    -- Another family line of the same candidate with the same name (case-insensitive)?
    -- Normalize on the VALUE side only; on edit, exclude the row being edited.
    SELECT EXISTS (
        SELECT 1
        FROM EMPONB_CAND_SELF_FAMILY f
        WHERE f.CANDIDATE_ID = v_candidate_id
          AND upper(f.MEMBER_NAME) = upper(v_member_name)
          AND (p->>'_action' <> 'edit' OR v_line_no IS NULL OR f.LINE_NO <> v_line_no)
    ) INTO v_exists;

    IF v_exists THEN
        RETURN jsonb_build_object('error',
            'Family member ' || v_member_name || ' is already added. Duplicate member names are not allowed.');
    END IF;

    RETURN NULL;
END;
$$;
