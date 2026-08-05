/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_validation
function_name: validate_self_qlf_code_duplicate
form_no: 3
field_name: qlf_code
language: plpgsql
description: Block duplicate QLF_CODE within the same candidate's education lines
functional_specification: On save of an EMPONB_CAND_SELF_EDUCATION row: if _action = 'edit', pass without re-checking when QLF_CODE is unchanged for this (CANDIDATE_ID, LINE_NO). Otherwise reject if another row already exists in EMPONB_CAND_SELF_EDUCATION for the same CANDIDATE_ID with the same QLF_CODE (excluding this LINE_NO on edit).
business_logic: Block duplicate QLF_CODE within the same candidate's education lines
*/

CREATE OR REPLACE FUNCTION validate_self_qlf_code_duplicate(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id text    := p->>'CANDIDATE_ID';
    v_qlf_code     text    := p->>'QLF_CODE';
    v_line_no      numeric := NULLIF(p->>'LINE_NO', '')::numeric;
    v_stored_qlf   text;
    v_exists       boolean;
BEGIN
    -- Nothing to check without a qualification code
    IF v_qlf_code IS NULL OR btrim(v_qlf_code) = '' THEN
        RETURN NULL;
    END IF;

    -- In edit mode, pass if the code is unchanged for this exact line
    IF p->>'_action' = 'edit' THEN
        SELECT QLF_CODE
          INTO v_stored_qlf
          FROM EMPONB_CAND_SELF_EDUCATION
         WHERE CANDIDATE_ID = v_candidate_id
           AND LINE_NO      = v_line_no;

        IF FOUND AND v_stored_qlf = v_qlf_code THEN
            RETURN NULL;
        END IF;
    END IF;

    -- Reject if another line for this candidate already uses the same code
    SELECT EXISTS (
             SELECT 1
               FROM EMPONB_CAND_SELF_EDUCATION
              WHERE CANDIDATE_ID = v_candidate_id
                AND QLF_CODE     = v_qlf_code
                AND (v_line_no IS NULL OR LINE_NO <> v_line_no)
           )
      INTO v_exists;

    IF v_exists THEN
        RETURN jsonb_build_object('error',
            'Qualification ' || v_qlf_code || ' is already added for this candidate.');
    END IF;

    RETURN NULL;
END;
$$;
