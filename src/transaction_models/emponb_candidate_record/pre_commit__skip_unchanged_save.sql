-- =====================================================================
-- pre_commit : skip_unchanged_save
-- Transaction : emponb_candidate_record
--
-- Blocks the save when the submitted transaction is byte-for-byte
-- equivalent (business-wise) to what is already stored.
--
--   1. New record (no stored EMPONB_CANDIDATE_RECORD row for the
--      submitted CANDIDATE_ID)  -> allow the save (no messages).
--   2. Existing record          -> compare the header row and all four
--      detail forms against their stored rows:
--         form 2 -> EMPONB_CAND_EXPERIENCE  (Past Experience)
--         form 3 -> EMPONB_CAND_EDUCATION   (Educational Qualification)
--         form 4 -> EMPONB_CAND_FAMILY      (Family)
--         form 5 -> EMPONB_CAND_PAY         (Candidate Pay)
--      each keyed by CANDIDATE_ID + LINE_NO.
--   3. Nothing differs          -> blocking message NO_CHANGES_TO_SAVE.
--   4. Something differs        -> empty message list, save proceeds.
--
-- Comparison rules:
--   * NULL and empty string are treated as equal
--   * trailing spaces trimmed (CHAR columns are blank padded)
--   * numbers compared by value (1 = 1.00)
--   * dates/timestamps compared by value, not by string format
--   * system / audit maintained columns are excluded so that a save is
--     never considered "changed" only because of a stamp
-- =====================================================================
CREATE OR REPLACE FUNCTION skip_unchanged_save(p jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    -- columns maintained by the system / audit trail - never compared
    c_excluded    text[] := ARRAY[
                        'STATUS_DATE',
                        'ADD_DATE', 'ADD_USER', 'ADD_TERM',
                        'CHG_DATE', 'CHG_USER', 'CHG_TERM'
                    ];

    v_cand_id     text;
    v_exists      boolean;
    v_changed     boolean := false;

    v_hdr         jsonb;          -- submitted header, keys upper-cased
    v_stored_hdr  jsonb;          -- stored  header, keys upper-cased

    v_key         text;
    v_new_val     text;
    v_old_val     text;

    -- detail form driver
    v_form        text;
    v_table       text;
    v_stored_det  jsonb;          -- { "<line_no>" : {row}, ... }
    v_sub_rows    jsonb;          -- submitted rows for the form
    v_sub_row     jsonb;
    v_old_row     jsonb;
    v_line        text;
    v_sub_count   int;
BEGIN
    v_cand_id := NULLIF(btrim(COALESCE(p->'header'->>'CANDIDATE_ID',
                                       p->'header'->>'candidate_id', '')), '');

    -- ---------------------------------------------------------------
    -- (1) No key yet, or an explicit insert -> brand new record, allow
    -- ---------------------------------------------------------------
    IF v_cand_id IS NULL OR lower(COALESCE(p->>'action', '')) IN ('insert', 'add', 'new') THEN
        RETURN jsonb_build_object('errors', '[]'::jsonb);
    END IF;

    SELECT EXISTS (SELECT 1
                     FROM EMPONB_CANDIDATE_RECORD
                    WHERE CANDIDATE_ID = v_cand_id)
      INTO v_exists;

    IF NOT v_exists THEN
        -- nothing stored for this candidate: it is a new record
        RETURN jsonb_build_object('errors', '[]'::jsonb);
    END IF;

    -- ---------------------------------------------------------------
    -- (2a) Header comparison
    -- ---------------------------------------------------------------
    -- Normalise submitted header keys to upper case so that the payload
    -- casing (candidate_id / CANDIDATE_ID) does not matter.
    SELECT COALESCE(jsonb_object_agg(upper(e.key), e.value), '{}'::jsonb)
      INTO v_hdr
      FROM jsonb_each(COALESCE(p->'header', '{}'::jsonb)) AS e(key, value)
     WHERE left(e.key, 1) <> '_';

    SELECT COALESCE(jsonb_object_agg(upper(e.key), e.value), '{}'::jsonb)
      INTO v_stored_hdr
      FROM EMPONB_CANDIDATE_RECORD r
      CROSS JOIN LATERAL jsonb_each(to_jsonb(r)) AS e(key, value)
     WHERE r.CANDIDATE_ID = v_cand_id;

    FOR v_key IN SELECT jsonb_object_keys(v_hdr)
    LOOP
        CONTINUE WHEN v_key = ANY (c_excluded);
        -- keys that are not real columns of the main table (e.g. the
        -- DESIGNATION_NAME lookup echo) are simply not comparable
        CONTINUE WHEN NOT (v_stored_hdr ? v_key);

        v_new_val := btrim(COALESCE(v_hdr->>v_key, ''));
        v_old_val := btrim(COALESCE(v_stored_hdr->>v_key, ''));

        CONTINUE WHEN v_new_val = v_old_val;          -- NULL = '' handled by COALESCE
        CONTINUE WHEN v_new_val = '' AND v_old_val = '';

        -- same number written differently (1 vs 1.00)
        IF v_new_val <> '' AND v_old_val <> '' THEN
            BEGIN
                CONTINUE WHEN v_new_val::numeric = v_old_val::numeric;
            EXCEPTION WHEN others THEN
                NULL;                                  -- not numeric, fall through
            END;

            -- same instant / same day written in a different format
            BEGIN
                CONTINUE WHEN v_new_val::timestamp = v_old_val::timestamp;
                CONTINUE WHEN v_new_val::timestamp::date = v_old_val::timestamp::date;
            EXCEPTION WHEN others THEN
                NULL;                                  -- not a date, fall through
            END;
        END IF;

        v_changed := true;
        EXIT;
    END LOOP;

    -- ---------------------------------------------------------------
    -- (2b) Detail form comparison - one pass per form
    -- ---------------------------------------------------------------
    IF NOT v_changed THEN
        FOREACH v_form IN ARRAY ARRAY['2', '3', '4', '5']
        LOOP
            v_table := CASE v_form
                           WHEN '2' THEN 'emponb_cand_experience'
                           WHEN '3' THEN 'emponb_cand_education'
                           WHEN '4' THEN 'emponb_cand_family'
                           WHEN '5' THEN 'emponb_cand_pay'
                       END;

            -- stored rows of this form, keyed by LINE_NO, keys upper-cased
            EXECUTE format(
                'SELECT COALESCE(jsonb_object_agg(x.lk, x.row_obj), ''{}''::jsonb)
                   FROM (SELECT d.line_no::text AS lk,
                                (SELECT jsonb_object_agg(upper(e.key), e.value)
                                   FROM jsonb_each(to_jsonb(d)) AS e(key, value)) AS row_obj
                           FROM %I d
                          WHERE d.candidate_id = $1) x',
                v_table)
              INTO v_stored_det
             USING v_cand_id;

            v_sub_rows := COALESCE(p->'details'->v_form, '[]'::jsonb);
            IF jsonb_typeof(v_sub_rows) <> 'array' THEN
                v_sub_rows := '[]'::jsonb;
            END IF;

            -- a removed line (or an added one) changes the row count
            v_sub_count := jsonb_array_length(v_sub_rows);
            IF v_sub_count <> (SELECT count(*) FROM jsonb_object_keys(v_stored_det)) THEN
                v_changed := true;
                EXIT;
            END IF;

            FOR v_sub_row IN SELECT jsonb_array_elements(v_sub_rows)
            LOOP
                -- upper-case the submitted row keys, drop internal markers
                SELECT COALESCE(jsonb_object_agg(upper(e.key), e.value), '{}'::jsonb)
                  INTO v_sub_row
                  FROM jsonb_each(v_sub_row) AS e(key, value)
                 WHERE left(e.key, 1) <> '_';

                v_line := NULLIF(btrim(COALESCE(v_sub_row->>'LINE_NO', '')), '');

                -- a line without a key, or with a key that is not stored,
                -- is an added line
                IF v_line IS NULL OR NOT (v_stored_det ? v_line) THEN
                    v_changed := true;
                    EXIT;
                END IF;

                v_old_row := v_stored_det->v_line;

                FOR v_key IN SELECT jsonb_object_keys(v_sub_row)
                LOOP
                    CONTINUE WHEN v_key = ANY (c_excluded);
                    CONTINUE WHEN NOT (v_old_row ? v_key);

                    v_new_val := btrim(COALESCE(v_sub_row->>v_key, ''));
                    v_old_val := btrim(COALESCE(v_old_row->>v_key, ''));

                    CONTINUE WHEN v_new_val = v_old_val;

                    IF v_new_val <> '' AND v_old_val <> '' THEN
                        BEGIN
                            CONTINUE WHEN v_new_val::numeric = v_old_val::numeric;
                        EXCEPTION WHEN others THEN
                            NULL;
                        END;

                        BEGIN
                            CONTINUE WHEN v_new_val::timestamp = v_old_val::timestamp;
                            CONTINUE WHEN v_new_val::timestamp::date = v_old_val::timestamp::date;
                        EXCEPTION WHEN others THEN
                            NULL;
                        END;
                    END IF;

                    v_changed := true;
                    EXIT;
                END LOOP;

                EXIT WHEN v_changed;
            END LOOP;

            EXIT WHEN v_changed;
        END LOOP;
    END IF;

    -- ---------------------------------------------------------------
    -- (3) Nothing changed anywhere -> block the save
    -- ---------------------------------------------------------------
    IF NOT v_changed THEN
        RETURN jsonb_build_object(
            'error', 'No changes have been made — there is nothing to save.',
            'errors', jsonb_build_array(
                jsonb_build_object(
                    'code',    'NO_CHANGES_TO_SAVE',
                    'field',   NULL,
                    'type',    'E',
                    'message', 'No changes have been made — there is nothing to save.'
                )
            )
        );
    END IF;

    -- ---------------------------------------------------------------
    -- (4) Something changed -> let the save go through
    -- ---------------------------------------------------------------
    RETURN jsonb_build_object('errors', '[]'::jsonb);
END;
$$;
