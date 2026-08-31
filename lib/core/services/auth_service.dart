// lib/core/services/auth_service.dart
// this file handle everything auth related, login, signup, logout, the whole thing
// if something go wrong with login, this is probably where to look first
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'department_head_guard.dart';
import 'identity_validator.dart';

// simple wrapper class to send both success/failure and data back to the UI
// instead of just crashing and leaving the user confuse
class AuthResult {
  final bool success;
  final String? error;
  final String? role;
  final String? userId;

  /// Set when [error] is a duplicate-identity clash rather than an ordinary
  /// failure. The registration screen shows those in a modal instead of as
  /// inline red text -- a duplicate means "this person is already in the
  /// system", which is a different kind of answer from "you mistyped".
  final IdentityField? conflictField;

  const AuthResult({
    required this.success,
    this.error,
    this.role,
    this.userId,
    this.conflictField,
  });
}

class AuthService {
  // this is our main connection to supabase, we use this for everything, importente kaayo ni
  final _supabase = Supabase.instance.client;

  // return the current session if there is one, null if user is not logged in
  Session? get currentSession => _supabase.auth.currentSession;

  // 1. SIGN UP
  // this handle the whole registration process, it do a lot of steps so pray it all work
  Future<AuthResult> signUp({
    required String firstName,
    required String lastName,
    required String address,
    required String universityId,
    required String institutionalEmail,
    required String departmentName,
    required String roleName,
    required String password,
    String employmentStatus = 'Full-Time',
  }) async {
    debugPrint('--- [AUTH] SIGN UP ATTEMPT START ---');

    try {
      // STEP 0: format rules, shared with both SAO Admin create screens so a
      // value rejected here cannot be accepted there.
      final formatError = IdentityValidator.validateFormat(
        firstName: firstName,
        lastName: lastName,
        email: institutionalEmail,
        universityId: universityId,
      );
      if (formatError != null) {
        return AuthResult(success: false, error: formatError);
      }

      // Clean once, then use only the cleaned values below. Stray whitespace is
      // how near-duplicates get in: " 12345" and "12345" are two different rows
      // to the database but the same ID number to a human.
      final String cleanFirstName = IdentityValidator.clean(firstName);
      final String cleanLastName = IdentityValidator.clean(lastName);
      final String cleanEmail = IdentityValidator.cleanEmail(institutionalEmail);
      final String cleanUniversityId = IdentityValidator.clean(universityId);
      final String cleanAddress = IdentityValidator.clean(address);

      // STEP 0.5: is this person already in the system?
      //
      // This replaces two direct SELECTs that did run, but let plenty through:
      // both used .eq(), which is case-sensitive and whitespace-sensitive, so
      // "Rodz@ctu.edu.ph" sailed past a stored "rodz@ctu.edu.ph" and " 12345"
      // past "12345". Neither looked at the name at all. And a check-then-
      // insert is a race no matter how it is written -- two registrations a few
      // milliseconds apart both read "available".
      //
      // So: normalised comparison, names included, via one RPC that every
      // create and rename path shares, backed by unique indexes that hold even
      // when the race is lost.
      final availability = await IdentityValidator.checkAvailability(
        client: _supabase,
        firstName: cleanFirstName,
        lastName: cleanLastName,
        email: cleanEmail,
        universityId: cleanUniversityId,
      );
      if (!availability.isAvailable) {
        return AuthResult(
          success: false,
          error: availability.error,
          conflictField: availability.field,
        );
      }

      // STEP 0.6: is the department head chair already taken?
      //
      // A department gets one head. This has to be asked BEFORE the auth
      // account exists: the database trigger rejects the department_table
      // insert at STEP 5, and by then the auth user and the user_info row are
      // already written -- and only the service role can remove an auth user,
      // so the app would leave exactly the orphan STEP 4 goes to such lengths
      // to avoid.
      final headConflict = await departmentHeadConflict(
        roleName: roleName,
        departmentName: departmentName,
      );
      if (headConflict != null) {
        return AuthResult(success: false, error: headConflict);
      }

      // STEP 1: create the user account in supabase auth first
      final authResponse = await _supabase.auth.signUp(
        email: cleanEmail,
        password: password,
      );

      // if supabase give us null user something went wrong, we stop here
      if (authResponse.user == null) {
        return const AuthResult(success: false, error: 'Registration failed.');
      }

      final String userId = authResponse.user!.id;
      debugPrint('[AUTH] Auth account created.');

      // STEP 2: find the role ID from the roles table so we can link it later
      final roleData = await _supabase
          .from('roles')
          .select('id')
          .eq('Roles', roleName)
          .maybeSingle();

      // if the role doesnt exist in the database something is wrong, dili valid
      if (roleData == null) {
        return const AuthResult(success: false, error: 'Selected role is invalid. Please contact support.');
      }
      final int roleId = roleData['id'];

      // STEP 3: handle department, but we skip this for SAO roles since they dont belong to a dept
      bool isSao = roleName.toUpperCase().contains('SAO');
      int? departmentId;

      if (!isSao) {
        // non-SAO users need a department, we fetch the ID here
        final deptData = await _supabase
            .from('department_name')
            .select('id')
            .eq('d_name', departmentName)
            .maybeSingle();

        // if department not found, something wrong with the selection
        if (deptData == null) {
          return const AuthResult(success: false, error: 'Selected department is invalid. Please contact support.');
        }
        departmentId = deptData['id'];
      }

      // STEP 4: insert the user basic info into user_info table
      //
      // The unique indexes from migration 20240130000008 are enforced here, and
      // this is where a genuine race lands: two people register the same ID
      // milliseconds apart, both pre-flight checks passed, and the database
      // rejects the second one. mapDatabaseError turns that into the same
      // wording the pre-flight check would have used.
      try {
        await _supabase.from('user_info').insert({
          'id': userId,
          'first_name': cleanFirstName,
          'last_name': cleanLastName,
          'address': cleanAddress,
          'email': cleanEmail,
          'account_status': 'pending', // all new accounts need admin approval before they can login
          'university_id': cleanUniversityId,
          'employment_status': employmentStatus,
        });
      } catch (insertError) {
        final duplicate = IdentityValidator.mapDatabaseError(
          insertError,
          firstName: cleanFirstName,
          lastName: cleanLastName,
        );
        if (duplicate == null) rethrow;
        // The auth account now exists with no profile row. Only the service
        // role can delete an auth user, so the app cannot clean this up --
        // hence the instruction to contact the SAO office.
        debugPrint('[AUTH] Duplicate at user_info insert; auth user $userId is orphaned.');
        await signOut();
        return AuthResult(
          success: false,
          error: '$duplicate\n\nPlease contact the SAO office to have this sorted out.',
          conflictField: IdentityField.name,
        );
      }

      // STEP 5: link user to the right table depending on their role
      // SAO users go to Sao_users table, everyone else go to department_table
      if (isSao) {
        await _supabase.from('Sao_users').insert({
          'user_id': userId,
          'role_id': roleId,
        });
      } else {
        await _supabase.from('department_table').insert({
          'user_id': userId,
          'Department_name_ID': departmentId,
          'roles': roleId,
        });
        // Also insert into instructor_departments for multi-dept support.
        // Non-Resident instructors can later be assigned a second dept by SAO Admin.
        // is_primary = true means this is their home department.
        try {
          await _supabase.from('instructor_departments').insert({
            'instructor_id': userId,
            'department_id': departmentId,
            'is_primary': true,
          });
        } catch (deptLinkError) {
          // Log but do not fail signup — instructor_departments is supplementary.
          // The backfill migration ensures existing users are already covered.
          debugPrint('[AUTH] Warning: Could not insert instructor_departments row: $deptLinkError');
        }
      }

      debugPrint('--- [AUTH] SIGN UP SUCCESS ---');
      return const AuthResult(success: true);
    } on SocketException {
      // no internet, we catch it separately so the error message is friendly
      return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
    } catch (e) {
      debugPrint('[AUTH] Sign Up Error: $e');
      final msg = e.toString();
      // some network errors dont throw SocketException, so we check the message too
      if (msg.contains('SocketException') || msg.contains('Failed host lookup') || msg.contains('errno = 7')) {
        return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
      }
      // The one-head-per-department trigger rejected the department_table
      // insert at STEP 5 -- the race STEP 0.6 cannot close, where someone else
      // takes the chair while this form is being filled in. The auth account
      // and the user_info row already exist by now and only the service role
      // can remove them, hence the instruction to contact the SAO office.
      final headTaken = DepartmentHeadGuard.describeConflictError(e);
      if (headTaken != null) {
        debugPrint('[AUTH] Department head chair taken; auth user is orphaned.');
        await signOut();
        return AuthResult(
          success: false,
          error: '$headTaken\n\nPlease contact the SAO office to have this sorted out.',
        );
      }
      // Supabase Auth keeps its own unique index on the email address and never
      // releases it, so an email can be free in user_info yet still taken here.
      final lower = msg.toLowerCase();
      if (lower.contains('already been registered') ||
          lower.contains('already registered') ||
          lower.contains('user_already_exists')) {
        return const AuthResult(
          success: false,
          error: 'This email address already has an account. Try logging in, '
              'or use Forgot Password if you cannot remember it.',
          conflictField: IdentityField.email,
        );
      }
      final duplicate = IdentityValidator.mapDatabaseError(e);
      if (duplicate != null) {
        return AuthResult(
          success: false,
          error: duplicate,
          conflictField: IdentityField.universityId,
        );
      }
      return const AuthResult(success: false, error: 'Registration failed. Please try again.');
    }
  }

  /// Is the department head chair for [departmentName] already occupied?
  ///
  /// Returns the sentence to show the applicant, or null when there is nothing
  /// in the way -- the role is not a head role, no department is chosen yet, or
  /// the chair is free.
  ///
  /// Shared by the registration screen, which asks as soon as a department is
  /// picked so the applicant is not carried through three more steps toward a
  /// registration that cannot succeed, and by [signUp], which asks again at
  /// submit because the chair can be filled while the form is open.
  ///
  /// The department is looked up by name here rather than reusing signUp's
  /// STEP 3 lookup, because that one runs after the auth account already
  /// exists and this check has to happen before it.
  Future<String?> departmentHeadConflict({
    required String roleName,
    required String departmentName,
  }) async {
    if (!isDepartmentHeadRole(roleName)) return null;
    final String name = departmentName.trim();
    if (name.isEmpty) return null;

    try {
      final dept = await _supabase
          .from('department_name')
          .select('id')
          .eq('d_name', name)
          .maybeSingle();
      // An unknown department is signUp's problem to report, not this one's.
      if (dept == null) return null;

      final taken = await DepartmentHeadGuard.departmentHasHead(
        client: _supabase,
        departmentId: dept['id'],
      );
      if (!taken) return null;

      // No head name for an applicant: they are not staff yet, and the RPC
      // deliberately never returns one to an unauthenticated caller.
      return DepartmentHeadGuard.conflictMessage(departmentName: name);
    } catch (e) {
      // Same reasoning as the availability check: a pre-flight courtesy that
      // must not block registration when it cannot run. The trigger still
      // rejects the insert, and signUp maps that to the same message.
      debugPrint('[AUTH] Department head check unavailable: $e');
      return null;
    }
  }

  /// Is this name / email / ID free?
  ///
  /// Same check signUp runs, exposed so the registration screen can ask on the
  /// step that owns the field instead of at the very end. Finding out an ID is
  /// taken AFTER reading the NDA and the DPA is the worst possible moment to
  /// find out.
  ///
  /// Pass only the fields you want checked.
  Future<IdentityCheckResult> checkIdentityAvailable({
    String? firstName,
    String? lastName,
    String? email,
    String? universityId,
  }) {
    return IdentityValidator.checkAvailability(
      client: _supabase,
      firstName: firstName,
      lastName: lastName,
      email: email,
      universityId: universityId,
    );
  }

  // 2. SIGN IN
  // this is where user try to log in, it do several checks before letting them in
  Future<AuthResult> signIn({
    required String idOrEmail,
    required String password,
  }) async {
    debugPrint('--- [AUTH] SIGN IN ATTEMPT START ---');

    try {
      String emailToUse = idOrEmail;

      // STEP 1: if user type their university ID instead of email, we convert it here
      // we use a generic error message on fail so attacker cant tell if an ID exist or not
      if (!idOrEmail.contains('@')) {
        final typedId = IdentityValidator.clean(idOrEmail);

        // Anything that is not a well-formed ID cannot match a stored one, so
        // there is nothing to look up. This also keeps LIKE metacharacters out
        // of the ilike pattern below -- '%' would otherwise match every row.
        if (IdentityValidator.validateUniversityId(typedId) != null) {
          return const AuthResult(success: false, error: 'Incorrect ID or password. Please try again.');
        }

        // ilike, not eq: IDs are stored as typed, so 'ctu-1234' must still find
        // 'CTU-1234'. limit(1) rather than maybeSingle() because maybeSingle
        // THROWS when more than one row comes back -- meaning a single
        // duplicated ID in the table used to lock out both of those people and
        // every login attempt on that ID. Ordering by created_at makes the
        // choice deterministic (oldest account wins) for as long as any
        // pre-existing duplicates remain.
        final matches = await _supabase
            .from('user_info')
            .select('email')
            .ilike('university_id', typedId)
            .order('created_at', ascending: true)
            .limit(1);

        if (matches.isEmpty || matches.first['email'] == null) {
          // we give the same error whether ID exist or not, security measure ni siya
          return const AuthResult(success: false, error: 'Incorrect ID or password. Please try again.');
        }
        emailToUse = matches.first['email'] as String;
      }

      // STEP 2: now we actually try to login with supabase auth using the email
      final response = await _supabase.auth.signInWithPassword(
        email: emailToUse,
        password: password,
      );
      debugPrint('[AUTH] Auth successful.');

      // STEP 3: fetch the user role and account status so we know where to send them
      // we null-check first because supabase can sometimes be sneaky
      if (response.user == null) {
        return const AuthResult(success: false, error: 'Authentication failed. Please try again.');
      }
      final String uid = response.user!.id;

      String? role;
      String? status;

      // Step A: check department_table first, this is where most users live (instructors etc)
      var userData = await _supabase
          .from('department_table')
          .select('user_info!user_id(account_status), roles!roles(Roles)')
          .eq('user_id', uid)
          .maybeSingle();

      if (userData != null) {
        // we handle both list and object response from supabase, it can be both apparently
        final ui = userData['user_info'];
        status = ui is List ? (ui.isNotEmpty ? ui[0]['account_status'] : null) : ui?['account_status'];
        final r = userData['roles'];
        role = r is List ? (r.isNotEmpty ? r[0]['Roles'] : null) : r?['Roles'];
      } else {
        // Step B: if not in department_table, check Sao_users for admin and staff
        var saoData = await _supabase
            .from('Sao_users')
            .select('user_info!user_id(account_status), roles!role_id(Roles)')
            .eq('user_id', uid)
            .maybeSingle();

        if (saoData != null) {
          final ui = saoData['user_info'];
          status = ui is List ? (ui.isNotEmpty ? ui[0]['account_status'] : null) : ui?['account_status'];
          final r = saoData['roles'];
          role = r is List ? (r.isNotEmpty ? r[0]['Roles'] : null) : r?['Roles'];
        }
      }

      // if we still cant find role or status, something seriously wrong with the profile
      if (role == null || status == null) {
        await signOut(); // sign them out first before returning error, clean it up
        return const AuthResult(success: false, error: 'User profile incomplete. Please contact support.');
      }

      // account must be approved by admin before they can login
      if (status == 'disabled') {
        await signOut();
        return const AuthResult(success: false, error: 'Your account has been deactivated by the administration.');
      }

      // Each non-approved status gets its own message. Previously everything
      // that was not 'disabled' fell through to "Account pending admin
      // approval." -- so a rejected applicant was told to wait for an approval
      // that had already happened, negatively, and a suspended user was told
      // the same thing. Both then wait indefinitely for an email that is never
      // coming instead of contacting the SAO office.
      if (status == 'rejected') {
        await signOut();
        return const AuthResult(success: false, error: 'Your registration was not approved. Please contact the SAO office.');
      }

      if (status == 'suspended') {
        await signOut();
        return const AuthResult(success: false, error: 'This account is suspended. Please contact the SAO office.');
      }

      if (status == 'pending') {
        await signOut();
        return const AuthResult(success: false, error: 'Account pending admin approval.');
      }

      if (status != 'approved') {
        await signOut();
        return const AuthResult(success: false, error: 'This account is not active. Please contact the SAO office.');
      }

      // The auth email is the authority; user_info.email is a copy kept for
      // login-by-university-ID. updateEmail() deliberately no longer writes
      // that copy up front, because Supabase does not change the auth email
      // until the confirmation link is clicked -- writing it early pointed ID
      // login at an address Auth did not recognise yet. Reconciling here means
      // the copy catches up by itself on the first sign-in after confirmation.
      await _syncEmailCopyFromAuth(uid, response.user!.email);

      debugPrint('--- [AUTH] SIGN IN SUCCESS ---');
      return AuthResult(success: true, role: role, userId: response.user!.id);
    } on AuthException catch (e) {
      debugPrint('[AUTH] Supabase Auth Error (code only): ${e.statusCode}');
      // check if its a network issue first before anything else
      if (_isNetworkError(e.message)) {
        return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
      }
      final msg = e.message.toLowerCase();
      // A banned account must NOT be reported as a wrong password. It was, and
      // the result is a user resetting their password over and over on an
      // account that no password will ever open. delete-user bans for ten
      // years, so this is reachable in practice.
      //
      // Checked BEFORE the invalid-credentials branch: depending on the
      // Supabase version a ban can surface either with 'banned' in the message
      // or as a plain invalid-credentials error. When it is the latter this
      // branch cannot fire and the old wording still shows -- which is why the
      // real fix is admin-accept-user clearing the ban on reactivation, not
      // this message.
      if (msg.contains('banned') || msg.contains('user is banned')) {
        return const AuthResult(success: false, error: 'This account has been suspended. Please contact the SAO office.');
      }
      // handle the common login errors with friendly messages
      if (msg.contains('invalid login') || msg.contains('invalid credentials') || msg.contains('email not confirmed')) {
        return const AuthResult(success: false, error: 'Incorrect ID or password. Please try again.');
      }
      if (msg.contains('too many requests') || msg.contains('rate limit')) {
        return const AuthResult(success: false, error: 'Too many attempts. Please wait a moment and try again.');
      }
      // we never show raw supabase error to user, too technical and scary looking
      return const AuthResult(success: false, error: 'Sign in failed. Please check your credentials and try again.');
    } on SocketException {
      return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
    } catch (e) {
      debugPrint('[AUTH] Sign In Error (type): ${e.runtimeType}');
      if (_isNetworkError(e.toString())) {
        return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
      }
      return const AuthResult(success: false, error: 'Sign in failed. Please check your credentials and try again.');
    }
  }

  /// fetch the user name and other info from user_info table using their uid
  Future<Map<String, dynamic>?> getUserInfo(String uid) async {
    try {
      final data = await _supabase
          .from('user_info')
          .select('first_name, last_name, university_id, email')
          .eq('id', uid)
          .maybeSingle();
      return data;
    } catch (e) {
      // if we cant get user info we just return null, caller will handle it
      debugPrint('[AUTH] Error fetching user info.');
      return null;
    }
  }

  /// fetch the role and account status for a given user ID
  /// this is used to verify the user profile is complete and approved
  Future<Map<String, String?>?> getUserProfile(String uid) async {
    try {
      String? role;
      String? status;

      // check department_table first, same logic as sign in, instructors are here
      var userData = await _supabase
          .from('department_table')
          .select('user_info!user_id(account_status), roles!roles(Roles)')
          .eq('user_id', uid)
          .maybeSingle();

      if (userData != null) {
        final ui = userData['user_info'];
        status = ui is List ? (ui.isNotEmpty ? ui[0]['account_status'] : null) : ui?['account_status'];
        final r = userData['roles'];
        role = r is List ? (r.isNotEmpty ? r[0]['Roles'] : null) : r?['Roles'];
      } else {
        // not in department_table so check SAO users table
        var saoData = await _supabase
            .from('Sao_users')
            .select('user_info!user_id(account_status), roles!role_id(Roles)')
            .eq('user_id', uid)
            .maybeSingle();

        if (saoData != null) {
          final ui = saoData['user_info'];
          status = ui is List ? (ui.isNotEmpty ? ui[0]['account_status'] : null) : ui?['account_status'];
          final r = saoData['roles'];
          role = r is List ? (r.isNotEmpty ? r[0]['Roles'] : null) : r?['Roles'];
        }
      }

      // return the profile if both role and status found, otherwise null
      if (role != null && status != null) {
        return {'role': role, 'status': status};
      }
      return null;
    } catch (e) {
      debugPrint('[AUTH] Error fetching user profile.');
      return null;
    }
  }

  // 3. SIGN OUT
  // simple log out function, we just tell supabase to end the session
  Future<void> signOut() async {
    debugPrint('[AUTH] User signing out...');
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      // if sign out fail we still move on, dili na namo i-force, just log it
      debugPrint('[AUTH] Error during signOut.');
    }
  }

  // 4a. REQUEST A DEACTIVATION CODE
  // Emails a 6-digit code to the signed-in user's own address. Deactivating an
  // account locks the person out until an SAO admin reactivates them, which is
  // too much to hang on one tap of a confirm button -- a phone left unlocked on
  // a desk should not be enough.
  //
  // Reuses send-admin-code with purpose SELF_DEACTIVATE: same crypto-random
  // code, same 10-minute expiry, same 60-second rate limit, same hashed
  // storage. The purpose is what stops this code from also unlocking admin
  // actions, and what lets the function skip its SAO_ADMIN gate -- an
  // instructor must be able to request one for themselves.
  Future<AuthResult> sendDeactivationCode() async {
    try {
      if (_supabase.auth.currentUser == null) {
        return const AuthResult(success: false, error: 'No user logged in.');
      }
      // The recipient is taken from the session server-side, so no email is
      // sent from here -- a client cannot redirect its own code.
      await _supabase.functions.invoke(
        'send-admin-code',
        body: {'purpose': 'SELF_DEACTIVATE'},
      );
      return const AuthResult(success: true);
    } catch (e) {
      debugPrint('[AUTH] Deactivation code request failed: $e');
      // The rate-limit message names the seconds left, so it must survive.
      return AuthResult(
        success: false,
        error: IdentityValidator.describeEdgeFunctionError(
          e,
          fallback: 'Could not send the code. Please try again.',
        ),
      );
    }
  }

  // 4. DEACTIVATE ACCOUNT
  // Marks the account disabled and bans it in Auth, so the person cannot sign
  // in until an SAO admin reactivates them. Not a hard delete -- their
  // evaluation data is real data collected while they were teaching.
  //
  // [verificationCode] is the code emailed by [sendDeactivationCode]. It is
  // re-checked inside the edge function, not here: delete-user is a public
  // endpoint, so a check in this method would only inconvenience the honest.
  Future<AuthResult> deleteAccount({required String verificationCode}) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      // we cant delete if there is no user logged in, obvious but we check anyway
      if (userId == null) return const AuthResult(success: false, error: 'No user logged in.');

      // call the cloud function to handle the deletion on the server side
      await _supabase.functions.invoke(
        'delete-user',
        body: {'userId': userId, 'verificationCode': verificationCode},
      );
      await signOut(); // sign them out after deletion, clean finish
      return const AuthResult(success: true);
    } catch (e) {
      debugPrint('[AUTH] Deactivate Account Error: $e');
      // Surface the server's own wording. The expected failures here are all
      // about the code -- wrong, expired, or out of attempts -- and each tells
      // the user something different about what to do next. Collapsing them
      // into one generic sentence leaves them stuck.
      return AuthResult(
        success: false,
        error: IdentityValidator.describeEdgeFunctionError(
          e,
          fallback: 'Deactivation failed. Please try again.',
        ),
      );
    }
  }

  // 5. UPDATE PROFILE
  // update the user first and last name in the database
  Future<AuthResult> updateProfile({
    required String firstName,
    required String lastName,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return const AuthResult(success: false, error: 'No user logged in.');

      // Renaming yourself is the third way a duplicate full name appears --
      // after registration and after an admin edit. Same shared rules.
      final formatError = IdentityValidator.validateFormat(
        firstName: firstName,
        lastName: lastName,
      );
      if (formatError != null) {
        return AuthResult(success: false, error: formatError);
      }

      final String cleanFirstName = IdentityValidator.clean(firstName);
      final String cleanLastName = IdentityValidator.clean(lastName);

      // excludeUserId is this account, so saving the settings page without
      // actually changing the name does not report you as your own duplicate.
      final availability = await IdentityValidator.checkAvailability(
        client: _supabase,
        firstName: cleanFirstName,
        lastName: cleanLastName,
        excludeUserId: userId,
      );
      if (!availability.isAvailable) {
        return AuthResult(success: false, error: availability.error);
      }

      // update only name fields, we dont touch the rest so dili ma-overwrite
      await _supabase.from('user_info').update({
        'first_name': cleanFirstName,
        'last_name': cleanLastName,
      }).eq('id', userId);

      return const AuthResult(success: true);
    } catch (e) {
      debugPrint('[AUTH] Update Profile Error: $e');
      final duplicate = IdentityValidator.mapDatabaseError(e);
      if (duplicate != null) {
        return AuthResult(success: false, error: duplicate);
      }
      // return generic message so the raw error dont scare the user
      return const AuthResult(success: false, error: 'Profile update failed. Please try again.');
    }
  }

  /// Brings the `user_info.email` copy back in line with the authoritative
  /// Supabase Auth email.
  ///
  /// Only ever needed because login-by-university-ID has to resolve an ID to an
  /// email before it can call signInWithPassword, so a copy of the address has
  /// to live in `user_info`. That copy goes stale the moment a user requests an
  /// email change and only becomes correct once they confirm it, which happens
  /// out of band. Reconciling on sign-in is the one point where Auth is
  /// guaranteed to have told us the current address.
  ///
  /// Failure here must never block a sign-in that already succeeded: a stale
  /// copy degrades ID login, whereas throwing would deny access outright.
  Future<void> _syncEmailCopyFromAuth(String userId, String? authEmail) async {
    if (authEmail == null || authEmail.trim().isEmpty) return;
    final String authoritative = IdentityValidator.cleanEmail(authEmail);

    try {
      final row = await _supabase
          .from('user_info')
          .select('email')
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return;

      final String? stored = row['email'] as String?;
      if (stored != null && IdentityValidator.cleanEmail(stored) == authoritative) {
        return; // already in step, no write
      }

      await _supabase
          .from('user_info')
          .update({'email': authoritative})
          .eq('id', userId);
      debugPrint('[AUTH] user_info.email reconciled with the confirmed auth email');
    } catch (e) {
      // Includes the case where the address is already taken by another row --
      // the unique index rejects it and the old copy stays. Logged, not raised.
      debugPrint('[AUTH] email copy sync skipped: $e');
    }
  }

  // UPDATE EMAIL
  // Requests an email change in Supabase Auth. The change does not take effect
  // until the user clicks the confirmation link sent to the NEW address.
  Future<AuthResult> updateEmail(String newEmail) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return const AuthResult(success: false, error: 'No user logged in.');

      final formatError = IdentityValidator.validateEmail(newEmail);
      if (formatError != null) {
        return AuthResult(success: false, error: formatError);
      }
      final String cleanNewEmail = IdentityValidator.cleanEmail(newEmail);

      // Check if new email is already used by someone else.
      //
      // The previous check used .eq(), so it only caught an exact byte match --
      // changing your address to the capitalised form of a colleague's went
      // straight through. Normalised comparison now, and the unique index on
      // email is the backstop.
      final availability = await IdentityValidator.checkAvailability(
        client: _supabase,
        email: cleanNewEmail,
        excludeUserId: userId,
      );
      if (!availability.isAvailable) {
        return AuthResult(success: false, error: availability.error);
      }

      // Update in Supabase Auth. This only SENDS a confirmation link -- the auth
      // email stays the old one until the user clicks it.
      await _supabase.auth.updateUser(
        UserAttributes(email: cleanNewEmail),
      );

      // user_info.email is deliberately NOT written here.
      //
      // It used to be written immediately, which broke login-by-university-ID:
      // that path looks the ID up in user_info, takes the email it finds, and
      // hands it to signInWithPassword. Writing the new address before Auth
      // knew about it meant ID login was handed an address Auth would reject,
      // so it failed from the moment Update was tapped until the link was
      // clicked -- and permanently if it never was. Email login with the OLD
      // address kept working the whole time, which made it look random.
      //
      // The copy is reconciled by _syncEmailCopyFromAuth on the next sign-in,
      // once Auth actually reports the new address.
      return const AuthResult(success: true);
    } catch (e) {
      debugPrint('[AUTH] Update Email Error: $e');
      return const AuthResult(success: false, error: 'Email update failed. Ensure the email is not already in use.');
    }
  }

  // 6. FORGOT PASSWORD — STEP 1: EMAIL THE CODE
  // Sends a one-time code to the user's email. No redirectTo / deep link is
  // passed on purpose: the entire reset now happens inside the app, so the user
  // types the code here instead of clicking a link out to a browser.
  //
  // NOTE: the Supabase "Reset Password" email template must include the
  // {{ .Token }} placeholder for the code to appear in the message. A template
  // that only contains {{ .ConfirmationURL }} will still send mail, but the
  // recipient gets a link with no code to type.
  Future<AuthResult> sendPasswordResetCode(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
      // we always return success here even if email doesnt exist
      // this prevent attacker from knowing which emails are registered, security 101
      return const AuthResult(success: true);
    } on SocketException {
      return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
    } catch (e) {
      debugPrint('[AUTH] Reset Code Error (type): ${e.runtimeType}');
      final msg = e.toString();
      // detect ALL network-related errors (not just SocketException) and surface them to user
      if (_isNetworkError(msg) || msg.contains('Failed host lookup')) {
        return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
      }
      // Rate limiting is worth telling the user about — otherwise they keep
      // tapping Resend and wonder why nothing arrives.
      if (msg.contains('rate limit') || msg.contains('Too many requests') || msg.contains('429')) {
        return const AuthResult(success: false, error: 'Too many requests. Please wait a minute before trying again.');
      }
      // for all other errors (e.g. auth service errors) we still return success
      // this prevents attackers from learning which emails are registered — security 101
      return const AuthResult(success: true);
    }
  }

  // 6b. FORGOT PASSWORD — STEP 2: VERIFY THE CODE
  // Exchanges the emailed code for a short-lived recovery session. That session
  // is what allows updatePassword() below to run without the old password.
  // Unlike step 1 this MUST report failure honestly — the user needs to know
  // their code was wrong or has expired.
  Future<AuthResult> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.recovery,
      );
      if (response.session == null) {
        return const AuthResult(success: false, error: 'That code could not be verified. Please request a new one.');
      }
      return AuthResult(success: true, userId: response.user?.id);
    } on SocketException {
      return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
    } on AuthException catch (e) {
      debugPrint('[AUTH] Verify Reset Code AuthException: ${e.message} '
          '(status=${e.statusCode}, code=${e.code})');
      final msg = e.message.toLowerCase();

      if (msg.contains('rate limit') || msg.contains('too many')) {
        return const AuthResult(success: false, error: 'Too many attempts. Please wait a minute before trying again.');
      }

      // Supabase reports "expired", "invalid", and "not found" for what is,
      // from the user's point of view, one situation: this code is dead. The
      // most common cause is that a NEWER code was requested — every request
      // (including Resend) invalidates the previous one — or that the code was
      // already used, since they are single-use.
      if (msg.contains('expired') ||
          msg.contains('invalid') ||
          msg.contains('not found')) {
        return AuthResult(
          success: false,
          error: 'This code is no longer valid. Codes can only be used once, '
              'and asking for a new one cancels the old one. Tap Resend code '
              'and use the newest email.${_debugSuffix(e.message)}',
        );
      }

      return AuthResult(
        success: false,
        error: 'Could not verify that code. Please tap Resend code and try '
            'the newest email.${_debugSuffix(e.message)}',
      );
    } catch (e) {
      debugPrint('[AUTH] Verify Reset Code Error: $e');
      final msg = e.toString();
      if (_isNetworkError(msg) || msg.contains('Failed host lookup')) {
        return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
      }
      return const AuthResult(success: false, error: 'Could not verify the code. Please try again.');
    }
  }

  // 7. UPDATE PASSWORD
  // update the user password directly, this only work when they are already authenticated
  Future<AuthResult> updatePassword(String newPassword) async {
    try {
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      return const AuthResult(success: true);
    } catch (e) {
      debugPrint('[AUTH] Update Password Error: $e');
      return const AuthResult(success: false, error: 'Password update failed. Please try again.');
    }
  }

  // Shows the provider's own wording in debug builds only, so a failing reset
  // can actually be diagnosed without exposing internals to real users.
  String _debugSuffix(String raw) => kDebugMode ? '\n\n[debug] $raw' : '';

  // 8. FETCH METADATA FOR DROPDOWNS
  // get list of all departments from database, used in signup form dropdowns
  Future<List<String>> getDepartments() async {
    try {
      final List<dynamic> data = await _supabase
          .from('department_name')
          .select('d_name')
          .order('d_name', ascending: true); // sort alphabetically so it look organize
      return data.map((e) => e['d_name'] as String).toList();
    } catch (e) {
      // if fetch fail we return empty list, better than crashing the whole signup form
      debugPrint('[AUTH] Error fetching departments.');
      return [];
    }
  }

  // get list of all available roles from database, also for signup dropdowns
  Future<List<String>> getRoles() async {
    try {
      final List<dynamic> data = await _supabase
          .from('roles')
          .select('Roles')
          .order('Roles', ascending: true);
      return data.map((e) => e['Roles'] as String).toList();
    } catch (e) {
      debugPrint('[AUTH] Error fetching roles.');
      return []; // empty list if fail, same as departments, dili ta mag crash
    }
  }

  /// check if an error message is related to network or connectivity issues
  /// we use this to give the user a proper internet error instead of a confusing one
  bool _isNetworkError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('no address associated') ||
        lower.contains('errno = 7') ||
        lower.contains('clientexception') ||
        lower.contains('connection refused') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection timed out');
  }
}
