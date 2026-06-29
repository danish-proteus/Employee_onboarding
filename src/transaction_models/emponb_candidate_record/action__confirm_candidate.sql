/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: action
function_name: confirm_candidate
action_name: Confirm
language: plpgsql
description: Confirm and push to IOFLOW Employee
functional_specification: Validate EMP_CODE present and unique, DATE_JOIN present, GROSS>=BASIC. Trigger the IOFLOW Employee-creation API with the consolidated employee payload (personal + finalization + pay structure rows where UPD_PAYSTRU='Y'). Store EMPLOYEE_PUSHED_FLAG='Y' and EMPLOYEE_PUSH_REF from the response. Set STATUS='Confirmed' and stamp STATUS_DATE. Send a notification to the INITIATED_BY HR user. Return a confirmation message.
business_logic: Confirm and push to IOFLOW Employee
*/

CREATE OR REPLACE FUNCTION emponb_candidate_record__confirm_candidate(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id char(10) := p->>'CANDIDATE_ID';
    v_rec          EMPONB_CANDIDATE_RECORD%ROWTYPE;
    v_dup          integer;
    v_base_url     varchar(500);
    v_endpoint     varchar(500);
    v_token        varchar(500);
    v_pay_rows     jsonb;
    v_payload      jsonb;
    v_resp         jsonb;
    v_push_ref     varchar(100);
BEGIN
    IF v_candidate_id IS NULL OR btrim(v_candidate_id) = '' THEN
        RETURN jsonb_build_object('error', 'Candidate id is required.');
    END IF;

    SELECT * INTO v_rec
      FROM EMPONB_CANDIDATE_RECORD
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found.');
    END IF;

    IF v_rec.STATUS = 'Confirmed' OR v_rec.EMPLOYEE_PUSHED_FLAG = 'Y' THEN
        RETURN jsonb_build_object('error', 'Candidate is already confirmed and pushed.');
    END IF;
    IF v_rec.STATUS = 'Cancelled' THEN
        RETURN jsonb_build_object('error', 'A cancelled candidate cannot be confirmed.');
    END IF;

    -- ---- Finalisation validations -------------------------------------------
    IF v_rec.EMP_CODE IS NULL OR btrim(v_rec.EMP_CODE) = '' THEN
        RETURN jsonb_build_object('error', 'Employee code is required before confirmation.');
    END IF;

    -- EMP_CODE must be unique across other candidate records.
    SELECT count(*) INTO v_dup
      FROM EMPONB_CANDIDATE_RECORD
     WHERE EMP_CODE = v_rec.EMP_CODE
       AND CANDIDATE_ID <> v_candidate_id;
    IF v_dup > 0 THEN
        RETURN jsonb_build_object('error', 'Employee code ' || btrim(v_rec.EMP_CODE) || ' is already assigned to another candidate.');
    END IF;

    IF v_rec.DATE_JOIN IS NULL THEN
        RETURN jsonb_build_object('error', 'Date of joining is required before confirmation.');
    END IF;

    IF COALESCE(v_rec.GROSS, 0) < COALESCE(v_rec.BASIC, 0) THEN
        RETURN jsonb_build_object('error', 'Gross salary cannot be less than basic salary.');
    END IF;

    -- ---- IOFLOW configuration ----------------------------------------------
    SELECT IOFLOW_BASE_URL, IOFLOW_EMPLOYEE_ENDPOINT, IOFLOW_AUTH_TOKEN
      INTO v_base_url, v_endpoint, v_token
      FROM EMPONB_ONBOARDING_SETTINGS
     ORDER BY SETTINGS_ID
     LIMIT 1;

    IF v_base_url IS NULL THEN
        RETURN jsonb_build_object('error', 'Onboarding settings are not configured.');
    END IF;

    -- Pay structure rows that should flow into the payroll master.
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'ad_code',     AD_CODE,
                'amount',      AMOUNT,
                'amount_type', AMOUNT_TYPE,
                'frequency',   FREQUENCY,
                'res_formula', RES_FORMULA,
                'amount_calc', AMOUNT_CALC,
                'appl_mode',   APPL_MODE)), '[]'::jsonb)
      INTO v_pay_rows
      FROM EMPONB_CAND_PAY
     WHERE CANDIDATE_ID = v_candidate_id
       AND UPD_PAYSTRU = 'Y';

    -- Consolidated employee payload: personal + finalisation + pay structure.
    v_payload := jsonb_build_object(
        'candidate_id',  v_rec.CANDIDATE_ID,
        'emp_code',      v_rec.EMP_CODE,
        'name_prefix',   v_rec.NAME_PREFIX,
        'first_name',    v_rec.EMP_FNAME,
        'middle_name',   v_rec.EMP_MNAME,
        'last_name',     v_rec.EMP_LNAME,
        'gender',        v_rec.GENDER,
        'birthdate',     v_rec.BIRTHDATE,
        'email_id',      v_rec.EMAIL_ID,
        'email_id_off',  v_rec.EMAIL_ID_OFF,
        'mobile',        v_rec.MOBILE,
        'pan_no',        v_rec.PAN_NO,
        'aadhar_no',     v_rec.AADHAR_NO,
        'bank_account_no', v_rec.BANK_ACCOUNT_NO,
        'bank_ifsc_code',  v_rec.BANK_IFSC_CODE,
        'fin_design_code', v_rec.FIN_DESIGN_CODE,
        'dept_code',     v_rec.DEPT_CODE,
        'grade',         v_rec.GRADE,
        'cadre',         v_rec.CADRE,
        'date_join',     v_rec.DATE_JOIN,
        'work_shift',    v_rec.WORK_SHIFT,
        'hol_tblno',     v_rec.HOL_TBLNO,
        'emp_site',      v_rec.EMP_SITE,
        'pay_site',      v_rec.PAY_SITE,
        'basic',         v_rec.BASIC,
        'gross',         v_rec.GROSS,
        'probation_date', v_rec.PROBATION_DATE,
        'probation_prd', v_rec.PROBATION_PRD,
        'notice_prd',    v_rec.NOTICE_PRD,
        'report_to',     v_rec.REPORT_TO,
        'pay_structure', v_pay_rows
    );

    -- Trigger the IOFLOW Employee-creation API.
    SELECT content::jsonb
      INTO v_resp
      FROM http((
            'POST',
            rtrim(v_base_url, '/') || '/' || ltrim(v_endpoint, '/'),
            ARRAY[http_header('Authorization', 'Bearer ' || v_token)],
            'application/json',
            v_payload::text
        )::http_request);

    v_push_ref := v_resp->>'employee_ref';
    IF v_push_ref IS NULL OR btrim(v_push_ref) = '' THEN
        RETURN jsonb_build_object('error', 'IOFLOW did not return an employee reference; push failed.');
    END IF;

    UPDATE EMPONB_CANDIDATE_RECORD
       SET EMPLOYEE_PUSHED_FLAG = 'Y',
           EMPLOYEE_PUSH_REF    = v_push_ref,
           STATUS               = 'Confirmed',
           STATUS_DATE          = now()
     WHERE CANDIDATE_ID = v_candidate_id;

    -- Notify the initiating HR user.
    PERFORM pg_notify('emponb_notify', jsonb_build_object(
        'type', 'candidate_confirmed',
        'candidate_id', v_candidate_id,
        'emp_code', btrim(v_rec.EMP_CODE),
        'employee_ref', v_push_ref,
        'hr_user', v_rec.INITIATED_BY
    )::text);

    RETURN jsonb_build_object('prompts',
             jsonb_build_array(jsonb_build_object(
                 'code', 'CONF01', 'type', 'P',
                 'message', 'Candidate confirmed and pushed to IOFLOW (ref ' || v_push_ref || ').')));
END;
$$;
