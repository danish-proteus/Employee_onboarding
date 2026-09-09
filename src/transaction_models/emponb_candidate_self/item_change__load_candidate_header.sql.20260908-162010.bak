/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: item_change
function_name: load_candidate_header
trigger_column: candidate_id
language: plpgsql
description: Load the candidate header/profile when a candidate id is entered
functional_specification: When candidate_id is entered, prefer the candidate self record: if a row exists in EMPONB_CANDIDATE_SELF for that id, fill the header/profile fields from EMPONB_CANDIDATE_SELF; otherwise fall back to EMPONB_CANDIDATE_RECORD. The designation display name is resolved from EMPONB_DESIG_DEPT_MASTER. If neither table has the id (or the id is blank) the header fields are cleared. Returns the standard item_change {updates} contract keyed by form column name.
business_logic: Auto-populate the candidate profile from the existing candidate record when HR enters an existing candidate id.
*/

CREATE OR REPLACE FUNCTION emponb_candidate_self__load_candidate_header(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_id      text := NULLIF(trim(p->>'candidate_id'), '');
    v_updates jsonb;
    v_clear   jsonb := '{}'::jsonb;
    f         text;
    -- Header/profile fields shared by the self form and both source tables.
    v_fields  text[] := ARRAY[
        'candidate_name','gender','design_code','design_name','email_id',
        'name_prefix','emp_fname','emp_mname','emp_lname','birthdate','nationality',
        'marital_status','marriage_anniversary','blood_group','religion','cast_category',
        'mother_tongue','physical_handicap','hobby1','hobby2','total_experience',
        'current_address','current_pin','current_city','current_state',
        'permanent_address','permanent_pin','permanent_city','permanent_state',
        'mobile','alternate_telephone','contact_person','contact_person_mobile','contact_person_email',
        'pan_no','aadhar_no','passport_no','driving_lic_no','pf_no','esic_no',
        'bank_account_no','bank_ifsc_code'
    ];
BEGIN
    -- No id yet: clear the header so a stale profile isn't left behind.
    IF v_id IS NULL THEN
        FOREACH f IN ARRAY v_fields LOOP
            v_clear := v_clear || jsonb_build_object(f, '');
        END LOOP;
        RETURN jsonb_build_object('updates', v_clear);
    END IF;

    -- Prefer the candidate self record.
    SELECT to_jsonb(sub) INTO v_updates FROM (
        SELECT s.candidate_name, s.gender, s.design_code,
               dm.designation_name AS design_name,
               s.email_id, s.name_prefix, s.emp_fname, s.emp_mname, s.emp_lname,
               s.birthdate, s.nationality, s.marital_status, s.marriage_anniversary,
               s.blood_group, s.religion, s.cast_category, s.mother_tongue,
               s.physical_handicap, s.hobby1, s.hobby2, s.total_experience,
               s.current_address, s.current_pin, s.current_city, s.current_state,
               s.permanent_address, s.permanent_pin, s.permanent_city, s.permanent_state,
               s.mobile, s.alternate_telephone, s.contact_person, s.contact_person_mobile,
               s.contact_person_email, s.pan_no, s.aadhar_no, s.passport_no,
               s.driving_lic_no, s.pf_no, s.esic_no, s.bank_account_no, s.bank_ifsc_code
        FROM emponb_candidate_self s
        LEFT JOIN emponb_desig_dept_master dm ON dm.design_code = s.design_code
        WHERE s.candidate_id = v_id
        LIMIT 1
    ) sub;

    -- Fall back to the candidate onboarding record.
    IF v_updates IS NULL THEN
        SELECT to_jsonb(sub) INTO v_updates FROM (
            SELECT r.candidate_name, r.gender, r.design_code,
                   dm.designation_name AS design_name,
                   r.email_id, r.name_prefix, r.emp_fname, r.emp_mname, r.emp_lname,
                   r.birthdate, r.nationality, r.marital_status, r.marriage_anniversary,
                   r.blood_group, r.religion, r.cast_category, r.mother_tongue,
                   r.physical_handicap, r.hobby1, r.hobby2, r.total_experience,
                   r.current_address, r.current_pin, r.current_city, r.current_state,
                   r.permanent_address, r.permanent_pin, r.permanent_city, r.permanent_state,
                   r.mobile, r.alternate_telephone, r.contact_person, r.contact_person_mobile,
                   r.contact_person_email, r.pan_no, r.aadhar_no, r.passport_no,
                   r.driving_lic_no, r.pf_no, r.esic_no, r.bank_account_no, r.bank_ifsc_code
            FROM emponb_candidate_record r
            LEFT JOIN emponb_desig_dept_master dm ON dm.design_code = r.design_code
            WHERE r.candidate_id = v_id
            LIMIT 1
        ) sub;
    END IF;

    -- Neither table has the id: clear the header.
    IF v_updates IS NULL THEN
        FOREACH f IN ARRAY v_fields LOOP
            v_clear := v_clear || jsonb_build_object(f, '');
        END LOOP;
        RETURN jsonb_build_object('updates', v_clear);
    END IF;

    -- Overwrite EVERY header field: fill it from the source row when present,
    -- otherwise blank it — so no stale value from a prior candidate is left behind.
    v_clear := '{}'::jsonb;
    FOREACH f IN ARRAY v_fields LOOP
        v_clear := v_clear || jsonb_build_object(f, COALESCE(v_updates->>f, ''));
    END LOOP;
    RETURN jsonb_build_object('updates', v_clear);
END;
$$;
