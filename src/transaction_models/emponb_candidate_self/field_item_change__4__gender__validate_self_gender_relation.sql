/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_item_change
function_name: validate_self_gender_relation
form_no: 4
field_name: gender
language: plpgsql
description: Validate gender/relation combination on change of gender
functional_specification: On change of GENDER (with RELATION already selected on the same family row): block disallowed combinations by returning an error - Female+Brother 'Brother cannot be female.', Female+Father 'Father cannot be female.', Female+GrandFather 'GrandFather cannot be female.', Female+Son 'Son cannot be female.', Female+Husband 'Husband cannot be female.', Male+Mother 'Mother cannot be male.', Male+Sister 'Sister cannot be male.', Male+GrandMother 'GrandMother cannot be male.', Male+Wife 'Wife cannot be male.', Male+Daughter 'Daughter cannot be male.'. If the combination is allowed, return no updates.
business_logic: Validate gender/relation combination on change of gender
*/

CREATE OR REPLACE FUNCTION validate_self_gender_relation(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_gender   text := p->>'GENDER';
    v_relation text := p->>'RELATION';
    v_msg      text;
BEGIN
    -- Need both values on the row to validate the combination
    IF v_gender IS NULL OR btrim(v_gender) = ''
       OR v_relation IS NULL OR btrim(v_relation) = '' THEN
        RETURN NULL;
    END IF;

    v_msg := CASE
        WHEN v_gender = 'F' AND v_relation = 'Brother'     THEN 'Brother cannot be female.'
        WHEN v_gender = 'F' AND v_relation = 'Father'      THEN 'Father cannot be female.'
        WHEN v_gender = 'F' AND v_relation = 'GrandFather' THEN 'GrandFather cannot be female.'
        WHEN v_gender = 'F' AND v_relation = 'Son'         THEN 'Son cannot be female.'
        WHEN v_gender = 'F' AND v_relation = 'Husband'     THEN 'Husband cannot be female.'
        WHEN v_gender = 'M' AND v_relation = 'Mother'      THEN 'Mother cannot be male.'
        WHEN v_gender = 'M' AND v_relation = 'Sister'      THEN 'Sister cannot be male.'
        WHEN v_gender = 'M' AND v_relation = 'GrandMother' THEN 'GrandMother cannot be male.'
        WHEN v_gender = 'M' AND v_relation = 'Wife'        THEN 'Wife cannot be male.'
        WHEN v_gender = 'M' AND v_relation = 'Daughter'    THEN 'Daughter cannot be male.'
        ELSE NULL
    END;

    IF v_msg IS NOT NULL THEN
        RETURN jsonb_build_object('error', v_msg);
    END IF;

    RETURN NULL;
END;
$$;
