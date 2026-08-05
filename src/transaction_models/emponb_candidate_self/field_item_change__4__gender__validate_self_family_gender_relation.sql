/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_item_change
function_name: validate_self_family_gender_relation
form_no: 4
field_name: gender
language: plpgsql
description: Validate gender-relation combination on gender change
functional_specification: On change of GENDER, check the current RELATION on the row. Block the combination (return an error / do not update) for: Female+Brother ('Brother cannot be female.'), Female+Father ('Father cannot be female.'), Female+GrandFather ('GrandFather cannot be female.'), Female+Son ('Son cannot be female.'), Female+Husband ('Husband cannot be female.'), Male+Mother ('Mother cannot be male.'), Male+Sister ('Sister cannot be male.'), Male+GrandMother ('GrandMother cannot be male.'), Male+Wife ('Wife cannot be male.'), Male+Daughter ('Daughter cannot be male.'). Return no updates when the combination is valid.
business_logic: Validate gender-relation combination on gender change
*/

CREATE OR REPLACE FUNCTION validate_self_family_gender_relation(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_gender   text := upper(btrim(COALESCE(p->>'GENDER','')));
    v_relation text := lower(btrim(COALESCE(p->>'RELATION','')));
BEGIN
    -- Nothing to check until both gender and relation are present on the row
    IF v_gender = '' OR v_relation = '' THEN
        RETURN NULL;
    END IF;

    -- Female cannot hold an inherently-male relation
    IF v_gender = 'F' THEN
        IF v_relation = 'brother'     THEN RETURN jsonb_build_object('error', 'Brother cannot be female.');     END IF;
        IF v_relation = 'father'      THEN RETURN jsonb_build_object('error', 'Father cannot be female.');      END IF;
        IF v_relation = 'grandfather' THEN RETURN jsonb_build_object('error', 'GrandFather cannot be female.'); END IF;
        IF v_relation = 'son'         THEN RETURN jsonb_build_object('error', 'Son cannot be female.');         END IF;
        IF v_relation = 'husband'     THEN RETURN jsonb_build_object('error', 'Husband cannot be female.');     END IF;
    END IF;

    -- Male cannot hold an inherently-female relation
    IF v_gender = 'M' THEN
        IF v_relation = 'mother'      THEN RETURN jsonb_build_object('error', 'Mother cannot be male.');      END IF;
        IF v_relation = 'sister'      THEN RETURN jsonb_build_object('error', 'Sister cannot be male.');      END IF;
        IF v_relation = 'grandmother' THEN RETURN jsonb_build_object('error', 'GrandMother cannot be male.'); END IF;
        IF v_relation = 'wife'        THEN RETURN jsonb_build_object('error', 'Wife cannot be male.');        END IF;
        IF v_relation = 'daughter'    THEN RETURN jsonb_build_object('error', 'Daughter cannot be male.');    END IF;
    END IF;

    RETURN NULL;
END;
$$;
