/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_validation
function_name: check_self_qualification_duplicate
form_no: 3
field_name: qlf_code
language: plpgsql
description: Block duplicate QLF_CODE lines for the same candidate
functional_specification: Excluding the row being edited when _action = 'edit' (match on CANDIDATE_ID and LINE_NO), check whether another EMPONB_CAND_SELF_EDUCATION row for the same CANDIDATE_ID already has this QLF_CODE; if found, return an error that the qualification is already added.
business_logic: Block duplicate QLF_CODE lines for the same candidate
*/

CREATE OR REPLACE FUNCTION check_self_qualification_duplicate(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id text    := p->>'CANDIDATE_ID';
    v_qlf_code     text    := p->>'QLF_CODE';
    v_line_no      numeric := NULLIF(p->>'LINE_NO','')::numeric;
    v_exists       boolean;
BEGIN
    -- Nothing to validate until candidate and qualification are known
    IF v_candidate_id IS NULL OR v_qlf_code IS NULL OR v_qlf_code = '' THEN
        RETURN NULL;
    END IF;

    -- Another education line of the same candidate already carrying this qualification?
    -- On edit, exclude the row being edited (same CANDIDATE_ID + LINE_NO).
    SELECT EXISTS (
        SELECT 1
        FROM EMPONB_CAND_SELF_EDUCATION e
        WHERE e.CANDIDATE_ID = v_candidate_id
          AND e.QLF_CODE = v_qlf_code
          AND (p->>'_action' <> 'edit' OR v_line_no IS NULL OR e.LINE_NO <> v_line_no)
    ) INTO v_exists;

    IF v_exists THEN
        RETURN jsonb_build_object('error', 'Qualification ' || v_qlf_code || ' is already added for this candidate.');
    END IF;

    RETURN NULL;
END;
$$;
