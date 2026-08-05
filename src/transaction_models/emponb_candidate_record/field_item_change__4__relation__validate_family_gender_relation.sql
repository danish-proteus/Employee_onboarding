/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: field_item_change
function_name: validate_family_gender_relation
form_no: 4
field_name: relation
language: plpgsql
description: Block gender/relation combinations that are not physiologically consistent
functional_specification: Same rule as on GENDER — re-run on RELATION change so the check fires whenever either column is entered/changed.
business_logic: Block gender/relation combinations that are not physiologically consistent
*/

CREATE OR REPLACE FUNCTION validate_family_gender_relation(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    -- Family detail row values (flat payload of form 4).
    v_gender   varchar(1)  := NULLIF(TRIM(COALESCE(p->>'GENDER',   p->>'gender')),   '');
    v_relation varchar(10) := NULLIF(TRIM(COALESCE(p->>'RELATION', p->>'relation')), '');
    v_expected varchar(1);  -- gender the relation implies, NULL when unconstrained
BEGIN
    -- Nothing to check until both columns carry a value.
    IF v_gender IS NULL OR v_relation IS NULL THEN
        RETURN NULL;
    END IF;

    -- Relations that imply a gender. Spouse / Guardian / Other are deliberately
    -- left unconstrained: they are valid for any gender.
    v_expected := CASE v_relation
                      WHEN 'Father'   THEN 'M'
                      WHEN 'Husband'  THEN 'M'
                      WHEN 'Son'      THEN 'M'
                      WHEN 'Brother'  THEN 'M'
                      WHEN 'Mother'   THEN 'F'
                      WHEN 'Wife'     THEN 'F'
                      WHEN 'Daughter' THEN 'F'
                      WHEN 'Sister'   THEN 'F'
                      ELSE NULL
                  END;

    IF v_expected IS NULL OR v_gender = v_expected THEN
        RETURN NULL;  -- consistent, or the relation places no constraint
    END IF;

    -- Inconsistent combination: block it and tell the user what is expected.
    RETURN jsonb_build_object(
        'error',
        'Relation "' || v_relation || '" requires gender ' ||
        CASE v_expected WHEN 'M' THEN 'Male' ELSE 'Female' END ||
        '. Please correct the gender or the relation.'
    );
END;
$$;
