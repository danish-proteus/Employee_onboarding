## Master Data Management
Reference masters that drive selection lists, validations and cross-updates across the onboarding process. Each is a header-only transaction (T) with Search, Add, Edit, Delete.

### Country Master
- Description: Maintain countries used for nationality, address and detail-line country codes.
- Data points: COUNTRY_CODE, COUNTRY_NAME, ISO_CODE, DIAL_CODE, CURRENCY_CODE, ACTIVE_FLAG.
- Business rules: COUNTRY_CODE unique and mandatory; ACTIVE_FLAG defaults to 'Y'.
- Business actions: Search, Add, Edit, Delete.
- Additional data management: Soft-disable instead of physical delete when referenced by any candidate record.

### Designation & Department Master
- Description: Maintain designations, departments, grades, cadres and design codes used by HR during initiation and finalization.
- Data points: DESIGNATION (DESIGN_CODE, DESIGNATION_NAME), DEPT_CODE, DEPT_NAME, GRADE, GRADE_NAME, CADRE, CADRE_NAME, JOINED_AS, ACTIVE_FLAG.
- Business rules: Each code unique within its master; DESIGN_CODE mandatory and active to be selectable.
- Business actions: Search, Add, Edit, Delete.

### Organisation Setup Master (Sites, Shifts, Holiday Tables)
- Description: Maintain employment site, payroll site, work shift and holiday table values used at confirmation.
- Data points: EMP_SITE, SITE_NAME; PAY_SITE, PAY_SITE_NAME; WORK_SHIFT, SHIFT_NAME, SHIFT_TIMINGS; HOL_TBLNO, HOL_TBL_NAME; ACTIVE_FLAG.
- Business rules: Codes unique within master; only active rows selectable in finalization.
- Business actions: Search, Add, Edit, Delete.

### Allowance / Deduction (Pay Head) Master
- Description: Maintain pay heads referenced by the candidate pay structure (AD_CODE).
- Data points: AD_CODE, AD_NAME, AMOUNT_TYPE (Fixed/Percentage/Formula), DEFAULT_FREQUENCY (Monthly/Annual/One-time), RES_FORMULA, APPL_MODE (Earning/Deduction), ACTIVE_FLAG.
- Business rules: AD_CODE unique; if AMOUNT_TYPE = 'Formula' then RES_FORMULA mandatory.
- Business actions: Search, Add, Edit, Delete.

### Qualification Master
- Description: Maintain qualification codes/types used in the candidate education detail.
- Data points: QLF_CODE, QLF_NAME, QLF_TYPE (Academic/Professional/Certification), COURSE_TYPE (Full-time/Part-time/Distance), ACTIVE_FLAG.
- Business rules: QLF_CODE unique; QLF_TYPE mandatory.
- Business actions: Search, Add, Edit, Delete.

### Demographic Reference Master
- Description: Maintain lookup values for Religion, Caste Category, Blood Group, Marital Status, Name Prefix, Mother Tongue, Nationality and Relation (family).
- Data points: LOOKUP_TYPE, LOOKUP_CODE, LOOKUP_DESC, ACTIVE_FLAG.
- Business rules: (LOOKUP_TYPE, LOOKUP_CODE) unique; only active values appear in candidate form drop-downs.
- Business actions: Search, Add, Edit, Delete.

## Onboarding Configuration
System parameters controlling link generation, key behaviour and integration endpoints.

### Onboarding Settings
- Description: Single-record (or effective-dated) configuration governing access-key life, retry limits and IOFLOW connectivity.
- Data points: KEY_VALIDITY_DAYS (default 1), MAX_VALIDATION_ATTEMPTS (default 3), IOFLOW_BASE_URL, IOFLOW_PAN_ENDPOINT, IOFLOW_AADHAR_ENDPOINT, IOFLOW_BANK_ENDPOINT, IOFLOW_EMPLOYEE_ENDPOINT, IOFLOW_AUTH_TOKEN, HR_NOTIFY_EMAIL_TEMPLATE, CANDIDATE_SUBMIT_EMAIL_TEMPLATE.
- Business rules: KEY_VALIDITY_DAYS > 0; MAX_VALIDATION_ATTEMPTS between 1 and 10; URLs mandatory and well-formed.
- Business actions: Edit (Save). No delete.
- Additional data management: KEY_VALIDITY_DAYS and MAX_VALIDATION_ATTEMPTS are also exposed as project variables (:key_validity_days, :max_validation_attempts) and referenced by the link-generation logic and the candidate form. These tokens must be declared under the app's Variables panel.

## Candidate Onboarding Management
HR-facing master transaction covering the full lifecycle of a candidate record. Initiation, link dispatch, review and finalization are handled as **actions** on this single transaction, with STATUS driving the stage. Header + four detail tables (Past Experience, Educational Qualification, Family, Candidate Pay).

### Candidate Onboarding Record
- Description: HR creates and manages the candidate's onboarding record from initial capture through submission, review and confirmation as employee. The record carries a STATUS that advances through the process and a STATUS_DATE that is stamped on every transition.
- Data points (HR initial capture): CANDIDATE_ID (system), CANDIDATE_NAME, GENDER, COUNTRY_CODE, DESIGNATION (DESIGN_CODE), EMAIL_ID, STATUS, STATUS_DATE, INITIATED_BY (HR user), INITIATED_ON.
- Data points (access key): ACCESS_KEY (system-generated token), KEY_GENERATED_ON, KEY_EXPIRY_DATETIME, KEY_VALID_FLAG, FORM_URL, LINK_SENT_ON, LINK_ACCESSED_ON, SUBMITTED_ON.
- Data points (candidate personal — captured via self-service form, displayed/read-only here): EMP_FNAME, EMP_MNAME, EMP_LNAME, NAME_PREFIX, GENDER, BIRTHDATE, NATIONALITY, MARITAL_STATUS, MARRIAGE_ANNIVERSARY, BLOOD_GROUP, RELIGION, CAST_CATEGORY, MOTHER_TONGUE, PHYSICAL_HANDICAP, HOBBY1, HOBBY2, TOTAL_EXPERIENCE.
- Data points (contact & address): CURRENT_ADDRESS, CURRENT_PIN, CURRENT_CITY, CURRENT_STATE, PERMANENT_ADDRESS, PERMANENT_PIN, PERMANENT_CITY, PERMANENT_STATE, MOBILE, ALTERNATE_TELEPHONE, CONTACT_PERSON, CONTACT_PERSON_MOBILE, CONTACT_PERSON_EMAIL.
- Data points (statutory & financial): PAN_NO, AADHAR_NO, PASSPORT_NO, DRIVING_LIC_NO, PF_NO, ESIC_NO, BANK_ACCOUNT_NO, BANK_IFSC_CODE, BANK_NAME.
- Data points (validation status): PAN_VALIDATED (Y/N), PAN_VALIDATED_NAME, PAN_ATTEMPTS; AADHAR_VALIDATED (Y/N), AADHAR_VALIDATED_NAME, AADHAR_ATTEMPTS; BANK_VALIDATED (Y/N), BANK_VALIDATED_NAME, BANK_ATTEMPTS.
- Data points (attachments): PAN_DOC (image/file), AADHAR_DOC (image/file), BANK_DOC (cancelled cheque / passbook image).
- Data points (HR finalization): EMP_CODE, DESIGNATION, DEPT_CODE, GRADE, CADRE, DESIGN_CODE, REPORT_TO, JOINED_AS, DATE_JOIN, WORK_SHIFT, HOL_TBLNO, EMP_SITE, PAY_SITE, BASIC, GROSS, PROBATION_DATE, PROBATION_PRD, NOTICE_PRD, EMAIL_ID_OFF, REPORT_TO__ADMIN, USER_ID, REMARKS, EMPLOYEE_PUSHED_FLAG, EMPLOYEE_PUSH_REF.
- Business rules:
  - STATUS lifecycle: Link Generated → Link Accessed → DataSubmitted → Review → Confirmed; STATUS_DATE updated on each transition.
  - EMAIL_ID mandatory and valid format before a link can be generated.
  - ACCESS_KEY unique; KEY_EXPIRY_DATETIME = KEY_GENERATED_ON + :key_validity_days. Key invalid after expiry or after submission.
  - PAN_NO format AAAAA9999A; AADHAR_NO 12 digits; BANK_IFSC_CODE 11-char IFSC pattern; MOBILE numeric 10 digits; PIN numeric 6 digits; CONTACT_PERSON_EMAIL valid email.
  - Validation attempts for PAN/AADHAR/BANK capped at :max_validation_attempts (default 3) each.
  - Once STATUS = DataSubmitted the candidate-editable fields become read-only to candidate; HR can edit finalization fields only.
  - EMP_CODE mandatory and unique before Confirm; DATE_JOIN mandatory before Confirm; GROSS ≥ BASIC.
  - Confirm allowed only when STATUS = Review and mandatory finalization fields complete.
- Business actions: Search, List Recent, Add (Initiate Candidate), Edit, Delete (only while STATUS = Link Generated and link not accessed), **Send/Resend Link**, **Re-validate PAN/AADHAR/Bank (IOFLOW)**, **Review**, **Confirm** (Push to IOFLOW Employee), Cancel.
- Additional data management & cross-updates:
  - On **Add/Initiate**: generate CANDIDATE_ID, set STATUS = (blank/Initiated).
  - On **Send Link**: generate ACCESS_KEY, compute KEY_EXPIRY_DATETIME, build FORM_URL (external candidate form + key), set STATUS = 'Link Generated', stamp STATUS_DATE & LINK_SENT_ON. Trigger: send-email to candidate with the link.
  - On **Re-validate**: invoke IOFLOW PAN/AADHAR/BANK endpoint, store *_VALIDATED, *_VALIDATED_NAME, increment *_ATTEMPTS; block further calls beyond the configured attempt cap.
  - On **Review**: set STATUS = 'Review', stamp STATUS_DATE.
  - On **Confirm**: trigger IOFLOW Employee-creation API with the consolidated employee payload (personal + finalization + pay structure); store EMPLOYEE_PUSHED_FLAG and EMPLOYEE_PUSH_REF; set STATUS = 'Confirmed', stamp STATUS_DATE; send-notification to INITIATED_BY HR user.
  - On candidate **Submit** (from the external form): set STATUS = 'DataSubmitted', stamp STATUS_DATE & SUBMITTED_ON, invalidate ACCESS_KEY, send-notification to initiating HR user and send-email summary to candidate.

### Past Experience (detail)
- Description: Multiple prior-employment rows entered by the candidate, displayed/editable on the HR transaction.
- Data points: LINE_NO, ORGANISATION, DESIGNATION, FROM_DATE, TO_DATE, GROSS_AMT.
- Business rules: TO_DATE ≥ FROM_DATE; GROSS_AMT ≥ 0; LINE_NO auto-sequenced.
- Business actions: Add row, Edit row, Delete row (subject to submission lock).

### Educational Qualification (detail)
- Description: Multiple qualification rows entered by the candidate.
- Data points: LINE_NO, QLF_CODE, QLF_TYPE, INSTITUTE, PASS_YEAR, CLASS, PERCENTAGE, COUNTRY_CODE, COURSE_TYPE, COURSE_DURATION.
- Business rules: QLF_CODE must exist in Qualification master; PASS_YEAR ≤ current year; PERCENTAGE between 0 and 100; COUNTRY_CODE valid; LINE_NO auto-sequenced.
- Business actions: Add row, Edit row, Delete row.

### Family Details (detail)
- Description: Multiple family-member rows entered by the candidate.
- Data points: LINE_NO, MEMBER_NAME, DATE_BIRTH, GENDER, RELATION.
- Business rules: MEMBER_NAME and RELATION mandatory; DATE_BIRTH ≤ today; RELATION from Demographic Reference master; LINE_NO auto-sequenced.
- Family member GENDER and RELATION must be consistent. The following combinations are not allowed and are blocked with a message: Female+Brother ('Brother cannot be female.'), Female+Father ('Father cannot be female.'), Female+GrandFather ('GrandFather cannot be female.'), Female+Son ('Son cannot be female.'), Female+Husband ('Husband cannot be female.'), Male+Mother ('Mother cannot be male.'), Male+Sister ('Sister cannot be male.'), Male+GrandMother ('GrandMother cannot be male.'), Male+Wife ('Wife cannot be male.'), Male+Daughter ('Daughter cannot be male.'). The rule applies identically in the HR-maintained Candidate Onboarding Record and the candidate self-service form. The check is enforced when either GENDER or RELATION is entered/changed.
- MEMBER_NAME must be unique within a candidate — the same family member name cannot be added twice in the Family section; a duplicate is blocked on Save with the message 'Family member <name> is already added. Duplicate member names are not allowed.'
- Business actions: Add row, Edit row, Delete row.

### Candidate Pay Structure (detail — HR only)
- Description: HR enters multiple pay-head rows defining the candidate's compensation structure during finalization.
- Data points: LINE_NO, AD_CODE, AMOUNT, AMOUNT_TYPE, FREQUENCY, RES_FORMULA, AMOUNT_CALC, UPD_PAYSTRU, APPL_MODE.
- Business rules: AD_CODE must exist in Pay Head master; if AMOUNT_TYPE = 'Formula' then RES_FORMULA mandatory and AMOUNT_CALC is derived; AMOUNT ≥ 0; UPD_PAYSTRU (Y/N) controls write-back to payroll; APPL_MODE = Earning/Deduction; LINE_NO auto-sequenced.
- Business actions: Add row, Edit row, Delete row.
- Additional data management: rows with UPD_PAYSTRU = 'Y' are included in the IOFLOW Employee payload on Confirm.

## Candidate Self-Service Onboarding Form
Public, key-validated intake screen the candidate opens from the emailed link. It is anonymous (no Vision app login) and is delivered as a Smart Page hosted on the External Website (see below). Documented here as a process activity for traceability; the page blocks are detailed under Smart Pages / External Website.

### Validate Access & Open Form
- Description: On opening the link, the form validates the key before rendering any input.
- Data points (read): ACCESS_KEY, KEY_EXPIRY_DATETIME, STATUS.
- Business rules: key must exist, be unexpired, and STATUS not already 'DataSubmitted' or 'Confirmed'; otherwise show an expired/invalid-link message and deny access.
- Business actions: Validate Key, Open Form.
- Additional data management: on first successful open set STATUS = 'Link Accessed', stamp STATUS_DATE & LINK_ACCESSED_ON.

### Capture Candidate Details
- Description: Candidate fills personal, contact, statutory, financial details plus the three detail tables, with inline document validation and attachments.
- Data points: all candidate personal/contact/statutory/financial fields listed in the Candidate Onboarding Record; Past Experience, Educational Qualification and Family detail tables; PAN_DOC, AADHAR_DOC, BANK_DOC attachments.
- Business rules: same field-level validations as the header; mandatory fields enforced on Submit (not on Save); PAN/AADHAR/BANK validation limited to :max_validation_attempts attempts each; attachments restricted to image/PDF with size limit; BANK_DOC must be a cancelled cheque or passbook image.
- Family member Gender and Relation must be consistent. The following combinations are not allowed and are blocked with a message: Female+Brother ('Brother cannot be female.'), Female+Father ('Father cannot be female.'), Female+GrandFather ('GrandFather cannot be female.'), Female+Son ('Son cannot be female.'), Female+Husband ('Husband cannot be female.'), Male+Mother ('Mother cannot be male.'), Male+Sister ('Sister cannot be male.'), Male+GrandMother ('GrandMother cannot be male.'), Male+Wife ('Wife cannot be male.'), Male+Daughter ('Daughter cannot be male.'). The rule applies identically in the HR-maintained Candidate Onboarding Record and the candidate self-service form.
- Past Experience carry-over — when HR sends or resends the onboarding link, every Past Experience detail line already saved by HR on the candidate record (EMPONB_CAND_EXPERIENCE) is copied into the candidate self-service Past Experience detail (EMPONB_CAND_SELF_EXPERIENCE) for the same CANDIDATE_ID, so the candidate sees the existing rows pre-filled when the link is opened. The copy is idempotent: a resend refreshes the candidate-side rows only while the record is still in Link Generated / Link Accessed status and never creates duplicates. Once the candidate has submitted (status DataSubmitted, Review or Confirmed) the candidate-side rows are left untouched. The candidate may edit, add or delete these lines before submitting.
- Business actions: **Validate PAN (IOFLOW)**, **Validate Aadhaar (IOFLOW)**, **Validate Bank (IOFLOW)**, Attach/Upload document, **Save** (draft, remains editable), **Submit** (final).
- Additional data management:
  - Each validate call stores *_VALIDATED (True/False), *_VALIDATED_NAME (name returned), and increments *_ATTEMPTS; once the attempt cap is reached the validate button is disabled.
  - Save persists a draft and keeps the record editable; the candidate may reopen the link and continue until Submit.
  - On Submit: enforce mandatory fields, set STATUS = 'DataSubmitted', stamp STATUS_DATE, invalidate the key (link can no longer be opened), email the candidate a full summary of submitted data, and notify the initiating HR user.

## Reports & Visuals

### Onboarding Pipeline by Status (V)
- Visualization: Stacked-Column-Chart. Criteria: date range (INITIATED_ON), DESIGN_CODE, COUNTRY_CODE. Data points: count of candidates per STATUS per period. Drill-down: click a segment → filtered candidate list.

### Candidate Status Distribution (V)
- Visualization: Pie-Chart / Doughnut-Chart. Criteria: date range. Data points: STATUS vs candidate count.

### Onboarding Tracker (V)
- Visualization: Grid. Criteria: STATUS, INITIATED_BY, date range, DESIGNATION. Data points: CANDIDATE_NAME, EMAIL_ID, DESIGNATION, STATUS, STATUS_DATE, LINK_SENT_ON, LINK_ACCESSED_ON, SUBMITTED_ON, KEY_EXPIRY_DATETIME, INITIATED_BY. Hyperlink: CANDIDATE_NAME → Candidate Onboarding Record.

### Expired / Pending Links (V)
- Visualization: Grid. Criteria: status in (Link Generated, Link Accessed). Data points: CANDIDATE_NAME, EMAIL_ID, LINK_SENT_ON, KEY_EXPIRY_DATETIME, days pending, STATUS. Conditional highlight for keys past expiry.

### Validation Outcome Summary (V)
- Visualization: Grid / Column-Chart. Criteria: date range. Data points: counts of PAN/AADHAR/BANK validated vs failed vs attempts-exhausted.

### Onboarding Aging (V)
- Visualization: Bar-Chart. Criteria: status. Data points: average days in each status / candidate-wise aging buckets.

### Candidate Profile Data Sheet (R)
- Description: Pixel-perfect printable consolidation of a confirmed/submitted candidate, used for the personnel file.
- Layout type: Document with header (company logo + title), candidate photo block, and signature block; page breaks between sections.
- Criteria: CANDIDATE_ID.
- Grouping levels: (1) Personal & Contact, (2) Statutory & Bank with validation status, (3) Past Experience, (4) Educational Qualification, (5) Family, (6) Employment & Pay Structure.
- Sub-total/total rows: Pay Structure sub-totals of earnings and deductions and net (GROSS) at the foot of the pay section.
- Columns: all header fields plus the four detail tables in their listed columns.

## HR Onboarding Dashboard (D)
- Role: HR / Onboarding Coordinator.
- Criteria (with defaults): date range (default current month, on INITIATED_ON), DESIGN_CODE (default All), INITIATED_BY (default current user), STATUS (default All).
- Key metric Cards (top): Total Candidates Initiated, Links Pending Action, Data Submitted (awaiting review), Confirmed this period, Expired Links.
- Visuals:
  - Onboarding Pipeline by Status (Stacked-Column-Chart) — count per STATUS per period.
  - Candidate Status Distribution (Doughnut-Chart) — STATUS vs count.
  - Onboarding Tracker (Grid) — candidate-wise current status with hyperlink to the record.
  - Validation Outcome Summary (Column-Chart) — PAN/AADHAR/BANK validated vs failed.
  - Onboarding Aging (Bar-Chart) — average days per status.

## Smart Pages (S)

### Candidate Onboarding Form (public, key-validated)
- Purpose & audience: external candidates completing their onboarding details from the emailed link, without logging into the Vision app.
- Key sections / blocks:
  - Hero block with company branding and a welcome heading addressing the candidate by name.
  - Key-validation gate: if invalid/expired/already-submitted, render a callout block with an "invalid or expired link" message and hide all inputs.
  - Personal Details section (inline inputs): NAME_PREFIX, EMP_FNAME, EMP_MNAME, EMP_LNAME, GENDER, BIRTHDATE, NATIONALITY, MARITAL_STATUS, MARRIAGE_ANNIVERSARY, BLOOD_GROUP, RELIGION, CAST_CATEGORY, MOTHER_TONGUE, PHYSICAL_HANDICAP, HOBBY1, HOBBY2, TOTAL_EXPERIENCE.
  - Address & Contact section: current and permanent address fields, MOBILE, ALTERNATE_TELEPHONE, emergency contact person fields. (Optional "same as current" copy action.)
  - Statutory & Financial section with inline validate buttons: PAN_NO (+ Validate PAN), AADHAR_NO (+ Validate Aadhaar), PASSPORT_NO, DRIVING_LIC_NO, PF_NO, ESIC_NO, BANK_ACCOUNT_NO + BANK_IFSC_CODE + BANK_NAME (+ Validate Bank). Each shows validated status and returned name, with remaining-attempts indicator.
  - Document upload blocks: PAN_DOC, AADHAR_DOC, BANK_DOC (cancelled cheque/passbook).
  - Grid/repeater blocks for Past Experience, Educational Qualification and Family with add/remove row.
- Inline inputs & actions/CTAs:
  - Validate PAN / Validate Aadhaar / Validate Bank → call External Website API → store result, decrement remaining attempts.
  - Save (Draft) → persists, keeps form editable, candidate may return via the same link.
  - Submit → final validation, locks the form, sets STATUS = 'DataSubmitted', emails candidate the summary, notifies HR; thereafter the link shows the "already submitted" message.

### Onboarding Confirmation / Thank-You (public)
- Purpose & audience: shown to the candidate after Submit.
- Key sections: hero confirmation banner, callout summarizing that details were received and a copy emailed, contact-HR line. No inputs.

## External Website: Candidate Onboarding Portal
- Purpose, audience & primary CTA: a public, anonymous site that hosts the key-validated candidate onboarding form reachable from the emailed link. Audience: prospective employees. Primary CTA: "Complete Your Onboarding".
- Custom domains: optional (e.g. onboarding.<tenant>.com); default tenant subdomain at tenant.proteusvision.com/.
- Marketing / functional pages (Smart Pages):
  - Onboarding Form page (the Candidate Onboarding Form Smart Page above) — entry route carrying the key, e.g. /onboard?key=<ACCESS_KEY>.
  - Thank-You / Confirmation page (the Onboarding Confirmation Smart Page above).
  - Invalid/Expired Link page — hero + callout explaining the link is no longer valid and to contact HR.

### Header
- A shared header Smart Page rendered on every portal page: tenant logo (left), portal title "Employee Onboarding", and a help/contact-HR link (right). No login control (anonymous site).

### Footer
- A shared footer Smart Page on every page: copyright line, privacy/data-use note, and a contact line (HR email/phone). Optional secondary link group (Privacy, Terms).

### API Requirements
- GET /api/onboard/validate-key — validate the candidate key and return whether the form may open. Query params: key. Response: { valid: bool, status, candidate_name, expires_at, reason }. Cache TTL: 0 (always live).
- GET /api/onboard/draft — load any saved draft for the keyed candidate. Query params: key. Response: { header:{...candidate fields}, validation_status:{...}, experience:[...], education:[...], family:[...] }. Cache TTL: 0.
- GET /api/masters/countries — country lookup. Query params: active=Y. Response: [{ country_code, country_name }]. Cache TTL: 86400.
- GET /api/masters/qualifications — qualification lookup. Query params: active=Y. Response: [{ qlf_code, qlf_name, qlf_type }]. Cache TTL: 86400.
- GET /api/masters/lookups — demographic lookups (prefix, gender, marital status, blood group, religion, caste, relation). Query params: type. Response: [{ lookup_code, lookup_desc }]. Cache TTL: 86400.
- POST /api/onboard/validate/{type} — proxy an IOFLOW validation for type ∈ {pan, aadhar, bank}. Body: { key, value, ifsc? }. Response: { validated: bool, name_returned, attempts_used, attempts_remaining }. Cache TTL: 0.
- POST /api/onboard/upload — upload PAN/AADHAR/BANK document. Body (multipart): key, doc_type, file. Response: { uploaded: bool, doc_ref }. Cache TTL: 0.
- POST /api/onboard/save — save draft. Body: { key, ...form payload }. Response: { saved: bool }. Cache TTL: 0.
- POST /api/onboard/submit — final submission. Body: { key, ...complete payload }. Response: { submitted: bool, status }. Cache TTL: 0.