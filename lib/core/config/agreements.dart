class Agreements {
  static const String ndaText = '''
# iEvaluate — Non-Disclosure Agreement (NDA)

**System:** iEvaluate: An AI-Driven Mobile Instructor Evaluation and Performance Analysis System
**Institution:** Cebu Technological University – Argao Campus
**Applies to:** All registered users — SAO Admin, SAO-Staff, Instructor, and Department Head accounts

---

## 1. Purpose

This Non-Disclosure Agreement ("Agreement") governs the confidentiality obligations of every user who is granted access to the iEvaluate system. By registering for an account, you acknowledge that you will encounter confidential information — including instructor evaluation records, student feedback, performance analytics, and system credentials — and you agree to protect that information as set out below.

## 2. Definition of Confidential Information

"Confidential Information" includes, but is not limited to:

- Instructor evaluation forms, ratings, scores, and written comments (whether raw, OCR-extracted, or processed)
- Aggregated and individual instructor performance analytics and reports
- Student identification numbers, signatures, and any other identifiers captured during evaluation form processing
- Login credentials, authentication tokens, and account information for any role
- System architecture details, database contents, API keys, and backend configurations (n8n workflows, Supabase/PostgreSQL records, webhook endpoints, etc.)
- Any other data accessible through the SAO Admin, SAO-Staff, Instructor, or Department Head dashboards that is not intended for public release

## 3. User Obligations

By accepting this Agreement, you agree to:

1. **Access only what your role permits.** Use your assigned Role-Based Access Control (RBAC) permissions solely for legitimate, work-related purposes tied to your official function.
2. **Not disclose.** Not share, copy, forward, screenshot, print, or otherwise disclose Confidential Information to any person or system not authorized to receive it.
3. **Not use for personal gain.** Not use Confidential Information for any purpose other than the evaluation, review, and improvement processes the system is designed to support.
4. **Protect your credentials.** Keep your login credentials confidential, never share your account, and report any suspected unauthorized access immediately to the SAO Admin.
5. **Report breaches.** Promptly report any accidental disclosure, data breach, or suspected security incident involving Confidential Information.
6. **Respect anonymization.** Not attempt to re-identify anonymized or hashed student data (e.g., hashed Student IDs used for validation) or circumvent the system's privacy safeguards.
7. **Return or delete on exit.** Cease all access to Confidential Information upon account deactivation, role change, or separation from the institution, and delete any locally retained copies.

## 4. Exclusions

This Agreement does not restrict information that:

- Is or becomes publicly available through no fault of the user
- Is officially released by SAO Admin or the institution for reporting, accreditation, or public disclosure purposes
- Is required to be disclosed by law, court order, or a lawful directive of the University or relevant government authority (e.g., the National Privacy Commission)

## 5. Duration

These confidentiality obligations take effect upon account approval and **remain in effect for as long as you hold an account**, and **continue after your account is deactivated or you leave your role**, for as long as the underlying data remains confidential.

## 6. Consequences of Breach

Violation of this Agreement may result in:

- Immediate suspension or termination of system access
- Reporting to the SAO Admin and relevant University office for disciplinary action
- Referral to appropriate authorities where the breach involves a violation of the Data Privacy Act of 2012 (RA 10173) or other applicable law

## 7. Acknowledgment

By checking "I Agree" during registration, you confirm that you have read, understood, and voluntarily agree to be bound by this Non-Disclosure Agreement as a condition of accessing the iEvaluate system.

---

*This Agreement is presented alongside the iEvaluate Data Privacy Notice & Consent, which describes how personal and evaluation data is collected, used, and protected.*
''';

  static const String dpaText = '''
# iEvaluate — Data Privacy Notice & Consent

**System:** iEvaluate: An AI-Driven Mobile Instructor Evaluation and Performance Analysis System
**Institution:** Cebu Technological University – Argao Campus
**Legal Basis:** Republic Act No. 10173, the Data Privacy Act of 2012, and its Implementing Rules and Regulations

---

## 1. Introduction

Cebu Technological University – Argao Campus ("the University"), through the iEvaluate system, is committed to protecting your privacy and personal data in compliance with the Data Privacy Act of 2012 (RA 10173). This notice explains what information we collect, why we collect it, how it is protected, and what rights you have as a data subject.

By registering an account and using iEvaluate, you consent to the collection and processing of your personal data as described in this notice.

## 2. Information We Collect

Depending on your role (SAO Admin, SAO-Staff, Instructor, or Department Head), iEvaluate may collect:

- **Personal information**: Full name, contact details, institutional email, university ID number
- **Academic/institutional details**: Department, position, assigned subjects/sections
- **Account credentials**: Username, encrypted password, authentication tokens
- **Evaluation data**: Instructor ratings, scores, and written/OCR-extracted comments submitted through evaluation forms
- **Sensitive identifiers (transient)**: Student ID numbers and signatures captured during Optical Mark Recognition (OMR)/Optical Character Recognition (OCR) processing
- **Usage data**: Login timestamps, session activity, and audit logs for security monitoring

Student identifiers such as ID numbers and signatures are used **only momentarily**, for backend validation of submitted forms. They are **hashed/anonymized or scrubbed from the database** immediately after validation and are not retained in identifiable form.

## 3. How We Use Your Information

Your data is used solely to:

- Authenticate and authorize access to the system based on your assigned role
- Process and validate instructor evaluation forms (via OMR/OCR and the n8n automation pipeline)
- Generate performance analytics, dashboards, and reports for authorized personnel
- Maintain audit logs for security and accountability
- Improve system reliability and support academic/institutional evaluation processes

Your data is **not** used for advertising, sold to third parties, or shared outside the scope of the University's evaluation processes.

## 4. How We Protect Your Data

iEvaluate applies the following safeguards:

- **Authentication:** JSON Web Token (JWT)-based, time-limited sessions
- **Authorization:** Role-Based Access Control (RBAC), so users only see data relevant to their role (e.g., Department Heads receive read-only access to anonymized performance summaries)
- **Encryption:** Data is encrypted in storage and transmitted exclusively over HTTPS
- **Anonymization:** Student identifiers are hashed or removed after validation
- **Offline safety:** Data captured offline is cached locally (SQLite) and synced securely once connectivity is restored
- **Access review:** New accounts remain pending until approved by the SAO Admin

## 5. Data Storage and Retention

- Evaluation records and analytics are stored in a secure, PostgreSQL-based cloud database (Supabase).
- Data is retained only for as long as necessary to fulfill evaluation, reporting, and institutional/academic requirements, or as required by University policy and applicable law.
- Sensitive transient identifiers (student IDs, signatures) are not retained beyond the validation step.

## 6. Your Rights as a Data Subject

Under RA 10173, you have the right to:

- **Be informed** that your personal data will be, are being, or were processed
- **Access** your personal data held in the system
- **Correct** inaccurate or outdated personal data
- **Object** to processing, subject to legal or contractual restrictions
- **Erasure or blocking** of data that is no longer necessary, subject to institutional record-keeping requirements
- **Data portability**, where applicable
- **File a complaint** with the University or the National Privacy Commission (NPC) if you believe your data has been misused

To exercise these rights, contact the SAO Admin or the University's designated Data Protection Officer.

## 7. Data Sharing

Personal and evaluation data within iEvaluate is accessible only to authorized personnel (SAO Admin, SAO-Staff, Department Heads, and relevant Instructors) according to their role permissions. Data will not be disclosed to external parties except:

- When required by law or a valid order from a competent authority
- With your explicit consent
- For official University reporting/accreditation purposes, in aggregated or anonymized form

## 8. Consent

By checking "I Agree" during registration, you acknowledge that:

- You have read and understood this Data Privacy Notice
- You voluntarily consent to the collection, processing, and storage of your personal data as described
- You understand your rights under RA 10173 and how to exercise them

---

*This notice is presented alongside the iEvaluate Non-Disclosure Agreement, which governs your confidentiality obligations while using the system.*
''';
}
