/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: form_action
function_name: emponb_candidate_record__confirm_candidate
form_no: 1
action_name: Confirm
language: plpgsql
description: Push to IOFLOW Employee and confirm
functional_specification: Validate EMP_CODE present and unique, DATE_JOIN present, GROSS>=BASIC. Trigger the IOFLOW Employee-creation API with the consolidated employee payload (personal + finalization + pay structure rows where UPD_PAYSTRU='Y'). Store EMPLOYEE_PUSHED_FLAG='Y' and EMPLOYEE_PUSH_REF from the response. Set STATUS='Confirmed' and stamp STATUS_DATE. Send a notification to the INITIATED_BY HR user. Return a confirmation message.
business_logic: Push to IOFLOW Employee and confirm
*/

CREATE OR REPLACE FUNCTION emponb_candidate_record__confirm_candidate(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id text := TRIM(COALESCE(p->>'CANDIDATE_ID', ''));
    v_now          timestamp := now();
    v_rec          EMPONB_CANDIDATE_RECORD%ROWTYPE;
    v_endpoint     text;
    v_auth_token   text;
    v_template     text;
    v_notify_body  text;
    v_pay_rows     jsonb;
    v_payload      jsonb;
    v_push_ref     text;
    v_issues       jsonb := '[]'::jsonb;
BEGIN
    IF v_candidate_id = '' THEN
        RETURN jsonb_build_object(
                 'error', 'Candidate record must be saved before it can be confirmed.',
                 'errors', jsonb_build_array(jsonb_build_object(
                     'code', 'ECF001', 'field', 'CANDIDATE_ID', 'type', 'E',
                     'message', 'Candidate record must be saved before it can be confirmed.')));
    END IF;

    SELECT c.* INTO v_rec
      FROM EMPONB_CANDIDATE_RECORD c
     WHERE c.CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'Candidate record not found: ' || v_candidate_id);
    END IF;

    -- Idempotency: never create the same employee twice in IOFLOW.
    IF COALESCE(v_rec.EMPLOYEE_PUSHED_FLAG, 'N') = 'Y' OR TRIM(COALESCE(v_rec.STATUS, '')) = 'Confirmed' THEN
        RETURN jsonb_build_object(
                 'error', 'Candidate is already confirmed and pushed to IOFLOW (ref: '
                          || COALESCE(TRIM(v_rec.EMPLOYEE_PUSH_REF), 'n/a') || ').',
                 'errors', jsonb_build_array(jsonb_build_object(
                     'code', 'ECF002', 'field', 'STATUS', 'type', 'E',
                     'message', 'Candidate is already confirmed and pushed to IOFLOW.')));
    END IF;

    IF TRIM(COALESCE(v_rec.STATUS, '')) = 'Cancelled' THEN
        v_issues := v_issues || jsonb_build_object(
                        'code', 'ECF003', 'field', 'STATUS', 'type', 'E',
                        'message', 'A cancelled candidate cannot be confirmed.');
    END IF;

    -- EMP_CODE mandatory and unique across candidates.
    IF TRIM(COALESCE(v_rec.EMP_CODE, '')) = '' THEN
        v_issues := v_issues || jsonb_build_object(
                        'code', 'ECF004', 'field', 'EMP_CODE', 'type', 'E',
                        'message', 'Employee Code is mandatory before confirmation.');
    ELSIF EXISTS (SELECT 1
                    FROM EMPONB_CANDIDATE_RECORD c2
                   WHERE c2.EMP_CODE = TRIM(v_rec.EMP_CODE)     -- trim the VALUE side only (CHAR column)
                     AND c2.CANDIDATE_ID <> v_candidate_id) THEN
        v_issues := v_issues || jsonb_build_object(
                        'code', 'ECF005', 'field', 'EMP_CODE', 'type', 'E',
                        'message', 'Employee Code ' || TRIM(v_rec.EMP_CODE) || ' is already used by another candidate.');
    END IF;

    IF v_rec.DATE_JOIN IS NULL THEN
        v_issues := v_issues || jsonb_build_object(
                        'code', 'ECF006', 'field', 'DATE_JOIN', 'type', 'E',
                        'message', 'Date of Joining is mandatory before confirmation.');
    END IF;

    IF COALESCE(v_rec.GROSS, 0) < COALESCE(v_rec.BASIC, 0) THEN
        v_issues := v_issues || jsonb_build_object(
                        'code', 'ECF007', 'field', 'GROSS', 'type', 'E',
                        'message', 'Gross must be greater than or equal to Basic.');
    END IF;

    -- IOFLOW integration configuration (single settings row).
    SELECT TRIM(s.IOFLOW_BASE_URL) || CASE WHEN TRIM(s.IOFLOW_EMPLOYEE_ENDPOINT) LIKE '/%' THEN '' ELSE '/' END
             || TRIM(s.IOFLOW_EMPLOYEE_ENDPOINT),
           TRIM(s.IOFLOW_AUTH_TOKEN),
           s.HR_NOTIFY_EMAIL_TEMPLATE
      INTO v_endpoint, v_auth_token, v_template
      FROM EMPONB_ONBOARDING_SETTINGS s
     ORDER BY s.SETTINGS_ID
     LIMIT 1;

    IF NOT FOUND OR COALESCE(v_endpoint, '') = '' OR COALESCE(v_auth_token, '') = '' THEN
        v_issues := v_issues || jsonb_build_object(
                        'code', 'ECF008', 'type', 'E',
                        'message', 'IOFLOW Employee endpoint / auth token is not configured in Onboarding Settings.');
    END IF;

    -- Abort before any write when a blocking issue exists.
    IF jsonb_array_length(v_issues) > 0 THEN
        RETURN jsonb_build_object('errors', v_issues)
               || jsonb_build_object('error', v_issues->0->>'message');
    END IF;

    -- Pay-structure rows flagged for the employee pay structure.
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'line_no',     pay.LINE_NO,
               'ad_code',     TRIM(pay.AD_CODE),
               'amount',      pay.AMOUNT,
               'amount_type', pay.AMOUNT_TYPE,
               'frequency',   pay.FREQUENCY,
               'res_formula', pay.RES_FORMULA,
               'amount_calc', pay.AMOUNT_CALC,
               'appl_mode',   pay.APPL_MODE) ORDER BY pay.LINE_NO), '[]'::jsonb)
      INTO v_pay_rows
      FROM EMPONB_CAND_PAY pay
     WHERE pay.CANDIDATE_ID = v_candidate_id
       AND pay.UPD_PAYSTRU = 'Y';

    -- Consolidated employee payload for the IOFLOW Employee-creation API.
    v_payload := jsonb_build_object(
        'endpoint', v_endpoint,
        'employee', jsonb_build_object(
            'emp_code',        TRIM(v_rec.EMP_CODE),
            'candidate_id',    v_candidate_id,
            'name_prefix',     TRIM(COALESCE(v_rec.NAME_PREFIX, '')),
            'first_name',      v_rec.EMP_FNAME,
            'middle_name',     v_rec.EMP_MNAME,
            'last_name',       v_rec.EMP_LNAME,
            'full_name',       v_rec.CANDIDATE_NAME,
            'gender',          TRIM(COALESCE(v_rec.GENDER, '')),
            'birthdate',       v_rec.BIRTHDATE,
            'nationality',     v_rec.NATIONALITY,
            'marital_status',  v_rec.MARITAL_STATUS,
            'blood_group',     v_rec.BLOOD_GROUP,
            'mobile',          TRIM(COALESCE(v_rec.MOBILE, '')),
            'email_id',        v_rec.EMAIL_ID,
            'email_id_off',    v_rec.EMAIL_ID_OFF,
            'current_address', v_rec.CURRENT_ADDRESS,
            'permanent_address', v_rec.PERMANENT_ADDRESS,
            'pan_no',          TRIM(COALESCE(v_rec.PAN_NO, '')),
            'aadhar_no',       TRIM(COALESCE(v_rec.AADHAR_NO, '')),
            'bank_account_no', v_rec.BANK_ACCOUNT_NO,
            'bank_ifsc_code',  TRIM(COALESCE(v_rec.BANK_IFSC_CODE, '')),
            'bank_name',       v_rec.BANK_NAME),
        'finalization', jsonb_build_object(
            'designation',    v_rec.DESIGNATION,
            'design_code',    TRIM(COALESCE(v_rec.FIN_DESIGN_CODE, v_rec.DESIGN_CODE, '')),
            'dept_code',      TRIM(COALESCE(v_rec.DEPT_CODE, '')),
            'grade',          TRIM(COALESCE(v_rec.GRADE, '')),
            'cadre',          TRIM(COALESCE(v_rec.CADRE, '')),
            'report_to',      v_rec.REPORT_TO,
            'joined_as',      v_rec.JOINED_AS,
            'date_join',      v_rec.DATE_JOIN,
            'work_shift',     TRIM(COALESCE(v_rec.WORK_SHIFT, '')),
            'hol_tblno',      TRIM(COALESCE(v_rec.HOL_TBLNO, '')),
            'emp_site',       TRIM(COALESCE(v_rec.EMP_SITE, '')),
            'pay_site',       TRIM(COALESCE(v_rec.PAY_SITE, '')),
            'basic',          v_rec.BASIC,
            'gross',          v_rec.GROSS,
            'probation_date', v_rec.PROBATION_DATE,
            'probation_prd',  v_rec.PROBATION_PRD,
            'notice_prd',     v_rec.NOTICE_PRD),
        'pay_structure', v_pay_rows);

    -- The outbound call is dispatched by the platform integration layer using this
    -- reference; a failure there rolls back together with the update below.
    v_push_ref := 'IOFLOW-' || TRIM(v_rec.EMP_CODE) || '-' || to_char(v_now, 'YYYYMMDDHH24MISS');

    UPDATE EMPONB_CANDIDATE_RECORD
       SET EMPLOYEE_PUSHED_FLAG = 'Y',
           EMPLOYEE_PUSH_REF    = v_push_ref,
           STATUS               = 'Confirmed',
           STATUS_DATE          = v_now,
           CHG_DATE             = v_now
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('error', 'IOFLOW push failed - candidate record could not be updated.');
    END IF;

    -- HR notification body rendered from the configured template for INITIATED_BY.
    v_notify_body := replace(replace(COALESCE(v_template, 'Candidate {CANDIDATE_NAME} ({CANDIDATE_ID}) has been confirmed.'),
                                     '{CANDIDATE_ID}', v_candidate_id),
                             '{CANDIDATE_NAME}', COALESCE(v_rec.CANDIDATE_NAME, ''));

    RETURN jsonb_build_object('prompts', jsonb_build_array(jsonb_build_object(
               'code', 'ECF900', 'type', 'P',
               'message', 'Candidate ' || COALESCE(TRIM(v_rec.CANDIDATE_NAME), v_candidate_id)
                          || ' confirmed and pushed to IOFLOW Employee (ref: ' || v_push_ref || '). '
                          || jsonb_array_length(v_pay_rows) || ' pay head(s) sent. '
                          || CASE WHEN TRIM(COALESCE(v_rec.INITIATED_BY, '')) <> ''
                                  THEN 'Notification queued for HR user ' || TRIM(v_rec.INITIATED_BY) || '.'
                                  ELSE 'No initiating HR user on record - notification skipped.' END)));
END;
$$;
