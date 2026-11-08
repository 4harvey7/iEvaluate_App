# iEvaluate Software Evaluation Questionnaire
### *iEvaluate: An AI-Driven Mobile Instructor Evaluation and Performance Analysis System Using n8n Workflow Automation*
**Cebu Technological University – Argao Campus**

---
## Purpose of the Evaluation
This questionnaire evaluates the quality, functional effectiveness, usability, and acceptance of **iEvaluate**. The iEvaluate system comprises four integrated components: (1) the **iEvaluate Android Mobile Application** for data gatherers, instructors, department heads, and administrators; (2) the **iEvaluate Batch Scanning Website** with the desktop **Scan Watcher** daemon for high-speed document scanners; (3) the **n8n Workflow Automation Engine** orchestrating OpenCV Optical Mark Recognition (OMR) and Google Gemini AI multimodal extraction; and (4) the **Supabase** cloud database backend.

The evaluation is structured into five distinct instruments:
- **Part I: ISO/IEC 25010 Software Quality Evaluation** (8 core dimensions: Functional Suitability, Performance Efficiency, Compatibility, Usability, Reliability, Security, Maintainability, Portability)
- **Part II: Objective-Based Evaluation** (Direct assessment against the five specific research objectives of the study)
- **Part III: System Usability Scale (SUS)** (Standardized 10-item usability metric)
- **Part IV: Technology Acceptance Model (TAM)** (Perceived Usefulness & Perceived Ease of Use)
- **Part V: Qualitative Open-Ended Feedback**

## Data Privacy Notice and Research Consent
In compliance with the Data Privacy Act of 2012 (Republic Act No. 10173), all personal information, ratings, and feedback provided in this questionnaire will be treated with absolute confidentiality. Data collected will be analyzed strictly in summarized form and utilized solely for academic research, software validation, and system enhancement. Participation in this evaluation is entirely voluntary. By answering this questionnaire, you signify your informed consent to the collection and academic processing of your responses.

## Respondent's Demographic Profile
- **Name (Optional):** __________________________________________________
- **Age:** __________ &nbsp;&nbsp;&nbsp;&nbsp; **Affiliated Institution / Office:** ________________________________
- **Primary Role (check one):**
  - [ ] SAO Administrator (System Admin)
  - [ ] SAO Staff / Data Gatherer (Scanning & Ingestion Operator)
  - [ ] Department Head (Academic Supervisor)
  - [ ] Instructor / Faculty Member
  - [ ] IT Expert / External Evaluator (Computer Science / IT Faculty, Software Engineer, Systems Analyst)
- **System Components Tested / Evaluated (check all that apply):**
  - [ ] iEvaluate Mobile Application (Android)
  - [ ] iEvaluate Batch Scanning Website & Scan Watcher Desktop Daemon
  - [ ] Google Sheets Evaluation Import Module
  - [ ] End-to-End AI Extraction & Reporting Workflows

---
## Rating Scale & Instructions (Parts I, II, & IV)
Please evaluate each statement objectively based on your direct testing or demonstration experience with iEvaluate. Indicate your rating using the standardized 5-point Likert scale (**no N/A column**):

| Rating | Descriptor | Meaning |
| :---: | :--- | :--- |
| **5** | **Strongly Agree** | Highly Acceptable / Fully Meets Expectations |
| **4** | **Agree** | Acceptable / Meets Expectations |
| **3** | **Neutral** | Moderately Acceptable / Neutral |
| **2** | **Disagree** | Slightly Acceptable / Partially Meets Expectations |
| **1** | **Strongly Disagree** | Unacceptable / Does Not Meet Expectations |

## Part I: ISO/IEC 25010 Software Quality Evaluation

### A. Functional Suitability
*Degree to which the system provides functions that meet stated and implied evaluation needs.*

| Dimension / Statement | 5 | 4 | 3 | 2 | 1 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Functional Completeness:** iEvaluate provides all the essential functions needed to digitize evaluation forms (smartphone camera capture, batch scanner station with Scan Watcher, and Google Sheets import) and generate comprehensive instructor evaluation reports. | | | | | |
| **Functional Correctness:** The system accurately reads rating marks (via OpenCV Optical Mark Recognition cross-checked by Google Gemini AI) and correctly computes category means (Management, Performance) and overall ratings with their descriptive equivalents. | | | | | |
| **Functional Appropriateness:** The features (mobile camera scanning, sync queue, human-in-the-loop review station, role-based dashboards, and intervention monitoring) effectively support the evaluation tasks of the SAO, Department Heads, and Instructors. | | | | | |
| **Functional Integration:** Data from mobile camera scans, high-speed document scanners, and Google Sheets imports seamlessly converge into a single centralized database without missing records or conflicting data. | | | | | |

### B. Performance Efficiency
*Performance relative to the amount of resources used under stated conditions.*

| Dimension / Statement | 5 | 4 | 3 | 2 | 1 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Time Behavior:** The system processes scanned forms, extracts handwritten feedback, and updates dashboard metrics within an acceptable and responsive turnaround time. | | | | | |
| **Resource Utilization:** The mobile app operates efficiently without excessive consumption of phone battery, memory, storage, or mobile network data during capture and sync operations. | | | | | |
| **Capacity & Scalability:** The system handles high volumes of forms, multiple scanning batches, and extensive historical evaluation records without crashing or significant slowdowns. | | | | | |
| **Concurrent Processing:** The system maintains responsive and stable performance when multiple users (administrators, staff, department heads, and instructors) access dashboards and submit scans simultaneously. | | | | | |

### C. Compatibility
*Degree to which the system can exchange information with other systems and work while sharing the same environment.*

| Dimension / Statement | 5 | 4 | 3 | 2 | 1 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Co-existence:** The iEvaluate mobile application and the desktop Scan Watcher program run harmoniously alongside other installed applications on phones or laptops without system conflicts. | | | | | |
| **Interoperability:** Forms captured from the phone app, the batch scanning website, and Google Sheets all integrate into consistent, unified results with zero mismatched records. | | | | | |
| **Cross-Platform Consistency:** The system delivers consistent data presentation, business logic, and reporting accuracy across supported Android devices and standard desktop web browsers. | | | | | |
| **Data Synchronization:** The system allows the mobile app, web scanning portal, n8n automation engine, and Supabase backend to exchange data smoothly and reliably. | | | | | |

### D. Usability
*Degree to which the system can be used by users to achieve specified goals with effectiveness, efficiency, and satisfaction.*

| Dimension / Statement | 5 | 4 | 3 | 2 | 1 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Appropriateness Recognizability:** Users can easily understand the purpose and functionality of each screen (camera viewfinder, sync queue, review station, analytics dashboard, and reports). | | | | | |
| **Learnability:** Users can quickly learn how to operate the system, scan forms, resolve flagged records, and interpret visual reports, assisted by built-in SAST Guidelines and visual prompts. | | | | | |
| **Operability:** System controls for scanning, syncing, reviewing flagged forms, importing spreadsheets, and exporting reports are intuitive and convenient to operate. | | | | | |
| **User Error Protection:** The system actively protects users from errors through real-time camera level/tilt warnings, blur detection, paper size selection, duplicate stamp rejection, and automatic discarding of incomplete forms. | | | | | |
| **User Interface Aesthetics:** The mobile app and the batch scanning website provide a clean, professional, consistent, and visually appealing interface. | | | | | |
| **Accessibility & Clarity:** The interface uses clear text, readable charts, color-coded sentiment badges, and brand-themed word clouds, making information accessible to users of varying technical skill. | | | | | |

### E. Reliability
*Degree to which the system performs specified functions under stated conditions for a specified period of time.*

| Dimension / Statement | 5 | 4 | 3 | 2 | 1 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Maturity & Stability:** The system operates dependably without unexpected freezing, crashes, or unhandled exceptions during continuous scanning, synchronization, and analytics generation. | | | | | |
| **Availability:** The mobile application, web scanning portal, database, and backend workflow services remain accessible and functional when needed during evaluation periods. | | | | | |
| **Fault Tolerance:** The system handles operational issues gracefully (such as network loss, low-confidence marks, or poor lighting) by queuing items locally or routing them to human validation. | | | | | |
| **Recoverability:** The offline sync queue preserves un-uploaded scans during network interruptions or unexpected app termination, allowing seamless resumption without data loss. | | | | | |

### F. Security
*Degree to which the system protects information and data so that users have access appropriate to their types and levels of authorization.*

| Dimension / Statement | 5 | 4 | 3 | 2 | 1 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Confidentiality & Anonymity:** Evaluation results and student remarks are visible only to authorized roles, and student identification numbers are permanently hidden from Instructors and Department Heads to protect anonymity. | | | | | |
| **Data Integrity:** Only authenticated and authorized users can modify evaluation records, and all score corrections are strictly governed through dedicated validation and review screens. | | | | | |
| **Non-repudiation & Auditability:** Account modifications, batch scan operations, and review approvals or rejections are recorded in tamper-evident Security Audit Logs with user and timestamp details. | | | | | |
| **Authenticity & Access Governance:** New accounts require administrative approval before activation, sign-ins are validated against secure role permissions, and users must acknowledge the NDA and Data Privacy Agreement. | | | | | |
| **Data Lifecycle Protection:** The system enforces automated security policies, including rate-limiting repeated failed logins on the website and automatically purging stored raw scanned page images after 90 days. | | | | | |

### G. Maintainability
*Degree of effectiveness and efficiency with which the system can be modified, corrected, or adapted.*

| Dimension / Statement | 5 | 4 | 3 | 2 | 1 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Modularity:** The system architecture is cleanly decoupled (mobile app, web portal, desktop watcher, automation workflows, and database), so updating one component has minimal impact on others. | | | | | |
| **Reusability & Extensibility:** The mark-reading algorithms, workflow templates, and database schemas are adaptable and reusable for future institutional survey forms (such as SET-15 and SUP-15). | | | | | |
| **Analyzability & Diagnostics:** Detailed system logs, workflow execution histories, and structured review reasons allow developers and administrators to quickly diagnose and resolve form processing issues. | | | | | |
| **Modifiability & Testability:** Developers can efficiently modify system features, update scoring thresholds, and verify that form extraction and metric computations remain accurate. | | | | | |

### H. Portability
*Degree of effectiveness and efficiency with which a system can be transferred from one hardware, software, or operational environment to another.*

| Dimension / Statement | 5 | 4 | 3 | 2 | 1 |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Adaptability:** The mobile app adapts effectively across various Android smartphone screen sizes, and the web batch scanning portal functions smoothly on standard desktop browsers. | | | | | |
| **Installability:** The mobile app (APK), web portal, and desktop Scan Watcher program can be easily installed, configured, and uninstalled following straightforward procedures. | | | | | |
| **Operational Replaceability:** iEvaluate effectively modernizes and replaces traditional manual paper handling, tedious manual keyboard encoding, and physical filing of evaluation results. | | | | | |

## Part II: Objective-Based Evaluation

### Objective 1: Multi-Channel Form Digitization
*To develop a mobile application and a web-based batch-scanning station that allow authorized SAO personnel to digitize completed evaluation forms through smartphone capture, document-scanner batches, and Google Sheets import, eliminating the need for manual encoding.*

| No. | Statement | 5 | 4 | 3 | 2 | 1 |
| :---: | :--- | :---: | :---: | :---: | :---: |
| **1.1** | The mobile app lets authorized users capture completed evaluation forms using the smartphone camera with real-time level/tilt guidance and blur warnings. | | | | | |
| **1.2** | The mobile app allows users to choose the appropriate paper size (Short, A4, or Long bond paper) before scanning to ensure accurate form framing. | | | | | |
| **1.3** | The mobile app maintains an offline sync queue that preserves captured scans, supports pause/resume/retry, and persists even after the app is closed. | | | | | |
| **1.4** | On the scanning laptop/PC, the Batch Scanning Station and Scan Watcher program automatically detect, ingest, and upload newly scanned pages from a document scanner. | | | | | |
| **1.5** | The system imports evaluation responses directly from a Google Sheet (supporting legacy and updated column layouts) and reports matched rows and unmapped row errors. | | | | | |
| **1.6** | The multi-channel capture workflows eliminate the need for manual, keystroke-by-keystroke typing of evaluation ratings into spreadsheets. | | | | | |

### Objective 2: AI-Assisted Extraction & Validation Pipeline
*To implement an AI-assisted extraction pipeline that reads ratings through OpenCV-based Optical Mark Recognition and handwritten fields through Google Gemini, cross-checks both readings, and routes low-confidence or rule-violating forms to human-in-the-loop validation, targeting at least 85% extraction accuracy.*

| No. | Statement | 5 | 4 | 3 | 2 | 1 |
| :---: | :--- | :---: | :---: | :---: | :---: |
| **2.1** | The OpenCV-based Optical Mark Recognition (OMR) accurately detects filled rating marks (recognizing checks and slashes while treating invalid marks as blank). | | | | | |
| **2.2** | The Google Gemini AI model accurately transcribes handwritten header fields (instructor name, subject code, semester, and student remarks). | | | | | |
| **2.3** | The system automatically cross-validates mark readings against AI interpretations and flags discrepancies for human checking. | | | | | |
| **2.4** | The system automatically discards invalid form images, forms with fewer than the minimum required answered items, and forms whose stamp number was already scanned in the same term. | | | | | |
| **2.5** | The web-based human-in-the-loop review station enables staff to compare scanned original images side-by-side with extracted values, correct marks using interactive pickers, and approve or reject submissions. | | | | | |
| **2.6** | The automated extraction and verification pipeline achieves high extraction accuracy (targeting at least 85%) during routine processing. | | | | | |

### Objective 3: Automated Metric Computation, Reporting & AI Remarks Analysis
*To automate the computation of per-item, category (Management, Performance), and overall mean ratings with their descriptive equivalents, and to generate evaluation reports and AI-assisted analysis of student remarks (sentiment, themes, and word cloud).*

| No. | Statement | 5 | 4 | 3 | 2 | 1 |
| :---: | :--- | :---: | :---: | :---: | :---: |
| **3.1** | The system computes per-item means, category means (Management and Performance), and overall mean ratings automatically without manual intervention. | | | | | |
| **3.2** | The computation algorithm correctly ignores blank or skipped items instead of penalizing them as zero. | | | | | |
| **3.3** | The system automatically displays the correct institutional descriptive rating (Outstanding to Unsatisfactory) for each instructor's mean rating. | | | | | |
| **3.4** | The system allows authorized users to view and download official evaluation summary reports as print-ready PDF documents. | | | | | |
| **3.5** | The system displays longitudinal performance trends across different subjects and historical terms. | | | | | |
| **3.6** | The AI sentiment analysis accurately classifies student open-ended remarks into Positive, Neutral, and Critical sentiment categories. | | | | | |
| **3.7** | The AI qualitative engine summarizes student remarks by extracting key positive themes, constructive improvement insights, and a concise 'What your students are saying' summary. | | | | | |
| **3.8** | The system generates an intuitive, brand-color-themed word cloud highlighting the most prominent terms from student feedback. | | | | | |
| **3.9** | The system automatically filters or masks abusive, rude, or sexually inappropriate words before remarks are displayed, preserving constructive feedback. | | | | | |

### Objective 4: n8n Workflow Automation, Dashboards & Intervention Monitoring
*To orchestrate end-to-end processing through n8n workflow automation and provide role-based dashboards, alerts, and intervention monitoring for SAO-Admins, SAO-Staff, Department Heads, and Instructors.*

| No. | Statement | 5 | 4 | 3 | 2 | 1 |
| :---: | :--- | :---: | :---: | :---: | :---: |
| **4.1** | End-to-end processing—from form upload to metric computation and database persistence—is fully automated and orchestrated through n8n workflows. | | | | | |
| **4.2** | The system provides dedicated, role-tailored dashboards for SAO-Admins, SAO-Staff, Department Heads, and Instructors. | | | | | |
| **4.3** | The system automatically dispatches real-time push notifications and alerts to instructors and their Department Head whenever an instructor's mean rating drops below the 3.0 threshold. | | | | | |
| **4.4** | The system sends prompt alerts to the instructor and Department Head when critical student feedback requiring attention is detected. | | | | | |
| **4.5** | The SAO-Admin dashboard displays live processing metrics, including auto-processed volumes, pending manual review counts, correction figures, and staff productivity. | | | | | |
| **4.6** | The Department Head module allows supervisors to monitor departmental faculty rankings, inspect subject analytics, and draft and issue structured intervention reports. | | | | | |

### Objective 5: System Security, RBAC, Data Privacy & Audit Logging
*To secure evaluation data through approval-based accounts, role-based access control, acceptance of the Non-Disclosure Agreement and Data Privacy Act terms, and audit logging, in compliance with RA 10173.*

| No. | Statement | 5 | 4 | 3 | 2 | 1 |
| :---: | :--- | :---: | :---: | :---: | :---: |
| **5.1** | New users are required to accept the Non-Disclosure Agreement (NDA) and Data Privacy Act (DPA) terms upon registration. | | | | | |
| **5.2** | The system enforces an approval-based registration workflow, keeping new accounts pending until reviewed and approved by the SAO-Admin. | | | | | |
| **5.3** | The system strictly restricts each user to view and interact only with screens and data belonging to their authorized role. | | | | | |
| **5.4** | The mobile app and web portal provide secure login using institutional email or university ID credentials. | | | | | |
| **5.5** | The web application protects against brute-force attacks by rate-limiting repeated failed login attempts. | | | | | |
| **5.6** | The system records account changes, batch operations, review approvals, and rejections in a tamper-evident Security Audit Log. | | | | | |
| **5.7** | The system enables administrators to manage user accounts, including approving registrations, disabling accounts, and re-enabling access. | | | | | |
| **5.8** | The system complies with privacy standards and storage policies by automatically purging stored scanned form images after 90 days. | | | | | |

### Overall Objective
*Overall assessment of the system's achievement of its research and development objectives.*

| No. | Statement | 5 | 4 | 3 | 2 | 1 |
| :---: | :--- | :---: | :---: | :---: | :---: |
| **O.1** | Overall, the iEvaluate system successfully achieves its stated project objectives and provides an effective, secure, and automated evaluation workflow. | | | | | |

## Part III: System Usability Scale (SUS)
*Standardized 10-item instrument for usability and learnability evaluation (Scale: 5 – Strongly Agree to 1 – Strongly Disagree)*

| No. | Statement | 5 | 4 | 3 | 2 | 1 |
| :---: | :--- | :---: | :---: | :---: | :---: |
| **1** | I think that I would like to use iEvaluate frequently. | | | | | |
| **2** | I found iEvaluate unnecessarily complex. | | | | | |
| **3** | I thought iEvaluate was easy to use. | | | | | |
| **4** | I think that I would need the support of a technical person to be able to use iEvaluate. | | | | | |
| **5** | I found the various functions in iEvaluate were well integrated. | | | | | |
| **6** | I thought there was too much inconsistency in iEvaluate. | | | | | |
| **7** | I would imagine that most people would learn to use iEvaluate very quickly. | | | | | |
| **8** | I found iEvaluate very cumbersome to use. | | | | | |
| **9** | I felt very confident using iEvaluate. | | | | | |
| **10** | I needed to learn a lot of things before I could get going with iEvaluate. | | | | | |

## Part IV: Technology Acceptance Model (TAM) Evaluation
*Assessing Perceived Usefulness (PU) and Perceived Ease of Use (PEOU) based on Davis (1989)*

### A. Perceived Usefulness (PU)
| No. | Statement | 5 | 4 | 3 | 2 | 1 |
| :---: | :--- | :---: | :---: | :---: | :---: |
| **1** | Using iEvaluate enables faculty evaluation tasks to be completed much faster compared to manual paper encoding and tallying. | | | | | |
| **2** | The system improves overall productivity in managing, compiling, and analyzing instructor performance data. | | | | | |
| **3** | Using iEvaluate enhances the timeliness and accessibility of evaluation results for instructors and administrators. | | | | | |
| **4** | The AI-assisted extraction and automated mean computation reduce errors and improve the accuracy of evaluation records. | | | | | |
| **5** | The AI sentiment analysis, theme extraction, and intervention monitoring provide valuable, actionable insights for academic improvement. | | | | | |
| **6** | Overall, I find iEvaluate highly useful for modernizing the faculty evaluation and feedback process. | | | | | |

### B. Perceived Ease of Use (PEOU)
| No. | Statement | 5 | 4 | 3 | 2 | 1 |
| :---: | :--- | :---: | :---: | :---: | :---: |
| **1** | Learning how to operate iEvaluate (mobile app and web portal) is easy and straightforward for me. | | | | | |
| **2** | I find it easy to navigate between screens, view dashboards, and access relevant features. | | | | | |
| **3** | My interaction with iEvaluate is clear, intuitive, and understandable. | | | | | |
| **4** | The system provides an organized interface and clear visual guidance (such as camera level indicators, blur alerts, and SAST guidelines) that make tasks easy to complete. | | | | | |
| **5** | I can easily become proficient in using iEvaluate without requiring extensive assistance or technical supervision. | | | | | |
| **6** | Overall, I find iEvaluate easy, convenient, and user-friendly to operate. | | | | | |

## Part V: Qualitative Open-Ended Feedback

**1. What do you like most about iEvaluate, and which feature was the most helpful or time-saving?**

```


```

**2. What was the most frustrating part of using iEvaluate, or which feature needs improvement?**

```


```

**3. What additional features, functions, or enhancements would you suggest for future iterations of iEvaluate?**

```


```

**Respondent's Signature:** ___________________________________ &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; **Date:** ______________________
