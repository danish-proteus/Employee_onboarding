/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: action
action_name: Submit
function_name: submit_to_candidate_record
language: plpgsql
description: Submit candidate self-service data to the Candidate Onboarding Record
functional_specification: Push the candidate's self-service data (from EMPONB_CANDIDATE_SELF and
  its detail tables) into the HR Candidate Onboarding Record for the CANDIDATE_ID on the current
  form. (1) UPDATE EMPONB_CANDIDATE_RECORD (matched on CANDIDATE_ID) with every candidate-supplied
  header field common to both tables (personal identity, contact/address, statutory/financial) and
  stamp STATUS='DataSubmitted', STATUS_DATE=now(), SUBMITTED_ON=now(). (2) Refresh every detail
  table (experience/education/family/pay): delete the record-side rows for this CANDIDATE_ID and
  re-insert one row per self-side row, carrying CANDIDATE_ID + LINE_NO. If no record row exists,
  return {"error":...}. On success return {"message":...} with the CANDIDATE_ID and copied counts.
  The whole operation is atomic - any failure rolls the action back.
business_logic: Submit candidate self-service data to the Candidate Onboarding Record
*/

CREATE OR REPLACE FUNCTION emponb_candidate_self__submit_to_candidate_record(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    -- CANDIDATE_ID is CHAR(10): the value is stored space-padded (e.g. '1' -> '1         ').
    -- Trim the incoming id and rtrim() every char column in the WHEREs below, otherwise a
    -- char(10)-vs-text comparison keeps the trailing blanks and never matches ('1        ' <> '1').
    v_cid   text := btrim(p->>'candidate_id');
    v_found int;
    v_exp   int := 0;
    v_edu   int := 0;
    v_fam   int := 0;
    v_pay   int := 0;
BEGIN
    -- Guard: a candidate id must be supplied on the form.
    IF v_cid IS NULL OR v_cid = '' THEN
        RETURN jsonb_build_object('error', 'No candidate id was supplied for submission.');
    END IF;

    -- The onboarding record must already exist (it is created HR-side at initiation).
    SELECT count(*) INTO v_found
    FROM emponb_candidate_record
    WHERE rtrim(candidate_id) = v_cid;

    IF v_found = 0 THEN
        RETURN jsonb_build_object(
            'error',
            format('No Candidate Onboarding Record exists for candidate %s. Data cannot be submitted.', v_cid)
        );
    END IF;

    -- (1) Header: copy the candidate-supplied fields common to both tables and stamp lifecycle.
    UPDATE emponb_candidate_record r SET
        -- personal identity
        name_prefix           = s.name_prefix,
        emp_fname             = s.emp_fname,
        emp_mname             = s.emp_mname,
        emp_lname             = s.emp_lname,
        birthdate             = s.birthdate,
        nationality           = s.nationality,
        marital_status        = s.marital_status,
        marriage_anniversary  = s.marriage_anniversary,
        blood_group           = s.blood_group,
        religion              = s.religion,
        cast_category         = s.cast_category,
        mother_tongue         = s.mother_tongue,
        physical_handicap     = s.physical_handicap,
        hobby1                = s.hobby1,
        hobby2                = s.hobby2,
        total_experience      = s.total_experience,
        -- contact / address
        current_address       = s.current_address,
        current_pin           = s.current_pin,
        current_city          = s.current_city,
        current_state         = s.current_state,
        permanent_address     = s.permanent_address,
        permanent_pin         = s.permanent_pin,
        permanent_city        = s.permanent_city,
        permanent_state       = s.permanent_state,
        mobile                = s.mobile,
        alternate_telephone   = s.alternate_telephone,
        contact_person        = s.contact_person,
        contact_person_mobile = s.contact_person_mobile,
        contact_person_email  = s.contact_person_email,
        -- statutory / financial
        pan_no                = s.pan_no,
        aadhar_no             = s.aadhar_no,
        passport_no           = s.passport_no,
        driving_lic_no        = s.driving_lic_no,
        pf_no                 = s.pf_no,
        esic_no               = s.esic_no,
        bank_account_no       = s.bank_account_no,
        bank_ifsc_code        = s.bank_ifsc_code,
        bank_name             = s.bank_name,
        -- lifecycle stamp
        status                = 'DataSubmitted',
        status_date           = now(),
        submitted_on          = now()
    FROM emponb_candidate_self s
    WHERE rtrim(r.candidate_id) = v_cid
      AND rtrim(s.candidate_id) = v_cid;

    -- (2) Detail refresh: delete + re-insert one row per self-side row (parent-detail link preserved).

    -- Experience
    DELETE FROM emponb_cand_experience WHERE rtrim(candidate_id) = v_cid;
    INSERT INTO emponb_cand_experience
        (candidate_id, line_no, organisation, designation, from_date, to_date, gross_amt, currency_code, country_code)
    SELECT candidate_id, line_no, organisation, designation, from_date, to_date, gross_amt, currency_code, country_code
    FROM emponb_cand_self_experience
    WHERE rtrim(candidate_id) = v_cid;
    GET DIAGNOSTICS v_exp = ROW_COUNT;

    -- Education
    DELETE FROM emponb_cand_education WHERE rtrim(candidate_id) = v_cid;
    INSERT INTO emponb_cand_education
        (candidate_id, line_no, qlf_code, qlf_type, institute, pass_year, class, percentage, country_code, course_type, course_duration)
    SELECT candidate_id, line_no, qlf_code, qlf_type, institute, pass_year, class, percentage, country_code, course_type, course_duration
    FROM emponb_cand_self_education
    WHERE rtrim(candidate_id) = v_cid;
    GET DIAGNOSTICS v_edu = ROW_COUNT;

    -- Family
    DELETE FROM emponb_cand_family WHERE rtrim(candidate_id) = v_cid;
    INSERT INTO emponb_cand_family
        (candidate_id, line_no, member_name, date_birth, gender, relation)
    SELECT candidate_id, line_no, member_name, date_birth, gender, relation
    FROM emponb_cand_self_family
    WHERE rtrim(candidate_id) = v_cid;
    GET DIAGNOSTICS v_fam = ROW_COUNT;

    -- Pay
    DELETE FROM emponb_cand_pay WHERE rtrim(candidate_id) = v_cid;
    INSERT INTO emponb_cand_pay
        (candidate_id, line_no, ad_code, amount, amount_type, frequency, res_formula, amount_calc, upd_paystru, appl_mode)
    SELECT candidate_id, line_no, ad_code, amount, amount_type, frequency, res_formula, amount_calc, upd_paystru, appl_mode
    FROM emponb_cand_self_pay
    WHERE rtrim(candidate_id) = v_cid;
    GET DIAGNOSTICS v_pay = ROW_COUNT;

    RETURN jsonb_build_object(
        'message',
        format('Candidate %s data submitted to the onboarding record: %s experience, %s education, %s family and %s pay row(s) copied.',
               v_cid, v_exp, v_edu, v_fam, v_pay)
    );
END;
$$;
