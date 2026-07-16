/*
project: Employee_onboarding
object_type: S
object_name: candidate_page
event_type: before_load
function_name: validate_access_key
language: plpgsql
description: Gate the candidate onboarding page on a valid, active, unexpired access key that matches the candidate record
functional_specification: On page load, read the access key from the URL params
  (accept either ?key= or ?access_key=), trim it, and read the candidate_id from
  the page vars/inputs/url_params. If either the key or the candidate_id is missing,
  access is denied with a "missing access key" message. Otherwise the candidate row
  is looked up by CANDIDATE_ID; a missing row denies with "Invalid onboarding link".
  The stored ACCESS_KEY must match the URL key, KEY_VALID_FLAG must be 'Y', and
  KEY_EXPIRY_DATETIME (when set) must not be in the past — each failing check returns
  allowed=false with a specific message. On success, allowed=true and the trimmed
  key is echoed back via set_vars as access_key.
business_logic: Validate the URL access key against the candidate record before rendering the page
*/

CREATE OR REPLACE FUNCTION candidate_page_validate_access_key(p jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
    v_key          text;
    v_candidate_id text;
    r              emponb_candidate_record%ROWTYPE;
BEGIN
    -- Accept either ?key= or ?access_key= on the emailed onboarding link.
    v_key := btrim(COALESCE(p->'url_params'->>'key', p->'url_params'->>'access_key', ''));

    -- Candidate id may arrive via page vars, form inputs, or the URL.
    v_candidate_id := btrim(COALESCE(p->'vars'->>'candidate_id', p->'inputs'->>'candidate_id', p->'url_params'->>'candidate_id', ''));

    -- Nothing to validate against: treat as a broken/incomplete link.
    IF v_key = '' OR v_candidate_id = '' THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'message', 'Onboarding link is missing its access key.'
        );
    END IF;

    -- Look up the candidate this link belongs to. Compare the value side only so
    -- the CANDIDATE_ID primary key stays index-friendly.
    SELECT ACCESS_KEY, KEY_VALID_FLAG, KEY_EXPIRY_DATETIME
    INTO r.ACCESS_KEY, r.KEY_VALID_FLAG, r.KEY_EXPIRY_DATETIME
    FROM emponb_candidate_record
    WHERE rtrim(CANDIDATE_ID) = v_candidate_id
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'message', 'Invalid onboarding link.'
        );
    END IF;

    -- The key in the URL must match the one on file for this candidate.
    IF v_key <> r.ACCESS_KEY THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'message', 'The access key in this link does not match our records.'
        );
    END IF;

    -- The key must still be active.
    IF rtrim(r.KEY_VALID_FLAG) <> 'Y' THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'message', 'This onboarding link is no longer active.'
        );
    END IF;

    -- The key must not have expired (NULL expiry means no expiry).
    IF r.KEY_EXPIRY_DATETIME IS NOT NULL AND r.KEY_EXPIRY_DATETIME < now() THEN
        RETURN jsonb_build_object(
            'allowed', false,
            'message', 'This onboarding link has expired.'
        );
    END IF;

    -- All checks passed: allow render and echo the trimmed key forward.
    RETURN jsonb_build_object(
        'allowed', true,
        'set_vars', jsonb_build_object('access_key', v_key, 'candidate_id', v_candidate_id)
    );
END;
$$;
