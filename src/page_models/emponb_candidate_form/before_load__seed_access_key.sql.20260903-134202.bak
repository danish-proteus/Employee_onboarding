/*
project: Employee_onboarding
object_type: S
object_name: emponb_candidate_form
event_type: before_load
function_name: seed_access_key
language: plpgsql
description: Read the onboarding key from the URL and pre-populate the form with the candidate's on-file details for that key
functional_specification: On page load, read the candidate key from the URL params
  (accept either ?key= or ?access_key=), trim it, and always return it via set_vars
  as access_key so the key-validation gate and API loaders can run. Access is never
  denied here (allowed is always true); key validity, expiry and already-submitted
  checks are handled by the client-side validate-key API gate. When a non-empty key
  matches a single emponb_candidate_record row (by ACCESS_KEY), that candidate's
  identity and on-file onboarding details are additionally returned via set_vars,
  mapped to the form input variables (lowercased column names), so the form is
  pre-filled with whatever has already been captured for this candidate_id. NULL
  columns are omitted so they never overwrite a page value; dates are ISO strings.
business_logic: Seed access_key from the URL and pre-fill the form from the candidate record
*/

CREATE OR REPLACE FUNCTION emponb_candidate_form_seed_access_key(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_params jsonb := COALESCE(p->'url_params', '{}'::jsonb);
    v_key    text;
    r        emponb_candidate_record%ROWTYPE;
    v_vars   jsonb;
    v_exp    jsonb;
    v_edu    jsonb;
    v_fam    jsonb;
    v_pay    jsonb;
BEGIN
    -- Accept either ?key= or ?access_key= on the emailed onboarding link.
    v_key := btrim(COALESCE(v_params->>'key', v_params->>'access_key', ''));

    -- No key on the URL: surface an empty access_key and let the gate handle it.
    IF v_key = '' THEN
        RETURN jsonb_build_object(
            'allowed', true,
            'set_vars', jsonb_build_object('access_key', '')
        );
    END IF;

    -- Look up the candidate this key belongs to. Validity/expiry/already-submitted
    -- are enforced by the validate-key API gate; here we only pre-fill details.
    SELECT * INTO r
    FROM emponb_candidate_record
    WHERE ACCESS_KEY = v_key
    LIMIT 1;

    IF NOT FOUND THEN
        -- Unknown key: still allow render; the validate-key gate shows the callout.
        RETURN jsonb_build_object(
            'allowed', true,
            'set_vars', jsonb_build_object('access_key', v_key)
        );
    END IF;

    -- Candidate row found: also pull this candidate's detail rows so the page's
    -- detail tables can render them. Each array carries the columns shown by the
    -- corresponding page table, in table-column order; empty array when no rows.
    -- CHAR(n) code columns are rtrim()'d so trailing pad-spaces don't break the
    -- select/lookup display; dates are ISO strings. Order by LINE_NO for stable rows.

    -- Past Experience (form_no 2 -> EMPONB_CAND_EXPERIENCE)
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'line_no',      x.LINE_NO,
        'organisation', x.ORGANISATION,
        'designation',  x.DESIGNATION,
        'from_date',    to_char(x.FROM_DATE, 'YYYY-MM-DD'),
        'to_date',      to_char(x.TO_DATE, 'YYYY-MM-DD'),
        'gross_amt',    x.GROSS_AMT
    ) ORDER BY x.LINE_NO), '[]'::jsonb)
    INTO v_exp
    FROM emponb_cand_experience x
    WHERE x.CANDIDATE_ID = r.CANDIDATE_ID;

    -- Education (form_no 3 -> EMPONB_CAND_EDUCATION)
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'line_no',         x.LINE_NO,
        'qlf_code',        NULLIF(rtrim(x.QLF_CODE), ''),
        'qlf_type',        x.QLF_TYPE,
        'institute',       x.INSTITUTE,
        'pass_year',       x.PASS_YEAR,
        'class',           x.CLASS,
        'percentage',      x.PERCENTAGE,
        'country_code',    NULLIF(rtrim(x.COUNTRY_CODE), ''),
        'course_type',     x.COURSE_TYPE,
        'course_duration', x.COURSE_DURATION
    ) ORDER BY x.LINE_NO), '[]'::jsonb)
    INTO v_edu
    FROM emponb_cand_education x
    WHERE x.CANDIDATE_ID = r.CANDIDATE_ID;

    -- Family (form_no 4 -> EMPONB_CAND_FAMILY)
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'line_no',     x.LINE_NO,
        'member_name', x.MEMBER_NAME,
        'date_birth',  to_char(x.DATE_BIRTH, 'YYYY-MM-DD'),
        'gender',      NULLIF(rtrim(x.GENDER), ''),
        'relation',    NULLIF(rtrim(x.RELATION), '')
    ) ORDER BY x.LINE_NO), '[]'::jsonb)
    INTO v_fam
    FROM emponb_cand_family x
    WHERE x.CANDIDATE_ID = r.CANDIDATE_ID;

    -- Candidate Pay (form_no 5 -> EMPONB_CAND_PAY)
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'line_no',     x.LINE_NO,
        'ad_code',     NULLIF(rtrim(x.AD_CODE), ''),
        'amount',      x.AMOUNT,
        'amount_type', x.AMOUNT_TYPE,
        'frequency',   x.FREQUENCY,
        'res_formula', x.RES_FORMULA,
        'amount_calc', x.AMOUNT_CALC,
        'upd_paystru', NULLIF(rtrim(x.UPD_PAYSTRU), ''),
        'appl_mode',   x.APPL_MODE
    ) ORDER BY x.LINE_NO), '[]'::jsonb)
    INTO v_pay
    FROM emponb_cand_pay x
    WHERE x.CANDIDATE_ID = r.CANDIDATE_ID;

    -- Build the pre-fill payload, dropping NULLs so they never overwrite a value,
    -- then guarantee access_key is always present.
    -- rtrim() the CHAR(n) columns so trailing pad-spaces don't break select
    -- matching (e.g. name_prefix) or get pushed back on submit; NULLIF keeps
    -- blank CHAR columns as NULL so jsonb_strip_nulls drops them.
    v_vars := jsonb_strip_nulls(jsonb_build_object(
        'candidate_id',          NULLIF(rtrim(r.CANDIDATE_ID), ''),
        'candidate_name',        r.CANDIDATE_NAME,
        'name_prefix',           NULLIF(rtrim(r.NAME_PREFIX), ''),
        'emp_fname',             r.EMP_FNAME,
        'emp_mname',             r.EMP_MNAME,
        'emp_lname',             r.EMP_LNAME,
        'gender',                NULLIF(rtrim(r.GENDER), ''),
        'birthdate',             to_char(r.BIRTHDATE, 'YYYY-MM-DD'),
        'nationality',           r.NATIONALITY,
        'marital_status',        r.MARITAL_STATUS,
        'marriage_anniversary',  to_char(r.MARRIAGE_ANNIVERSARY, 'YYYY-MM-DD'),
        'blood_group',           r.BLOOD_GROUP,
        'religion',              r.RELIGION,
        'cast_category',         r.CAST_CATEGORY,
        'mother_tongue',         r.MOTHER_TONGUE,
        'physical_handicap',     NULLIF(rtrim(r.PHYSICAL_HANDICAP), ''),
        'hobby1',                r.HOBBY1,
        'hobby2',                r.HOBBY2,
        'total_experience',      r.TOTAL_EXPERIENCE,
        'current_address',       r.CURRENT_ADDRESS,
        'current_pin',           NULLIF(rtrim(r.CURRENT_PIN), ''),
        'current_city',          r.CURRENT_CITY,
        'current_state',         r.CURRENT_STATE,
        'permanent_address',     r.PERMANENT_ADDRESS,
        'permanent_pin',         NULLIF(rtrim(r.PERMANENT_PIN), ''),
        'permanent_city',        r.PERMANENT_CITY,
        'permanent_state',       r.PERMANENT_STATE,
        'mobile',                NULLIF(rtrim(r.MOBILE), ''),
        'alternate_telephone',   r.ALTERNATE_TELEPHONE,
        'contact_person',        r.CONTACT_PERSON,
        'contact_person_mobile', NULLIF(rtrim(r.CONTACT_PERSON_MOBILE), ''),
        'contact_person_email',  r.CONTACT_PERSON_EMAIL,
        'pan_no',                NULLIF(rtrim(r.PAN_NO), ''),
        'aadhar_no',             NULLIF(rtrim(r.AADHAR_NO), ''),
        'passport_no',           r.PASSPORT_NO,
        'driving_lic_no',        r.DRIVING_LIC_NO,
        'pf_no',                 r.PF_NO,
        'esic_no',               r.ESIC_NO,
        'bank_account_no',       r.BANK_ACCOUNT_NO,
        'bank_ifsc_code',        NULLIF(rtrim(r.BANK_IFSC_CODE), ''),
        'bank_name',             r.BANK_NAME
    ));

    -- access_key must always be present, even if every other field was NULL.
    -- Detail arrays are always emitted (each empty [] when the candidate has no
    -- rows in that table) so the page's detail tables render deterministically.
    v_vars := v_vars || jsonb_build_object(
        'access_key', v_key,
        'exp_rows',   COALESCE(v_exp, '[]'::jsonb),
        'edu_rows',   COALESCE(v_edu, '[]'::jsonb),
        'fam_rows',   COALESCE(v_fam, '[]'::jsonb),
        'pay_rows',   COALESCE(v_pay, '[]'::jsonb)
    );

    RETURN jsonb_build_object(
        'allowed', true,
        'set_vars', v_vars
    );
END;
$$;
