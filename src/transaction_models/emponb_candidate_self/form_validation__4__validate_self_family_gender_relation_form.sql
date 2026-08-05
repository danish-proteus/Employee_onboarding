/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: form_validation
function_name: validate_self_family_gender_relation_form
form_no: 4
language: plpgsql
description: Form-level gender/relation consistency check on save
functional_specification: On save of a family line, validate GENDER against RELATION per the same combination rules used on item_change (Female cannot be Brother/Father/GrandFather/Son/Husband; Male cannot be Mother/Sister/GrandMother/Wife/Daughter). Return the specific mismatch message as the error when a blocked combination is found; otherwise pass.
business_logic: Form-level gender/relation consistency check on save
*/

CREATE OR REPLACE FUNCTION validate_self_family_gender_relation_form(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_gender   text := upper(btrim(COALESCE(p->>'GENDER','')));
    v_relation text := lower(btrim(COALESCE(p->>'RELATION','')));
BEGIN
    -- Nothing to check until both gender and relation are supplied
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
