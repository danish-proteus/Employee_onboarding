/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_validation
function_name: check_email_id_unique_self
form_no: 1
field_name: email_id
language: plpgsql
description: Block duplicate candidate emails across self and HR records
functional_specification: Field-level validation on EMAIL_ID of the Candidate Self header. On add (_action = 'add') check both EMPONB_CANDIDATE_SELF and EMPONB_CANDIDATE_RECORD for any OTHER row already holding this EMAIL_ID and return an error if found. On edit (_action = 'edit') skip the check when the incoming EMAIL_ID is unchanged from the stored EMPONB_CANDIDATE_SELF value for this CANDIDATE_ID; otherwise run the same duplicate search excluding the current CANDIDATE_ID's own row.
business_logic: Block duplicate candidate emails across self and HR records
*/

CREATE OR REPLACE FUNCTION check_email_id_unique_self(p jsonb) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE
    v_email        text := btrim(COALESCE(p->>'EMAIL_ID', ''));
    v_candidate_id text := btrim(COALESCE(p->>'CANDIDATE_ID', ''));
    v_action       text := COALESCE(p->>'_action', 'add');
    v_stored_email text;
    v_dup          integer;
BEGIN
    -- Nothing to validate when no email entered.
    IF v_email = '' THEN
        RETURN NULL;
    END IF;

    -- On edit, skip when the email is unchanged from what is stored for this candidate.
    IF v_action = 'edit' AND v_candidate_id <> '' THEN
        SELECT btrim(s.EMAIL_ID)
          INTO v_stored_email
          FROM EMPONB_CANDIDATE_SELF s
         WHERE s.CANDIDATE_ID = v_candidate_id::char(10);

        IF FOUND AND v_stored_email = v_email THEN
            RETURN NULL;
        END IF;
    END IF;

    -- Duplicate search across both the self and HR candidate records, excluding this
    -- candidate's own row (email compared value-to-column; column left un-wrapped).
    SELECT 1
      INTO v_dup
     WHERE EXISTS (
             SELECT 1 FROM EMPONB_CANDIDATE_SELF s
              WHERE s.EMAIL_ID = v_email
                AND s.CANDIDATE_ID <> v_candidate_id::char(10)
           )
        OR EXISTS (
             SELECT 1 FROM EMPONB_CANDIDATE_RECORD r
              WHERE r.EMAIL_ID = v_email
                AND r.CANDIDATE_ID <> v_candidate_id::char(10)
           );

    IF FOUND THEN
        RETURN jsonb_build_object('error',
            'Email id ''' || v_email || ''' already exists for another candidate.');
    END IF;

    RETURN NULL;
END;
$$;
