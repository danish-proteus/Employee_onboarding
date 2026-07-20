/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_validation
function_name: check_duplicate_qualification
form_no: 3
field_name: qlf_code
language: plpgsql
description: Block saving when the selected QLF_CODE is already present on another education line of the same candidate, checking both the unsaved sibling rows in the current transaction grid and the persisted EMPONB_CAND_SELF_EDUCATION rows.
business_logic: Block saving when the selected QLF_CODE is already present on another education line of the same candidate, checking both the unsaved sibling rows in the current transaction grid and the persisted EMPONB_CAND_SELF_EDUCATION rows.
*/

CREATE OR REPLACE FUNCTION check_duplicate_qualification(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    -- Current education row (form_no 3, table EMPONB_CAND_SELF_EDUCATION).
    v_candidate_id char(10)  := p->>'candidate_id';   -- parent/header key
    v_qlf_code     char(10)  := p->>'qlf_code';        -- qualification under edit
    v_line_no      numeric   := NULLIF(p->>'line_no', '')::numeric;  -- key of a saved row (NULL for a new unsaved row)

    -- Position of the current grid row, used to exclude "self" when the row is
    -- new and therefore has no LINE_NO yet. Tolerate the common envelope key
    -- spellings the grid may use for the current row's index.
    v_row_index    numeric   := NULLIF(
                                    COALESCE(p->>'_row_index', p->>'_grid_index', p->>'_row', p->>'row_index'),
                                    '')::numeric;

    -- Sibling detail rows currently held in the transaction grid (unsaved).
    -- Tolerate the common envelope key spellings for the detail-row array.
    v_grid_rows    jsonb     := COALESCE(p->'_rows', p->'_grid_rows', p->'_detail_rows', p->'rows', '[]'::jsonb);

    v_qlf_norm     text      := UPPER(TRIM(COALESCE(v_qlf_code, '')));  -- normalized value for in-memory compare
    v_row          jsonb;      -- iterator over grid siblings
    v_idx          int := 0;   -- position of the row being iterated
    v_row_line     numeric;    -- LINE_NO of the sibling row (if any)
    v_dup          boolean := false;  -- did we find a duplicate anywhere?
BEGIN
    -- (2) Empty qualification is handled by mandatory/must_exist checks; there is
    -- nothing to compare here, so treat it as valid.
    IF v_qlf_norm = '' THEN
        RETURN NULL;
    END IF;

    -- Candidate must be identified to scope the duplicate check.
    IF v_candidate_id IS NULL OR TRIM(v_candidate_id) = '' THEN
        RETURN NULL;
    END IF;

    -- (3a) Scan the OTHER unsaved education rows held in the transaction grid.
    IF jsonb_typeof(v_grid_rows) = 'array' THEN
        FOR v_row IN SELECT * FROM jsonb_array_elements(v_grid_rows)
        LOOP
            v_row_line := NULLIF(v_row->>'line_no', '')::numeric;

            -- Skip the current row itself: by LINE_NO when both rows are saved,
            -- otherwise by grid position for a new (unsaved) row.
            IF v_line_no IS NOT NULL AND v_row_line IS NOT NULL THEN
                IF v_row_line = v_line_no THEN
                    v_idx := v_idx + 1;
                    CONTINUE;
                END IF;
            ELSIF v_row_index IS NOT NULL AND v_idx = v_row_index THEN
                v_idx := v_idx + 1;
                CONTINUE;
            END IF;

            -- Same qualification on a different grid row => duplicate.
            IF UPPER(TRIM(COALESCE(v_row->>'qlf_code', ''))) = v_qlf_norm THEN
                v_dup := true;
                EXIT;
            END IF;

            v_idx := v_idx + 1;
        END LOOP;
    END IF;

    -- (4) Scan the persisted rows for the same candidate. Keep the predicate
    -- sargable: compare the key/qualification columns directly and exclude the
    -- current saved row by LINE_NO.
    IF NOT v_dup THEN
        PERFORM 1
           FROM EMPONB_CAND_SELF_EDUCATION
          WHERE CANDIDATE_ID = v_candidate_id
            AND QLF_CODE      = v_qlf_code
            AND (v_line_no IS NULL OR LINE_NO <> v_line_no)
          LIMIT 1;
        IF FOUND THEN
            v_dup := true;
        END IF;
    END IF;

    -- (5) No duplicate anywhere => valid.
    IF NOT v_dup THEN
        RETURN NULL;
    END IF;

    -- Duplicate found in either source => blocking validation error.
    RETURN jsonb_build_object(
        'error', 'Duplicate qualification is not allowed. This qualification is already added for this candidate.',
        'errors', jsonb_build_array(
            jsonb_build_object(
                'code',    'EDU_QLF_DUP',
                'field',   'QLF_CODE',
                'type',    'E',
                'message', 'Duplicate qualification is not allowed. This qualification is already added for this candidate.'
            )
        )
    );
END;
$$;
