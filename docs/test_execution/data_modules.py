# -*- coding: utf-8 -*-
"""Test-execution data for the five iEvaluate pages/modules."""

P, F, B = "PASS", "FAIL", "BLOCKED"

MODULES = [
# =====================================================================  1
dict(
  no=1, code="TER-01",
  page="Login Page (Authentication)",
  file="lib/login_screen.dart",
  entry="App launch with no active session",
  role="All roles (Instructor, Department Head, SAO Staff, SAO Administrator)",
  objective=("Confirm that a valid user of any role is authenticated and routed to the "
             "dashboard of that role only, and that every invalid, unauthorised or "
             "abusive sign-in path is refused with a message the user can act on."),
  scope_in=("Splash-to-login routing, credential entry, password masking, the NDA/DPA "
            "gate, successful authentication, role-based routing, empty-field "
            "validation, invalid credentials, rate limiting, deactivated accounts and "
            "password reset."),
  scope_out=("Biometric sign-in (not implemented in this build) and SSO. Session "
             "persistence across a device reboot is covered by the Dashboard report."),
  cases=[
    dict(id="TC-LGN-01", scen="Login screen is presented on a cold launch",
      steps="1. Force-stop the app and clear the running task.\n"
            "2. Tap the iEvaluate icon and wait for the splash to resolve.",
      data="No active session on the device",
      exp='Login screen appears headed "iEvaluate Portal" with the subtitle '
          '"Secure access to academic evaluation tools." and the CTU seal.',
      act="Login screen rendered in 2.1 s. Heading, subtitle and seal all match the "
          "specification character for character.", st=P, dfr="-"),
    dict(id="TC-LGN-02", scen="Identifier field accepts an ID or an institutional email",
      steps="1. Tap the first field and read its placeholder.\n"
            "2. Type a university ID, clear it, then type an institutional email.",
      data="ID 2021-00318; email rlicayan@ctu.edu.ph",
      exp='Placeholder reads "University ID or Institutional Email". Both formats are '
          'accepted without a client-side format error.',
      act="Placeholder correct. Both the numeric ID and the email were accepted and "
          "retained in the field.", st=P, dfr="-"),
    dict(id="TC-LGN-03", scen="Password masking and reveal toggle",
      steps="1. Type a password into the second field.\n"
            "2. Tap the eye icon at the right of the field.\n"
            "3. Tap the eye icon a second time.",
      data="Valid instructor password (not recorded)",
      exp="Password is masked by default. The first tap reveals the characters, the "
          "second re-masks them. Focus and caret position are preserved.",
      act="Behaved exactly as expected across three repetitions. No character loss on "
          "toggle.", st=P, dfr="-"),
    dict(id="TC-LGN-04", scen="NDA and DPA agreement dialog is reachable and dismissible",
      steps='1. Tap the information icon beside "I agree to the NDA and DPA".\n'
            "2. Scroll the dialog to its end.\n"
            "3. Dismiss the dialog.",
      data="n/a",
      exp='A dialog titled "NDA & DPA Agreements" opens, scrolls to the end of both '
          'agreements and closes without altering the checkbox state.',
      act="Dialog opened, scrolled and closed. The checkbox state was unchanged after "
          "dismissal.", st=P, dfr="-"),
    dict(id="TC-LGN-05", scen="Successful sign-in with valid instructor credentials",
      steps="1. Enter the institutional email and password.\n"
            '2. Tick "I agree to the NDA and DPA".\n'
            '3. Tap "Sign In".',
      data="Active instructor account, role = INSTRUCTOR",
      exp='Authentication succeeds and the app routes to "My Dashboard" showing the '
          'bottom tabs Dashboard, My Subjects, Feedback and Past Terms.',
      act='Signed in within 3.4 s and landed on "My Dashboard" with all four tabs '
          "present. No other role's dashboard was reachable.", st=P, dfr="-"),
    dict(id="TC-LGN-06", scen="Role-based routing for the remaining three roles",
      steps="1. Sign out.\n"
            "2. Repeat TC-LGN-05 with a Department Head, an SAO Staff and an SAO "
            "Administrator account in turn.",
      data="One active account per role",
      exp="Each account reaches only its own dashboard: the Executive Overview, the "
          "SAO Staff shift dashboard and the SAO system overview respectively.",
      act="All three routed correctly. No cross-role screen was reachable by tab, "
          "drawer or back gesture.", st=P, dfr="-"),
    dict(id="TC-LGN-07", scen="Both credential fields left empty",
      steps="1. Leave both fields blank.\n"
            "2. Tick the NDA checkbox.\n"
            '3. Tap "Sign In".',
      data="Empty strings",
      exp='Sign-in is refused with "Please enter your ID/email and password." and no '
          "network call is made.",
      act="Refused with the exact message. No authentication request was issued.",
      st=P, dfr="-"),
    dict(id="TC-LGN-08", scen="NDA / DPA consent not given",
      steps="1. Enter valid credentials.\n"
            '2. Leave "I agree to the NDA and DPA" unticked.\n'
            '3. Tap "Sign In".',
      data="Valid instructor credentials",
      exp='Refused with "Please agree to the NDA and DPA to log in." and no session '
          "is created.",
      act="Refused with the exact message. No session token was written to secure "
          "storage.", st=P, dfr="-"),
    dict(id="TC-LGN-09", scen="Single invalid-password attempt",
      steps="1. Enter a valid email with a deliberately wrong password.\n"
            '2. Tap "Sign In" once.',
      data='Valid email, password "wrongpass1"',
      exp="Sign-in fails with an invalid-credentials message and the typed email is "
          "NOT cleared, so the user need not retype it.",
      act="Failed as expected and the email persisted in the field.", st=P, dfr="-"),
    dict(id="TC-LGN-10", scen="Rate limiter trips after repeated failures",
      steps="1. Repeat TC-LGN-09 until the attempt limit is reached.\n"
            "2. Observe the countdown and attempt a further sign-in.",
      data="Throwaway instructor account, wrong password x5",
      exp='The limit blocks further attempts with "Too many failed attempts. Please '
          'wait Xm Ys before trying again." carrying a live countdown.',
      act="Blocked on the 5th attempt. The countdown rendered live and decremented "
          "each second; sign-in stayed refused until it expired.", st=P, dfr="-"),
    dict(id="TC-LGN-11", scen="Deactivated account is denied",
      steps="1. Enter the credentials of an account deactivated by the "
            "administration.\n"
            '2. Tap "Sign In".',
      data="Deactivated instructor account",
      exp='Denied with "Your account has been deactivated by the administration." The '
          "dashboard is never reached.",
      act="Denied with the exact message. Routing did not occur.", st=P, dfr="-"),
    dict(id="TC-LGN-12", scen="Forgot-password reset completes end to end",
      steps='1. Tap "Forgot Password?".\n'
            "2. Complete the emailed reset.\n"
            "3. Return and sign in with the new password.",
      data="Institutional mailbox of the test account",
      exp="Reset mail arrives, the new password is accepted, and the app confirms with "
          '"Password updated successfully! Please log in with your new password."',
      act="Reset mail arrived in 41 s. The new password was accepted and the "
          "confirmation banner appeared. The old password was correctly rejected "
          "afterwards.", st=P, dfr="-"),
    dict(id="TC-LGN-13", scen="Sign-in attempted with no network connectivity",
      steps="1. Enable airplane mode.\n"
            '2. Enter valid credentials and tap "Sign In".',
      data="Valid instructor credentials, radio off",
      exp="A connectivity notice is shown, the app does not crash or hang, and the "
          "attempt can be retried once the radio is restored.",
      act="NOT EXECUTED. The campus test handset could not be taken off the network "
          "during the booked window without losing the remote debugging session. "
          "Re-scheduled to the next regression cycle.", st=B, dfr="-"),
  ],
  defects=[],
  notes=["No defect was raised against this page. The authentication and rate-limiting "
         "paths behaved to specification on every executed case.",
         "TC-LGN-10 must be run on a throwaway account: the limiter is real and locks "
         "the account for the full duration of the countdown."],
),
# =====================================================================  2
dict(
  no=2, code="TER-02",
  page="Registration / Sign-Up Page",
  file="lib/signup_screen.dart",
  entry='Login screen -> "Need an account?" -> "Register"',
  role="Prospective user (Instructor, Department Head, SAO Staff, SAO Administrator)",
  objective=("Confirm that the four-step registration wizard collects and validates "
             "personal, academic and credential data, enforces the "
             "one-department-head rule and the duplicate checks, and leaves the account "
             "pending SAO Administrator approval rather than active."),
  scope_in=("Step navigation, role selection, live availability checks on name, ID and "
            "email, department-head uniqueness, address and employment validation, "
            "password strength rules, the NDA/DPA gate, submission and the "
            "pending-approval confirmation."),
  scope_out=("The approval action itself, which belongs to the SAO Administrator "
             "module, and the notification e-mail template."),
  cases=[
    dict(id="TC-REG-01", scen="Registration wizard is reachable and step 1 renders",
      steps='1. From the Login screen tap "Register".\n'
            "2. Read the step indicator and the section heading.",
      data="n/a",
      exp='The wizard opens on "Personal Information" as step 1 of 4, with the '
          "remaining steps Academic Information, Create Password and Review & Terms.",
      act="Opened on Personal Information with the four-step indicator rendered "
          "correctly.", st=P, dfr="-"),
    dict(id="TC-REG-02", scen="Role selection is mandatory before continuing",
      steps='1. Leave "I am registering as" unset.\n'
            '2. Tap "Continue".',
      data="No role chosen",
      exp='Progress is refused with "Please choose what you are registering as".',
      act="Refused with the exact message; the wizard stayed on step 1.", st=P,
      dfr="-"),
    dict(id="TC-REG-03", scen="All four roles are offered with the correct labels",
      steps='1. Open the "I am registering as" selector and read every option.',
      data="n/a",
      exp='The list offers "Instructor", "Department Head", "SAO Staff (Data '
          'Gatherer)" and "SAO Administrator".',
      act="All four options were present and correctly labelled.", st=P, dfr="-"),
    dict(id="TC-REG-04", scen="Live duplicate check on the applicant name",
      steps="1. Enter a first and last name already held by an approved user.\n"
            "2. Enter a name that is not yet in use.",
      data='Existing "Rodz Licayan"; new "Juan Cruz"',
      exp='The taken name is rejected with "Someone is already registered with this '
          'exact name"; the free name reports "Juan Cruz is available".',
      act="Both outcomes were observed. The check debounced correctly and did not "
          "fire on every keystroke.", st=P, dfr="-"),
    dict(id="TC-REG-05",
      scen="Live duplicate check on the ID and the institutional email",
      steps="1. Enter an ID already registered, then a free one.\n"
            "2. Enter an email already registered, then a free one.",
      data="Registered ID and email of an approved account",
      exp='Taken values report "This <ID label> is already registered" and "This email '
          'is already registered"; free values report the matching "is available" '
          "messages.",
      act="All four messages appeared correctly against the live directory.", st=P,
      dfr="-"),
    dict(id="TC-REG-06", scen="Address fields are validated individually",
      steps="1. Leave the house number / street blank and continue.\n"
            "2. Fill it, clear the barangay line and continue.",
      data='Address "Lamacan, Argao, Cebu"',
      exp='Each omission is refused by its own message: "House number / street is '
          'required" and "Barangay is required".',
      act="Both messages appeared against the correct field, and Continue stayed "
          "blocked until each was supplied.", st=P, dfr="-"),
    dict(id="TC-REG-07", scen="Department is mandatory on the academic step",
      steps="1. Reach Academic Information without selecting a department.\n"
            '2. Tap "Continue".',
      data="No department chosen",
      exp='Refused with "Please select a department". The selector lists the '
          "departments held in the system, and free text is accepted for one that is "
          "not listed.",
      act="Refused with the exact message. The list loaded from the live department "
          "table and the free-text fallback worked.", st=P, dfr="-"),
    dict(id="TC-REG-08", scen="One-department-head rule is enforced at registration",
      steps='1. Choose the role "Department Head".\n'
            "2. Select a department that already has an assigned head.\n"
            "3. Select a department that has none.",
      data="CTE (head assigned); a department with no head",
      exp='While the check runs the field reads "Checking if this department already '
          'has a head..."; a department that already has one is refused with "This '
          'department already has a head". A vacant department is accepted.',
      act="The interim message appeared and the occupied department was refused. The "
          "vacant department was accepted and the wizard advanced.", st=P, dfr="-"),
    dict(id="TC-REG-09", scen="Employment status is mandatory for instructor roles",
      steps='1. Choose "Instructor" and leave Employment Status unset.\n'
            '2. Tap "Continue", then select "Instructor - Resident (Full-Time)".',
      data="FULL-TIME / PART-TIME",
      exp='Refused with "Please select an employment status" until Resident '
          "(Full-Time) or Non-Resident (Part-Time) is chosen.",
      act="Refused as expected, then advanced once Full-Time was selected. The stored "
          'value was "FULL-TIME".', st=P, dfr="-"),
    dict(id="TC-REG-10", scen="Password strength rules are enforced and displayed live",
      steps='1. On "Create Password" type a weak password and read the checklist.\n'
            "2. Build up to a compliant password.\n"
            "3. Enter a different confirmation value.",
      data='Weak "abc"; compliant "Passw0rd_"',
      exp='The four rules "At least 8 characters", "One uppercase letter", "One '
          'number" and "One special character (! @ # - _ ...)" tick individually as '
          'they are met. A mismatched confirmation is refused with "Passwords do not '
          'match".',
      act="All four indicators ticked live as each rule was satisfied. The mismatch "
          "was refused with the exact message.", st=P, dfr="-"),
    dict(id="TC-REG-11", scen="Agreement must be read before it can be accepted",
      steps='1. On "Review & Terms" tap the agreement checkbox without opening the '
            "agreement.\n"
            '2. Open "NDA and Data Privacy Agreement", read to the end, then tick.',
      data="n/a",
      exp='Before the agreement is opened the control reads "Tap to read. Required '
          'before you can agree." and ticking is refused with "Read the agreement '
          'above first". After reading, the checkbox accepts the tick and the link '
          'changes to "Read - tap to view again".',
      act="Ticking was refused before reading and accepted afterwards. The link label "
          "changed as specified.", st=P, dfr="-"),
    dict(id="TC-REG-12", scen="Review step reflects the data entered",
      steps='1. Tap "Tap to review your details" and compare every field with what '
            "was entered.",
      data="Full instructor application",
      exp='The summary shows the composed full name, the role line "Registering as '
          '<role>", department, employment status, address and institutional email, '
          "all matching the wizard input.",
      act='Every field matched. The role line read "Registering as Instructor."',
      st=P, dfr="-"),
    dict(id="TC-REG-13", scen="Submission leaves the account pending approval",
      steps='1. Tap "Register".\n'
            "2. Read the confirmation screen.\n"
            '3. Tap "Return to Login" and try to sign in with the new credentials.',
      data="Complete instructor application",
      exp='A "Registration Submitted!" screen explains that the account is waiting for '
          "an SAO Administrator to approve it and that notifications go to the "
          "submitted address. Sign-in with the new credentials is refused until "
          "approval.",
      act="The confirmation screen was shown with the correct e-mail address "
          "interpolated. Sign-in was correctly refused, and the record appeared in "
          "the SAO Administrator's pending queue.", st=P, dfr="-"),
    dict(id="TC-REG-14", scen="Duplicate submission of an already-pending application",
      steps="1. Re-run TC-REG-13 with the identical ID and e-mail.",
      data="Same application submitted twice",
      exp="The second submission is refused by the duplicate checks before it can be "
          "written, and no second pending record is created.",
      act="The ID and e-mail checks both reported the value as already registered and "
          "blocked the wizard on step 1. Only one pending record exists.", st=P,
      dfr="-"),
  ],
  defects=[],
  notes=["No defect was raised against this page.",
         "TC-REG-13 and TC-REG-14 write to the live pending-approvals queue. Every "
         "record created during this run was removed by the SAO Administrator "
         "afterwards, verified in the Users tab."],
),
# =====================================================================  3
dict(
  no=3, code="TER-03",
  page="Instructor - My Dashboard Page",
  file="lib/instructor/ (dashboard) and lib/core/navigation/main_scaffold.dart",
  entry='Sign in as Instructor -> tab "Dashboard"',
  role="Instructor",
  objective=("Confirm that the instructor's landing page presents the correct "
             "evaluation scores for the active term, reacts to a term change, surfaces "
             "notices and interventions, and that the surrounding navigation identifies "
             "the signed-in account consistently."),
  scope_in=("Score cards, sync state, notices and intervention banners, "
            "pull-to-refresh, term reactivity, bottom-tab navigation, the side drawer "
            "identity block and entry-point coverage of every instructor screen."),
  scope_out=("The Official Evaluation Report and the Student Feedback screens, each "
             "covered by its own report."),
  cases=[
    dict(id="TC-DSH-01", scen="Dashboard renders the active term's scores",
      steps="1. Sign in as Instructor.\n"
            "2. Read the score cards and the term label.",
      data="Active term: 2nd Semester, 2027-2028",
      exp="The overall score, the per-category breakdown and the term label all match "
          "the values held for the signed-in instructor in the active term.",
      act="Scores and term label matched the back-end record exactly.", st=P, dfr="-"),
    dict(id="TC-DSH-02", scen="Pull-to-refresh re-reads the dashboard",
      steps="1. Pull down on the dashboard and release.\n"
            "2. Wait for the indicator to clear.",
      data="n/a",
      exp="A refresh indicator is shown, the data is re-fetched, and the cards settle "
          "on the same or newer values without flicker or duplication.",
      act="Refreshed in 1.6 s. Values were re-read and no duplicate cards appeared "
          "over ten repetitions.", st=P, dfr="-"),
    dict(id="TC-DSH-03", scen="Dashboard reacts to a change of active term",
      steps="1. Have the SAO Administrator switch the active academic term.\n"
            "2. Return to the instructor device and refresh.",
      data="Switch from 2nd Sem 2027-2028 to 1st Sem 2027-2028",
      exp="The dashboard re-reads against the new active term: the label updates and "
          "the scores change to that term's values without a re-install or a "
          "re-login.",
      act="The label and the scores both updated on the first refresh after the "
          "switch.", st=P, dfr="-"),
    dict(id="TC-DSH-04", scen="Notices and intervention banners are surfaced",
      steps="1. Have the Department Head issue an intervention for this instructor.\n"
            "2. Refresh the instructor dashboard.",
      data="One intervention report raised cross-role",
      exp="The intervention appears on the dashboard as a notice the instructor can "
          "open and read, carrying the department head's text.",
      act="The intervention appeared after one refresh with the correct author and "
          "body text.", st=P, dfr="-"),
    dict(id="TC-DSH-05", scen="Bottom tabs reach every instructor screen",
      steps="1. Visit Dashboard, My Subjects, Feedback and Past Terms in turn, then "
            "return to Dashboard.",
      data="n/a",
      exp="Each tab loads its own screen, the selected tab is highlighted, and "
          "returning to Dashboard restores its scroll position.",
      act="All four tabs loaded correctly and the scroll position was restored.",
      st=P, dfr="-"),
    dict(id="TC-DSH-06", scen="Drawer avatar initials identify the signed-in account",
      steps="1. Open the side drawer and read the avatar initials.\n"
            '2. Open "Account Settings" and read the profile card initials.\n'
            "3. Compare the two.",
      data='Signed-in instructor "Rodz Harvey Licayan"',
      exp="Both places show the same initials for the same account, derived from the "
          "first and last name.",
      act='FAIL. The drawer showed "RH" (the first two words, so the middle name) '
          'while the Settings profile card showed "RL". The one account appeared to '
          "belong to two different people depending on the screen. Raised as DEF-05, "
          "fixed on 31/08/2026, awaiting re-test.", st=F, dfr="DEF-05"),
    dict(id="TC-DSH-07", scen="Subject cards open the matching subject detail",
      steps='1. Open "My Subjects" and tap each subject card.\n'
            "2. Confirm the detail screen matches the card tapped.",
      data="Assigned subjects for the active term",
      exp="Every card opens the detail for that subject only, with the same code, "
          "title and score as the card.",
      act="All assigned subjects opened the correct detail screen.", st=P, dfr="-"),
    dict(id="TC-DSH-08", scen="Performance trend chart includes the active term",
      steps='1. Open "Past Terms" and read the Performance Trend chart.\n'
            "2. Scroll the chart horizontally to its right-hand end.",
      data="Term history of the signed-in instructor",
      exp="Every term the instructor has data for is plotted, including the active "
          "term, which sits at the right-hand end of a horizontally scrolling axis.",
      act="Initially appeared to be missing the active term, because the newest "
          'VISIBLE bar was "1st 26-27". Scrolling right showed the term present and '
          "correctly selected. Suspected defect investigated and WITHDRAWN; recorded "
          "here because the misreading is easy to repeat.", st=P, dfr="-"),
    dict(id="TC-DSH-09",
      scen="Session survives backgrounding and is cleared on sign-out",
      steps="1. Background the app for five minutes and reopen it.\n"
            "2. Sign out from the drawer, then press the back gesture.",
      data="n/a",
      exp="The session survives backgrounding and the dashboard is restored. After "
          "sign-out the Login screen is shown and the back gesture cannot return to "
          "any authenticated screen.",
      act="The session survived backgrounding. After sign-out the back gesture stayed "
          "on the Login screen and the stored token was cleared.", st=P, dfr="-"),
    dict(id="TC-DSH-10", scen="Every instructor screen has a reachable entry point",
      steps="1. Enumerate the instructor screens in the codebase.\n"
            "2. Reach each one from the running app.",
      data="Static review plus a device walkthrough",
      exp="Every instructor screen shipped in the build can be reached through the "
          "tabs, the drawer or a card tap.",
      act="FAIL. lib/instructor/term_subjects_screen.dart is never instantiated "
          "anywhere in the codebase - Past Terms renders its own subject list inline. "
          "It is dead code, so no acceptance test can cover it. Raised as DEF-07, "
          "still OPEN.", st=F, dfr="DEF-07"),
  ],
  defects=[
    dict(id="DEF-05", sev="LOW", pri="Low",
      desc='Avatar initials differ between the side drawer ("RH") and the Account '
           'Settings profile card ("RL") for the same signed-in instructor, because '
           "the drawer took the first TWO WORDS of the display name and so picked up "
           "the middle name.",
      root="lib/core/navigation/main_scaffold.dart composed the initials from the "
           "first two words of the full display name, while Settings correctly used "
           "first_name + last_name.",
      fix="A new _initialsOf() helper takes the FIRST and LAST word of the name, "
          "skipping any middle name. A single-word name yields one letter and an "
          'empty name still yields "?". Settings was already correct and is '
          "unchanged. flutter analyze reports no issues on the file.",
      st="FIXED 31/08/2026, PENDING RE-TEST", tc="TC-DSH-06"),
    dict(id="DEF-07", sev="LOW (code hygiene)", pri="Low",
      desc="lib/instructor/term_subjects_screen.dart is unreachable. Nothing in the "
           "codebase instantiates it and Past Terms renders its own subject list "
           "inline, so the file is dead code that no acceptance test can cover.",
      root="An earlier navigation design was replaced by the inline list in Past "
           "Terms, and the orphaned screen was never removed.",
      fix="Not yet applied. Either wire up an entry point or delete the file.",
      st="OPEN", tc="TC-DSH-10"),
  ],
  notes=["DEF-05 must be re-tested by re-running TC-DSH-06 and confirming the drawer "
         "and the Settings profile card show the same two letters.",
         "TC-DSH-08 records a WITHDRAWN suspected defect. The Performance Trend chart "
         "scrolls horizontally and the newest terms sit off-screen until scrolled, so "
         "a reader who does not scroll will wrongly conclude the active term is "
         "missing. Kept in this report so the same misreading is not raised again."],
),
# =====================================================================  4
dict(
  no=4, code="TER-04",
  page="Instructor - Student Feedback Page",
  file="lib/instructor/student_feedback_screen.dart",
  entry='Instructor dashboard -> tab "Feedback"',
  role="Instructor",
  objective=("Confirm that anonymised student feedback is presented with its sentiment "
             "breakdown, AI-generated insights, word cloud and direct quotes, and that "
             "every element stays legible inside its panel on the target handset."),
  scope_in=("Sentiment tone bands, AI insight generation through the n8n workflow, the "
            "AI word cloud, the direct-quotes list and its counter, empty states, and "
            "layout robustness at larger system font sizes."),
  scope_out=("The sentiment model itself and the accuracy of its classification, which "
             "are evaluated separately from acceptance testing."),
  cases=[
    dict(id="TC-FBK-01", scen="Feedback screen loads for the active term",
      steps='1. Sign in as Instructor and open the "Feedback" tab.',
      data="Active-term feedback for the signed-in instructor",
      exp="The screen loads the active term's feedback with the sentiment summary, AI "
          "insights, word cloud and direct quotes sections all present.",
      act="All four sections rendered within 2.8 s.", st=P, dfr="-"),
    dict(id="TC-FBK-02", scen="Sentiment breakdown totals the responses received",
      steps="1. Read the positive / neutral / negative counts.\n"
            "2. Compare the sum with the response count held for the term.",
      data="Anonymised responses for the active term",
      exp="The three bands sum exactly to the number of responses recorded, and the "
          "percentages are consistent with the counts.",
      act="Counts summed correctly and the percentages matched to one decimal place.",
      st=P, dfr="-"),
    dict(id="TC-FBK-03", scen="Feedback is anonymous",
      steps="1. Read every quote and insight on the screen.\n"
            "2. Look for any student name, ID or identifying reference.",
      data="Full feedback set for the term",
      exp="No student name, student number or other identifier appears anywhere on "
          "the screen.",
      act="No identifying data was present in any quote, insight or tooltip.", st=P,
      dfr="-"),
    dict(id="TC-FBK-04", scen="AI insights are generated and displayed",
      steps="1. Read the AI insights panel.\n"
            "2. Refresh and confirm the panel repopulates.",
      data="n8n workflow endpoint, live",
      exp="The panel shows generated insights derived from the term's feedback and "
          "repopulates on refresh without duplicating earlier text.",
      act="Insights were generated on each load and did not duplicate across five "
          "refreshes.", st=P, dfr="-"),
    dict(id="TC-FBK-05", scen="Word cloud keeps every term inside the panel",
      steps='1. Open "AI Word Cloud".\n'
            "2. Pull to refresh several times so more than one shuffle is checked.\n"
            "3. Inspect the right-hand edge of the dark panel on each shuffle.",
      data="Feedback term set; the cloud reshuffles on each load",
      exp="Every word, rotated or upright, is drawn wholly inside the dark panel and "
          "is readable on every shuffle.",
      act='FAIL. The rotated term "Fair grading" ran past the right edge of the panel '
          "and was cut off mid-word. Because the cloud reshuffles on each load, WHICH "
          "word was clipped changed between refreshes, so the fault was intermittent "
          "rather than tied to one term. Raised as DEF-02, fixed on 31/08/2026, "
          "awaiting re-test.", st=F, dfr="DEF-02"),
    dict(id="TC-FBK-06", scen="Direct quotes list and its counter",
      steps='1. Scroll to "Direct Quotes" and read the "N Comments" counter.\n'
            "2. Count the quotes rendered in the list.\n"
            "3. Repeat at the largest system font size the device offers.",
      data="Device font scale 1.0, then maximum",
      exp="The counter equals the number of quotes listed, and both the heading and "
          "the counter stay fully inside the screen at every font size.",
      act='FAIL. The "N Comments" counter reached the right edge of the display with '
          "no padding. At the tested count it stayed readable, but a wider value or a "
          "larger system font size would have clipped it. The count itself was "
          "correct. Raised as DEF-04, fixed on 31/08/2026, awaiting re-test.", st=F,
      dfr="DEF-04"),
    dict(id="TC-FBK-07", scen="Quotes are readable in full",
      steps="1. Open the longest quote in the list.\n"
            "2. Confirm it is not truncated.",
      data="Longest anonymised comment in the term set",
      exp="Long comments wrap or expand rather than being cut off, so the instructor "
          "can read the whole comment.",
      act="The longest comment wrapped and was fully readable.", st=P, dfr="-"),
    dict(id="TC-FBK-08", scen="Empty state for a term with no feedback",
      steps="1. Switch to a historical term that has no recorded feedback.",
      data="Term with zero responses",
      exp="An explanatory empty state is shown instead of empty panels, a zero "
          "sentiment chart or an error.",
      act="A clear empty state was shown for the sentiment, cloud and quotes "
          "sections.", st=P, dfr="-"),
    dict(id="TC-FBK-09", scen="Screen behaves when the AI workflow is unreachable",
      steps="1. Point the build at an unreachable n8n endpoint.\n"
            "2. Open the Feedback tab.",
      data="Invalid workflow URL",
      exp="The AI insights panel degrades to an error or retry state, while the "
          "sentiment counts and the quotes, which do not depend on the workflow, "
          "still render.",
      act="NOT EXECUTED. Re-pointing the workflow endpoint requires a rebuild against "
          "a staging configuration that was not available in the booked window. "
          "Carried to the next regression cycle.", st=B, dfr="-"),
  ],
  defects=[
    dict(id="DEF-02", sev="MEDIUM", pri="High",
      desc='In "AI Word Cloud" the rotated term "Fair grading" ran past the right edge '
           "of the dark panel and was cut off mid-word, so it could not be read. "
           "Intermittent, because the cloud reshuffles on every load and a different "
           "word was clipped each time.",
      root="Nothing bounded a word to the panel. The words sit in a Wrap inside a "
           "fixed-padding Container and each word was a bare Text with no width "
           "constraint. RotatedBox swaps the constraints it passes down, so a rotated "
           "word's own text width becomes its vertical extent, and neither extent was "
           "capped.",
      fix="The word area is now wrapped in a LayoutBuilder, so the panel's real inner "
          "width is known at layout time. Every word is bounded by "
          "ConstrainedBox(maxWidth: that width) and drawn through "
          "FittedBox(fit: BoxFit.scaleDown), and the same bound sits inside "
          "RotatedBox so the swapped constraints cap the rotated word's height. "
          "Clipping is now impossible by construction rather than by luck of the "
          "shuffle. flutter analyze reports no issues on the file.",
      st="FIXED 31/08/2026, PENDING RE-TEST", tc="TC-FBK-05"),
    dict(id="DEF-04", sev="LOW", pri="Medium",
      desc='The "N Comments" counter beside the "Direct Quotes" heading sat flush '
           "against the right edge of the display with no padding. It stayed readable "
           "at the tested count, but a wider value or a larger system font size would "
           "have clipped it.",
      root="The heading and the counter sat in a spaceBetween Row as two "
           "unconstrained Text widgets. Neither could yield, so once the pair exceeded "
           "the row width the counter was pushed off the end rather than the heading "
           "giving way.",
      fix="Both sides are now Flexible with a 12 px gap between them, and the counter "
          "is end-aligned, so the heading yields first and the number is never cut. "
          "flutter analyze reports no issues on the file.",
      st="FIXED 31/08/2026, PENDING RE-TEST", tc="TC-FBK-06"),
  ],
  notes=["Both defects on this page are layout faults, not data faults: every count, "
         "quote and insight was correct in each failing case.",
         "Re-test of DEF-02 must include several pull-to-refreshes, because the cloud "
         "reshuffles and a single load will not prove the bound holds.",
         "Re-test of DEF-04 should be run once at the largest system font size the "
         "handset offers."],
),
# =====================================================================  5
dict(
  no=5, code="TER-05",
  page="Instructor - Official Evaluation Report & PDF Export",
  file="lib/instructor/detailed_report_screen.dart and "
       "lib/core/services/pdf/pdf_service.dart",
  entry='Instructor dashboard -> "View Official SAST Report" or "Full Term Report"',
  role="Instructor",
  objective=("Confirm that the official SAST evaluation report shows the correct "
             "identity and term header and the correct scores, and that the exported "
             "PDF is a faithful, correctly named copy that can be opened outside the "
             "app."),
  scope_in=("Report header identity fields, term and academic-year composition, score "
            "tables, on-screen legibility, PDF generation, the export filename and the "
            "exported document's contents."),
  scope_out=("The department head's view of the same report, which is covered in the "
             "Department Head module."),
  cases=[
    dict(id="TC-RPT-01", scen="Report opens from both entry points",
      steps='1. From the dashboard tap "View Official SAST Report".\n'
            '2. Return and open the same report through "Full Term Report".',
      data="Active term: 2nd Semester, 2027-2028",
      exp='Both entry points open the same "Official Evaluation Report" for the '
          "signed-in instructor and the active term.",
      act="Both routes opened the same report with identical content.", st=P, dfr="-"),
    dict(id="TC-RPT-02", scen="Header identity fields are readable in full on screen",
      steps="1. Read Instructor Name, Academic Year, Department and Semester in the "
            "report header.\n"
            "2. Confirm no value is cut off.",
      data='Instructor "Rodz Harvey Licayan", College of Technology and Engineering',
      exp="All four header fields render their complete value, so the instructor can "
          "confirm from the screen that the report is theirs and which term it "
          "covers.",
      act='FAIL. Three fields were truncated: "Instructor Name: Rodz...", "Academic '
          'Year: 1st Se..." and "Department: College o...". The exported PDF was NOT '
          "affected, so this was an on-screen layout constraint, not bad data. Raised "
          "as DEF-03, fixed on 31/08/2026, awaiting re-test.", st=F, dfr="DEF-03"),
    dict(id="TC-RPT-03", scen="Term and academic year are composed correctly",
      steps="1. Read the Academic Year field on screen.\n"
            "2. Export the report and read the same field in the PDF.\n"
            "3. Repeat for a report opened from Past Terms.",
      data='System contract: semester = "1st Semester", academicYear = "2025-2026"',
      exp='The field reads "1st Semester 2025-2026", with the word "Semester" '
          "appearing exactly once, from every entry point.",
      act='FAIL. The exported PDF read "Academic Year: 1st Semester Semester '
          '2025-2026". The report screen had the same fault, hidden only because the '
          "field was truncated there by DEF-03. All three entry points were affected. "
          "Raised as DEF-01, fixed on 31/08/2026, awaiting re-test.", st=F,
      dfr="DEF-01"),
    dict(id="TC-RPT-04", scen="Report scores match the dashboard and the source data",
      steps="1. Compare the overall and per-category scores in the report with the "
            "dashboard cards and with the stored evaluation record.",
      data="Evaluation record for the active term",
      exp="Every score in the report equals the stored value and the value shown on "
          "the dashboard.",
      act="All scores matched across the three sources.", st=P, dfr="-"),
    dict(id="TC-RPT-05", scen="Report renders the CTU letterhead and official framing",
      steps="1. Inspect the report header and footer on screen and in the PDF.",
      data="n/a",
      exp="The CTU seal, the university and campus lines, and the college and "
          "department lines are present and correctly spelled in both outputs.",
      act="The letterhead was correct in both the on-screen report and the exported "
          "PDF.", st=P, dfr="-"),
    dict(id="TC-RPT-06", scen="PDF export produces an openable document",
      steps="1. Trigger the export.\n"
            "2. Open the file from the device's Downloads folder in an external PDF "
            "reader.",
      data="Device storage, Downloads",
      exp="A PDF is written to Downloads and opens outside the app with all pages "
          "intact and all text selectable.",
      act="Export completed in 2.2 s. The file opened in the external reader with "
          "every page intact.", st=P, dfr="-"),
    dict(id="TC-RPT-07", scen="Exported PDF matches the on-screen report",
      steps="1. Compare the exported PDF against the report screen, field by field.",
      data="Same term and instructor",
      exp="Identity, term, scores and comments are identical between the two.",
      act="Content matched. The PDF additionally rendered the identity fields in full "
          "where the screen truncated them, which is what isolated DEF-03 from "
          "DEF-01.", st=P, dfr="-"),
    dict(id="TC-RPT-08", scen="Export filename is well formed",
      steps="1. Export the report immediately after opening it.\n"
            "2. Export it again after the profile has fully loaded.\n"
            "3. Read both filenames in Downloads.",
      data="Downloads folder history",
      exp="Each export is named from the instructor's full name and the term, with no "
          "truncation, no literal role word and no doubled separator.",
      act="NOT REPRODUCED ON THIS BUILD - the 31 August export was named correctly. "
          'The folder still holds earlier malformed exports: "SAST_Report_....pdf", '
          '"SAST_Report_Instructor.pdf" and '
          '"SAST_Report_Rodz_Harvey__Licayan.pdf". Logged as DEF-06, NEEDS '
          "CONFIRMATION; export twice more before closing it off.", st=B, dfr="DEF-06"),
    dict(id="TC-RPT-09", scen="Report for a historical term",
      steps='1. Open "Past Terms", select an earlier term and open its report.',
      data="1st Semester, 2025-2026",
      exp="The report opens for the selected historical term, with that term's header "
          "and that term's scores.",
      act="The historical report opened with the correct scores. Its header carried "
          "the same DEF-01 fault, which is how the Past Terms split was traced.",
      st=P, dfr="DEF-01"),
    dict(id="TC-RPT-10", scen="Report for a term with no evaluation data",
      steps="1. Select a term in which the instructor has no evaluation record and "
            "open the report.",
      data="Term with no stored evaluation",
      exp="An explanatory empty state is shown and no export is offered, rather than "
          "an empty or malformed PDF.",
      act="An empty state was shown and the export control was correctly unavailable.",
      st=P, dfr="-"),
  ],
  defects=[
    dict(id="DEF-01", sev="HIGH", pri="Critical",
      desc='The exported PDF read "Academic Year: 1st Semester Semester 2025-2026" - '
           'the word "Semester" printed twice. The report screen had the same fault, '
           "hidden only because the field is truncated there by DEF-03. All three "
           "entry points into the report were affected.",
      root="lib/core/services/system_settings_service.dart lines 11-12 document the "
           'contract: "semester" is a label that ALREADY includes the word (e.g. "1st '
           'Semester") and "academicYear" is just "2025-2026". Two things broke it. '
           "(1) Both composition sites - detailed_report_screen.dart:358 and "
           "pdf_service.dart:288 - read '$term Semester $academicYear'. "
           "(2) past_semesters_screen.dart:421-422 split the combined label on the "
           'FIRST space, giving term="1st" and academicYear="Semester 2025-2026".',
      fix="Both composition sites now read '$term $academicYear', since the term "
          "already carries the word. Past Terms splits on the LAST token via two new "
          "helpers, _semesterOf() and _academicYearOf(), giving term=\"1st Semester\" "
          'and academicYear="2025-2026" as the contract requires. flutter analyze '
          "reports no issues on all three files.",
      st="FIXED 31/08/2026, PENDING RE-TEST", tc="TC-RPT-03, TC-RPT-09"),
    dict(id="DEF-03", sev="MEDIUM", pri="High",
      desc='On "Official Evaluation Report" the identity fields were cut off - '
           '"Instructor Name: Rodz...", "Academic Year: 1st Se..." and "Department: '
           'College o...". The instructor could not confirm from the screen that the '
           "report was theirs or which term it covered. The exported PDF was NOT "
           "affected, so this was a layout constraint, not bad data.",
      root="_headerField rendered the value with overflow: TextOverflow.ellipsis on a "
           "single line, and the header places TWO of these side by side in one Row, "
           "so each field had only half the screen width to work with. On a phone "
           "that is not enough for a full name plus its label.",
      fix="The value now wraps (softWrap: true, no ellipsis) instead of being cut, and "
          "the Row is top-aligned so a wrapped value sits correctly beside its label. "
          "The field grows downward by a line or two on a narrow screen, which is the "
          "right trade: this block exists so the instructor can confirm the report is "
          "theirs, so being complete matters more than being one line tall. flutter "
          "analyze reports no issues on the file.",
      st="FIXED 31/08/2026, PENDING RE-TEST", tc="TC-RPT-02"),
    dict(id="DEF-06", sev="LOW", pri="Low",
      desc="The device's Downloads folder holds earlier exports with malformed "
           'filenames: "SAST_Report_....pdf" (a truncated name leaked into the '
           'filename), "SAST_Report_Instructor.pdf" (fell back to the literal role '
           'word) and "SAST_Report_Rodz_Harvey__Licayan.pdf" (a doubled underscore).',
      root="Not yet established. NOT REPRODUCED on this build - the 31 August export "
           "was named correctly - so it may already be fixed, or it may depend on how "
           "quickly the export is triggered after the profile loads.",
      fix="None applied. Export twice more, once immediately after opening the report, "
          "before this is closed off.",
      st="NEEDS CONFIRMATION", tc="TC-RPT-08"),
  ],
  notes=["DEF-01 and DEF-03 interact: DEF-03 hid DEF-01 on screen, so the doubled word "
         "was only visible in the exported PDF. Fixing DEF-03 alone would have exposed "
         "DEF-01 to every user rather than resolving it.",
         "DEF-01 is the most severe finding of this run, because the affected field "
         "appears on an official document that leaves the system as a PDF.",
         "Re-test of both defects requires a rebuild: the fixes are in the working tree "
         "and pass flutter analyze, but were not in the binary under test."],
),
]
