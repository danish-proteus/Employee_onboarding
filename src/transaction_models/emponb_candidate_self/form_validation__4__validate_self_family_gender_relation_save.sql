/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: form_validation
function_name: validate_self_family_gender_relation_save
form_no: 4
language: plpgsql
description: Final save-time check of gender/relation combination
functional_specification: On save of an EMPONB_CAND_SELF_FAMILY row, re-validate GENDER against RELATION using the same disallowed-combination list as the field-level checks (Female+Brother/Father/GrandFather/Son/Husband, Male+Mother/Sister/GrandMother/Wife/Daughter) and reject with the matching message if violated.
business_logic: Final save-time check of gender/relation combination
*/

CREATE OR REPLACE FUNCTION validate_self_family_gender_relation_save(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
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
