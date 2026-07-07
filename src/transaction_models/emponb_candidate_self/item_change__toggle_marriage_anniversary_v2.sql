/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: item_change
function_name: toggle_marriage_anniversary_v2
trigger_column: marital_status
language: plpgsql
description: Toggle marriage anniversary edit/clear based on marital status
functional_specification: When marital_status = 'Yes', make MARRIAGE_ANNIVERSARY editable (unprotect) without altering its value. When marital_status is anything else ('No' or blank), clear MARRIAGE_ANNIVERSARY and make it non-editable (protect). Returns the standard item_change {updates, protect} contract keyed by the form column name.
business_logic: Enable marriage anniversary only when marital status is Yes
*/

CREATE OR REPLACE FUNCTION emponb_candidate_self__toggle_marriage_anniversary_v2(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_marital text := p->>'marital_status';
BEGIN
    IF v_marital = 'Yes' THEN
        -- Married: keep the anniversary editable, don't touch its value.
        RETURN jsonb_build_object(
            'protect', jsonb_build_object('marriage_anniversary', false)
        );
    ELSE
        -- Not married / not answered: clear the anniversary and lock it.
        -- Use '' (empty string), NOT SQL NULL: the engine drops null-valued
        -- keys from `updates` (null = "no change"), so a NULL never clears the
        -- field on the client. An empty string is delivered and clears it.
        RETURN jsonb_build_object(
            'updates', jsonb_build_object('marriage_anniversary', ''),
            'protect', jsonb_build_object('marriage_anniversary', true)
        );
    END IF;
END;
$$;
