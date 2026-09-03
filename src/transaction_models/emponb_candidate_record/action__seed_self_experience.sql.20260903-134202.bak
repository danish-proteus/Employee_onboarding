/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_record
event_type: action
function_name: seed_self_experience
form_no: 1
action_name: Seed Self Experience
language: plpgsql
description: Copy the recruiter-entered past experience lines to the candidate self-service form
functional_specification: Seeds the candidate self-service form (EMPONB_CANDIDATE_SELF / EMPONB_CAND_SELF_EXPERIENCE) with the Past Experience lines captured on the recruiter-side candidate record (EMPONB_CAND_EXPERIENCE). A header row in EMPONB_CANDIDATE_SELF is created on demand from the candidate record. The existing self-experience lines are deleted and re-inserted so a resend refreshes rather than duplicates. The seed is skipped entirely once the candidate has taken over the data (STATUS in DataSubmitted, Review, Confirmed, Cancelled) so that candidate-entered data is never overwritten.
business_logic: Copy past experience lines from the candidate record to the candidate self form, refreshing on resend and never overwriting submitted data
*/

CREATE OR REPLACE FUNCTION seed_self_experience(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_candidate_id text := NULLIF(TRIM(p->>'CANDIDATE_ID'), '');
    v_status       text;
    v_count        integer := 0;
    v_edu_count    integer := 0;
    v_fam_count    integer := 0;
    v_pay_count    integer := 0;
BEGIN
    -- Nothing to seed when the action fires before the record carries a key.
    IF v_candidate_id IS NULL THEN
        RETURN jsonb_build_object('status', 'success',
                                  'message', 'No candidate specified; nothing to copy.');
    END IF;

    SELECT c.STATUS
      INTO v_status
      FROM EMPONB_CANDIDATE_RECORD c
     WHERE c.CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'success',
                                  'message', 'No candidate record found; nothing to copy.');
    END IF;

    -- Once the candidate owns the data, never overwrite what they submitted.
    IF TRIM(COALESCE(v_status, '')) IN ('DataSubmitted', 'Review', 'Confirmed', 'Cancelled') THEN
        RETURN jsonb_build_object('status', 'success',
                                  'message', 'Candidate data already submitted; past experience left untouched.');
    END IF;

    -- (1) Ensure the self-service header row exists for this candidate.
    INSERT INTO EMPONB_CANDIDATE_SELF (CANDIDATE_ID, CANDIDATE_NAME, GENDER, DESIGN_CODE, EMAIL_ID, STATUS)
    SELECT c.CANDIDATE_ID, c.CANDIDATE_NAME, c.GENDER, c.DESIGN_CODE, c.EMAIL_ID, c.STATUS
      FROM EMPONB_CANDIDATE_RECORD c
     WHERE c.CANDIDATE_ID = v_candidate_id
       AND NOT EXISTS (SELECT 1
                         FROM EMPONB_CANDIDATE_SELF s
                        WHERE s.CANDIDATE_ID = v_candidate_id);

    -- (2) Refresh (not append) the self-service past experience lines.
    DELETE FROM EMPONB_CAND_SELF_EXPERIENCE
     WHERE CANDIDATE_ID = v_candidate_id;

    INSERT INTO EMPONB_CAND_SELF_EXPERIENCE
           (CANDIDATE_ID, LINE_NO, ORGANISATION, DESIGNATION, FROM_DATE, TO_DATE, GROSS_AMT)
    SELECT e.CANDIDATE_ID, e.LINE_NO, e.ORGANISATION, e.DESIGNATION, e.FROM_DATE, e.TO_DATE, e.GROSS_AMT
      FROM EMPONB_CAND_EXPERIENCE e
     WHERE e.CANDIDATE_ID = v_candidate_id;

    GET DIAGNOSTICS v_count = ROW_COUNT;

    -- (3) Refresh (not append) the self-service education lines.
    DELETE FROM EMPONB_CAND_SELF_EDUCATION
     WHERE CANDIDATE_ID = v_candidate_id;

    INSERT INTO EMPONB_CAND_SELF_EDUCATION
           (CANDIDATE_ID, LINE_NO, QLF_CODE, QLF_TYPE, INSTITUTE, PASS_YEAR, CLASS,
            PERCENTAGE, COUNTRY_CODE, COURSE_TYPE, COURSE_DURATION)
    SELECT ed.CANDIDATE_ID, ed.LINE_NO, ed.QLF_CODE, ed.QLF_TYPE, ed.INSTITUTE, ed.PASS_YEAR, ed.CLASS,
           ed.PERCENTAGE, ed.COUNTRY_CODE, ed.COURSE_TYPE, ed.COURSE_DURATION
      FROM EMPONB_CAND_EDUCATION ed
     WHERE ed.CANDIDATE_ID = v_candidate_id;

    GET DIAGNOSTICS v_edu_count = ROW_COUNT;

    -- (4) Refresh (not append) the self-service family lines.
    DELETE FROM EMPONB_CAND_SELF_FAMILY
     WHERE CANDIDATE_ID = v_candidate_id;

    INSERT INTO EMPONB_CAND_SELF_FAMILY
           (CANDIDATE_ID, LINE_NO, MEMBER_NAME, DATE_BIRTH, GENDER, RELATION)
    SELECT f.CANDIDATE_ID, f.LINE_NO, f.MEMBER_NAME, f.DATE_BIRTH, f.GENDER, f.RELATION
      FROM EMPONB_CAND_FAMILY f
     WHERE f.CANDIDATE_ID = v_candidate_id;

    GET DIAGNOSTICS v_fam_count = ROW_COUNT;

    -- (5) Refresh (not append) the self-service candidate pay lines.
    DELETE FROM EMPONB_CAND_SELF_PAY
     WHERE CANDIDATE_ID = v_candidate_id;

    INSERT INTO EMPONB_CAND_SELF_PAY
           (CANDIDATE_ID, LINE_NO, AD_CODE, AMOUNT, AMOUNT_TYPE, FREQUENCY, RES_FORMULA,
            AMOUNT_CALC, UPD_PAYSTRU, APPL_MODE)
    SELECT pay.CANDIDATE_ID, pay.LINE_NO, pay.AD_CODE, pay.AMOUNT, pay.AMOUNT_TYPE, pay.FREQUENCY, pay.RES_FORMULA,
           pay.AMOUNT_CALC, pay.UPD_PAYSTRU, pay.APPL_MODE
      FROM EMPONB_CAND_PAY pay
     WHERE pay.CANDIDATE_ID = v_candidate_id;

    GET DIAGNOSTICS v_pay_count = ROW_COUNT;

    RETURN jsonb_build_object('status', 'success',
                              'message', v_count || ' experience, ' || v_edu_count || ' education, '
                                         || v_fam_count || ' family and ' || v_pay_count
                                         || ' pay line(s) copied to the candidate form');
END;
$$;
