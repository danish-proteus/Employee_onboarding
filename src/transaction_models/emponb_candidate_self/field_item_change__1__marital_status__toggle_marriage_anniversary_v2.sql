/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_item_change
function_name: toggle_marriage_anniversary_v2
form_no: 1
field_name: marital_status
language: plpgsql
description: Enable and keep the marriage anniversary editable only when marital status is Yes; otherwise clear it and make it non-editable
business_logic: Enable and keep the marriage anniversary editable only when marital status is Yes; otherwise clear it and make it non-editable
*/

CREATE OR REPLACE FUNCTION field_item_change__1__marital_status__toggle_marriage_anniversary_v2(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_marital_status text := p->>'MARITAL_STATUS';
BEGIN
    -- When married (Yes): keep MARRIAGE_ANNIVERSARY editable (unlock the cell).
    -- Otherwise: clear the value and lock the cell so it cannot be edited.
    IF v_marital_status = 'Yes' THEN
        RETURN jsonb_build_object(
            'updates', jsonb_build_object(
                'MARRIAGE_ANNIVERSARY', jsonb_build_object('protect', '0')
            )
        );
    ELSE
        RETURN jsonb_build_object(
            'updates', jsonb_build_object(
                'MARRIAGE_ANNIVERSARY', jsonb_build_object('value', NULL, 'protect', '1')
            )
        );
    END IF;
END;
$$;
