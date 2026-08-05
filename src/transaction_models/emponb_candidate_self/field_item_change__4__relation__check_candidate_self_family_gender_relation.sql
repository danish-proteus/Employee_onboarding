/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_item_change
function_name: check_candidate_self_family_gender_relation
form_no: 4
field_name: relation
language: plpgsql
description: Validate gender/relation consistency on RELATION change
functional_specification: When RELATION changes, check it against the current GENDER on the row. Disallowed combinations, each blocked with its exact message: Female+Brother ('Brother cannot be female.'), Female+Father ('Father cannot be female.'), Female+GrandFather ('GrandFather cannot be female.'), Female+Son ('Son cannot be female.'), Female+Husband ('Husband cannot be female.'), Male+Mother ('Mother cannot be male.'), Male+Sister ('Sister cannot be male.'), Male+GrandMother ('GrandMother cannot be male.'), Male+Wife ('Wife cannot be male.'), Male+Daughter ('Daughter cannot be male.'). If disallowed, return an error with the matching message and leave RELATION unchanged; otherwise return no updates.
business_logic: Validate gender/relation consistency on RELATION change
*/

CREATE OR REPLACE FUNCTION check_candidate_self_family_gender_relation(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_gender   text := p->>'GENDER';    -- M / F / O
    v_relation text := p->>'RELATION';  -- family relation just changed
BEGIN
    -- Nothing to validate until both values are present
    IF v_gender IS NULL OR v_relation IS NULL THEN
        RETURN NULL;
    END IF;

    -- Female gender cannot hold a male-only relation
    IF v_gender = 'F' THEN
        CASE v_relation
            WHEN 'Brother'     THEN RETURN jsonb_build_object('error', 'Brother cannot be female.');
            WHEN 'Father'      THEN RETURN jsonb_build_object('error', 'Father cannot be female.');
            WHEN 'GrandFather' THEN RETURN jsonb_build_object('error', 'GrandFather cannot be female.');
            WHEN 'Son'         THEN RETURN jsonb_build_object('error', 'Son cannot be female.');
            WHEN 'Husband'     THEN RETURN jsonb_build_object('error', 'Husband cannot be female.');
            ELSE NULL;
        END CASE;
    -- Male gender cannot hold a female-only relation
    ELSIF v_gender = 'M' THEN
        CASE v_relation
            WHEN 'Mother'      THEN RETURN jsonb_build_object('error', 'Mother cannot be male.');
            WHEN 'Sister'      THEN RETURN jsonb_build_object('error', 'Sister cannot be male.');
            WHEN 'GrandMother' THEN RETURN jsonb_build_object('error', 'GrandMother cannot be male.');
            WHEN 'Wife'        THEN RETURN jsonb_build_object('error', 'Wife cannot be male.');
            WHEN 'Daughter'    THEN RETURN jsonb_build_object('error', 'Daughter cannot be male.');
            ELSE NULL;
        END CASE;
    END IF;

    -- Combination is valid; leave the form untouched
    RETURN NULL;
END;
$$;
