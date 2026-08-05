/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_validation
function_name: validate_family_gender_relation
form_no: 4
field_name: relation
language: plpgsql
description: Block inconsistent gender/relation combinations
functional_specification: Field-level validation on RELATION of the Family detail form (and re-invoked via the GENDER column's item_change). Reject the combination and return the exact matching message for: GENDER='F' and RELATION='Brother' -> 'Brother cannot be female.'; GENDER='F' and RELATION='Father' -> 'Father cannot be female.'; GENDER='F' and RELATION='GrandFather' -> 'GrandFather cannot be female.'; GENDER='F' and RELATION='Son' -> 'Son cannot be female.'; GENDER='F' and RELATION='Husband' -> 'Husband cannot be female.'; GENDER='M' and RELATION='Mother' -> 'Mother cannot be male.'; GENDER='M' and RELATION='Sister' -> 'Sister cannot be male.'; GENDER='M' and RELATION='GrandMother' -> 'GrandMother cannot be male.'; GENDER='M' and RELATION='Wife' -> 'Wife cannot be male.'; GENDER='M' and RELATION='Daughter' -> 'Daughter cannot be male.'. All other GENDER/RELATION combinations pass. Return NULL/no error when GENDER or RELATION is blank.
business_logic: Block inconsistent gender/relation combinations
*/

CREATE OR REPLACE FUNCTION validate_family_gender_relation(p jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
    v_gender   text := btrim(COALESCE(p->>'GENDER', ''));
    v_relation text := btrim(COALESCE(p->>'RELATION', ''));
    v_msg      text;
BEGIN
    -- Nothing to check until both gender and relation are supplied.
    IF v_gender = '' OR v_relation = '' THEN
        RETURN NULL;
    END IF;

    -- Reject only the logically inconsistent gender/relation combinations.
    IF v_gender = 'F' THEN
        v_msg := CASE v_relation
                    WHEN 'Brother'     THEN 'Brother cannot be female.'
                    WHEN 'Father'      THEN 'Father cannot be female.'
                    WHEN 'GrandFather' THEN 'GrandFather cannot be female.'
                    WHEN 'Son'         THEN 'Son cannot be female.'
                    WHEN 'Husband'     THEN 'Husband cannot be female.'
                    ELSE NULL
                 END;
    ELSIF v_gender = 'M' THEN
        v_msg := CASE v_relation
                    WHEN 'Mother'      THEN 'Mother cannot be male.'
                    WHEN 'Sister'      THEN 'Sister cannot be male.'
                    WHEN 'GrandMother' THEN 'GrandMother cannot be male.'
                    WHEN 'Wife'        THEN 'Wife cannot be male.'
                    WHEN 'Daughter'    THEN 'Daughter cannot be male.'
                    ELSE NULL
                 END;
    END IF;

    IF v_msg IS NOT NULL THEN
        RETURN jsonb_build_object('error', v_msg);
    END IF;

    RETURN NULL;
END;
$$;
