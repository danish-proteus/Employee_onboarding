/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_item_change
function_name: copy_current_to_permanent_address
form_no: 1
field_name: same_as_current_address
language: plpgsql
description: Copy current address into permanent address when checkbox is checked
functional_specification: On change of SAME_AS_CURRENT_ADDRESS: if the new value is Y, set PERMANENT_ADDRESS = CURRENT_ADDRESS, PERMANENT_PIN = CURRENT_PIN, PERMANENT_CITY = CURRENT_CITY, PERMANENT_STATE = CURRENT_STATE on the form (using the actual current/permanent address column names already present on this header form) and mark those permanent address fields protected/read-only in the UI. If the new value is N, leave the current permanent address field values as-is and make them editable again (remove the protect flag).
business_logic: Copy current address into permanent address when checkbox is checked
*/

CREATE OR REPLACE FUNCTION copy_current_to_permanent_address(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    -- Checkbox value; sourced from a CHAR(1) column so it arrives trimmed. Normalise case.
    v_same_flag text := UPPER(COALESCE(TRIM(p->>'SAME_AS_CURRENT_ADDRESS'), ''));
BEGIN
    IF v_same_flag = 'Y' THEN
        -- Checked: mirror the current address block (from the incoming payload) into the
        -- permanent block and lock those fields so the candidate can't hand-edit them.
        RETURN jsonb_build_object(
            'updates', jsonb_build_object(
                'PERMANENT_ADDRESS', jsonb_build_object('value', p->>'CURRENT_ADDRESS', 'protect', '1'),
                'PERMANENT_PIN',     jsonb_build_object('value', p->>'CURRENT_PIN',     'protect', '1'),
                'PERMANENT_CITY',    jsonb_build_object('value', p->>'CURRENT_CITY',    'protect', '1'),
                'PERMANENT_STATE',   jsonb_build_object('value', p->>'CURRENT_STATE',   'protect', '1')
            )
        );
    END IF;

    -- Unchecked / cleared: keep the existing permanent values as-is, only unlock the fields
    RETURN jsonb_build_object(
        'updates', jsonb_build_object(
            'PERMANENT_ADDRESS', jsonb_build_object('value', p->>'PERMANENT_ADDRESS', 'protect', '0'),
            'PERMANENT_PIN',     jsonb_build_object('value', p->>'PERMANENT_PIN',     'protect', '0'),
            'PERMANENT_CITY',    jsonb_build_object('value', p->>'PERMANENT_CITY',    'protect', '0'),
            'PERMANENT_STATE',   jsonb_build_object('value', p->>'PERMANENT_STATE',   'protect', '0')
        )
    );
END;
$$;
