/*
project: Employee_onboarding
object_type: T
object_name: emponb_candidate_self
event_type: field_item_change
function_name: load_candidate_header
form_no: 1
field_name: candidate_id
language: plpgsql
description: When candidate_id is entered, prefer the candidate self record: if a row exists in EMPONB_CANDIDATE_SELF for that id, fill every header field from EMPONB_CANDIDATE_SELF; otherwise fall back to EMPONB_CANDIDATE_RECORD. Clear the header fields if neither has the id.
business_logic: When candidate_id is entered, prefer the candidate self record: if a row exists in EMPONB_CANDIDATE_SELF for that id, fill every header field from EMPONB_CANDIDATE_SELF; otherwise fall back to EMPONB_CANDIDATE_RECORD. Clear the header fields if neither has the id.
*/

CREATE OR REPLACE FUNCTION load_candidate_header(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    v_candidate_id CHAR(10);
    v_rec          RECORD;
BEGIN
    -- The candidate id just entered on the header
    v_candidate_id := NULLIF(TRIM(p->>'CANDIDATE_ID'), '');

    -- Nothing to look up: clear the header fields
    IF v_candidate_id IS NULL THEN
        RETURN jsonb_build_object(
            'updates',
            jsonb_build_object(
                'CANDIDATE_NAME', NULL,
                'GENDER',         NULL,
                'DESIGN_CODE',    NULL,
                'EMAIL_ID',       NULL,
                'STATUS',         NULL
            )
        );
    END IF;

    -- Prefer the candidate self record: compare the PK column directly (sargable)
    SELECT s.CANDIDATE_NAME, s.GENDER, s.DESIGN_CODE, s.EMAIL_ID, s.STATUS
      INTO v_rec
      FROM EMPONB_CANDIDATE_SELF s
     WHERE s.CANDIDATE_ID = v_candidate_id;

    -- Fall back to the master candidate record when no self row exists
    IF NOT FOUND THEN
        SELECT r.CANDIDATE_NAME, r.GENDER, r.DESIGN_CODE, r.EMAIL_ID, r.STATUS
          INTO v_rec
          FROM EMPONB_CANDIDATE_RECORD r
         WHERE r.CANDIDATE_ID = v_candidate_id;
    END IF;

    -- Neither table has the id: clear the header fields
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'updates',
            jsonb_build_object(
                'CANDIDATE_ID',   v_candidate_id,
                'CANDIDATE_NAME', NULL,
                'GENDER',         NULL,
                'DESIGN_CODE',    NULL,
                'EMAIL_ID',       NULL,
                'STATUS',         NULL
            )
        );
    END IF;

    -- Populate the header fields from whichever source matched
    RETURN jsonb_build_object(
        'updates',
        jsonb_build_object(
            'CANDIDATE_ID',   v_candidate_id,
            'CANDIDATE_NAME', v_rec.CANDIDATE_NAME,
            'GENDER',         v_rec.GENDER,
            'DESIGN_CODE',    v_rec.DESIGN_CODE,
            'EMAIL_ID',       v_rec.EMAIL_ID,
            'STATUS',         v_rec.STATUS
        )
    );
END;
$$;
