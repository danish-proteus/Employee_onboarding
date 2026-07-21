/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: field_validation
function_name: check_duplicate_family_member
form_no: 4
field_name: member_name
language: plpgsql
description: Block the same family member name being added twice in the Family section. Purely in-memory - compares only against the other form-4 detail rows currently held in the transaction payload (including rows not yet committed); never reads EMPONB_CAND_FAMILY or any master table.
business_logic: Block the same family member name being added twice in the Family section. Purely in-memory - compares only against the other form-4 detail rows currently held in the transaction payload (including rows not yet committed); never reads EMPONB_CAND_FAMILY or any master table.
*/

CREATE OR REPLACE FUNCTION check_duplicate_family_member(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    -- Current family row (form_no 4, table EMPONB_CAND_FAMILY).
    v_member_name text    := p->>'member_name';                       -- name under edit
    v_line_no     numeric := NULLIF(p->>'line_no', '')::numeric;      -- LINE_NO of the row being edited (NULL for a brand new row)

    -- Position of the current row in the on-screen grid, used to exclude "self"
    -- when the row is new and therefore has no LINE_NO yet. Tolerate the common
    -- envelope key spellings the grid may use for the current row's index.
    v_row_index   numeric := NULLIF(
                                 COALESCE(p->>'_row_index', p->>'_grid_index', p->>'_row', p->>'row_index'),
                                 '')::numeric;

    -- Sibling detail rows currently held in the transaction payload for form 4.
    -- Tolerate the common envelope key spellings for the detail-row array.
    v_grid_rows   jsonb   := COALESCE(
                                 p->'_rows',
                                 p->'_grid_rows',
                                 p->'_detail_rows',
                                 p->'rows',
                                 p->'details'->'4',
                                 '[]'::jsonb);

    v_name_norm   text    := UPPER(TRIM(COALESCE(v_member_name, '')));  -- normalized value for compare
    v_row         jsonb;                 -- iterator over the on-screen rows
    v_idx         int     := 0;          -- position of the row being iterated
    v_row_line    numeric;               -- LINE_NO of the sibling row (if any)
    v_dup         boolean := false;      -- did we find a duplicate on screen?
BEGIN
    -- Blank name is handled by the mandatory check; nothing to compare here.
    IF v_name_norm = '' THEN
        RETURN NULL;
    END IF;

    -- Scan ONLY the other rows the user has added on this screen. No database
    -- lookup is performed, so rows that are not yet committed are still caught.
    IF jsonb_typeof(v_grid_rows) = 'array' THEN
        FOR v_row IN SELECT * FROM jsonb_array_elements(v_grid_rows)
        LOOP
            v_row_line := NULLIF(v_row->>'line_no', '')::numeric;

            -- Skip the current row itself: by LINE_NO when the edited row already
            -- has one, otherwise by grid position for a new (unsaved) row. This
            -- keeps re-editing an existing row from flagging itself.
            IF v_line_no IS NOT NULL AND v_row_line IS NOT NULL THEN
                IF v_row_line = v_line_no THEN
                    v_idx := v_idx + 1;
                    CONTINUE;
                END IF;
            ELSIF v_row_index IS NOT NULL AND v_idx = v_row_index THEN
                v_idx := v_idx + 1;
                CONTINUE;
            END IF;

            -- Case-insensitive, space-trimmed comparison on both sides.
            IF UPPER(TRIM(COALESCE(v_row->>'member_name', ''))) = v_name_norm THEN
                v_dup := true;
                EXIT;
            END IF;

            v_idx := v_idx + 1;
        END LOOP;
    END IF;

    -- No duplicate among the on-screen rows => valid.
    IF NOT v_dup THEN
        RETURN NULL;
    END IF;

    -- Duplicate found => blocking validation error (user cannot proceed).
    RETURN jsonb_build_object(
        'error', 'Member name ''' || TRIM(v_member_name) || ''' has already been entered in the Family details.',
        'errors', jsonb_build_array(
            jsonb_build_object(
                'code',    'FAM_DUP_MEMBER_NAME',
                'field',   'MEMBER_NAME',
                'type',    'E',
                'message', 'Member name ''' || TRIM(v_member_name) || ''' has already been entered in the Family details.'
            )
        )
    );
END;
$$;
