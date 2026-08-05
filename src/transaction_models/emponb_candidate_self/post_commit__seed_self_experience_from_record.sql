/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: post_commit
function_name: seed_self_experience_from_record
language: plpgsql
description: Seed/refresh Past Experience lines from the HR candidate record
functional_specification: After add/edit of EMPONB_CANDIDATE_SELF for this CANDIDATE_ID: if the record's STATUS is 'Link Generated' or 'Link Accessed', copy every EMPONB_CAND_EXPERIENCE row for this CANDIDATE_ID into EMPONB_CAND_SELF_EXPERIENCE (matched/replaced by LINE_NO) so the candidate sees the HR-captured experience lines pre-filled. The copy is idempotent - re-running it must not create duplicate lines, and once STATUS is 'DataSubmitted', 'Review' or 'Confirmed' the candidate-side rows must be left untouched.
business_logic: Seed/refresh Past Experience lines from the HR candidate record
*/

CREATE OR REPLACE FUNCTION seed_self_experience_from_record(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    -- post_commit receives the whole transaction tree; the header holds this row's values
    v_candidate_id text := COALESCE(p->'header'->>'CANDIDATE_ID', p->>'CANDIDATE_ID');
    v_status       text;
BEGIN
    IF v_candidate_id IS NULL OR btrim(v_candidate_id) = '' THEN
        RETURN NULL;
    END IF;

    -- Read the current status from the HR candidate record
    SELECT STATUS
      INTO v_status
      FROM EMPONB_CANDIDATE_RECORD
     WHERE CANDIDATE_ID = v_candidate_id;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    -- Seed only while the link is generated/accessed. Once the candidate has
    -- started submitting (DataSubmitted/Review/Confirmed) leave their rows alone.
    IF v_status IS NULL OR btrim(v_status) NOT IN ('Link Generated', 'Link Accessed') THEN
        RETURN NULL;
    END IF;

    -- Refresh candidate-side lines that still exist on the HR side (matched by LINE_NO)
    UPDATE EMPONB_CAND_SELF_EXPERIENCE tgt
       SET ORGANISATION = src.ORGANISATION,
           DESIGNATION  = src.DESIGNATION,
           FROM_DATE    = src.FROM_DATE,
           TO_DATE      = src.TO_DATE,
           GROSS_AMT    = src.GROSS_AMT
      FROM EMPONB_CAND_EXPERIENCE src
     WHERE src.CANDIDATE_ID = v_candidate_id
       AND tgt.CANDIDATE_ID = v_candidate_id
       AND tgt.LINE_NO      = src.LINE_NO;

    -- Insert HR lines not yet present on the candidate side (keeps the copy idempotent)
    INSERT INTO EMPONB_CAND_SELF_EXPERIENCE
           (CANDIDATE_ID, LINE_NO, ORGANISATION, DESIGNATION, FROM_DATE, TO_DATE, GROSS_AMT)
    SELECT src.CANDIDATE_ID, src.LINE_NO, src.ORGANISATION, src.DESIGNATION,
           src.FROM_DATE, src.TO_DATE, src.GROSS_AMT
      FROM EMPONB_CAND_EXPERIENCE src
     WHERE src.CANDIDATE_ID = v_candidate_id
       AND NOT EXISTS (
             SELECT 1
               FROM EMPONB_CAND_SELF_EXPERIENCE tgt
              WHERE tgt.CANDIDATE_ID = v_candidate_id
                AND tgt.LINE_NO      = src.LINE_NO
           );

    RETURN NULL;
END;
$$;
