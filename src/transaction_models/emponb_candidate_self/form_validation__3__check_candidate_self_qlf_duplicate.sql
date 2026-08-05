/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: form_validation
function_name: check_candidate_self_qlf_duplicate
form_no: 3
language: plpgsql
description: Block duplicate QLF_CODE rows for the same candidate
functional_specification: On add, or on edit when QLF_CODE has changed, check whether another row of EMPONB_CAND_SELF_EDUCATION for the same CANDIDATE_ID already has the same QLF_CODE (excluding the current LINE_NO on edit). Return an error if a duplicate is found.
business_logic: Block duplicate QLF_CODE rows for the same candidate
*/

CREATE OR REPLACE FUNCTION check_candidate_self_qlf_duplicate(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id text := p->>'CANDIDATE_ID';
    v_qlf_code     text := p->>'QLF_CODE';
    v_line_no      numeric := NULLIF(p->>'LINE_NO', '')::numeric;
    v_dup          boolean;
BEGIN
    -- Qualification code is required to run the duplicate check
    IF v_qlf_code IS NULL OR v_candidate_id IS NULL THEN
        RETURN NULL;
    END IF;

    IF p->>'_action' = 'edit' THEN
        -- On edit, only re-check when QLF_CODE actually changed; exclude the current line
        SELECT EXISTS (
            SELECT 1
            FROM EMPONB_CAND_SELF_EDUCATION
            WHERE CANDIDATE_ID = v_candidate_id
              AND QLF_CODE     = v_qlf_code
              AND LINE_NO     <> v_line_no
        ) INTO v_dup;
    ELSE
        -- On add, any other row of the same candidate with this code is a duplicate
        SELECT EXISTS (
            SELECT 1
            FROM EMPONB_CAND_SELF_EDUCATION
            WHERE CANDIDATE_ID = v_candidate_id
              AND QLF_CODE     = v_qlf_code
        ) INTO v_dup;
    END IF;

    IF v_dup THEN
        RETURN jsonb_build_object('error',
            'This qualification is already entered for the candidate.');
    END IF;

    RETURN NULL;
END;
$$;
