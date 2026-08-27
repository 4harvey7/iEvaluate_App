// lib/core/services/auth_service.dart
// this file handle everything auth related, login, signup, logout, the whole thing
// if something go wrong with login, this is probably where to look first
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// simple wrapper class to send both success/failure and data back to the UI
// instead of just crashing and leaving the user confuse
class AuthResult {
  final bool success;
  final String? error;
  final String? role;
  final String? userId;
  const AuthResult({required this.success, this.error, this.role, this.userId});
}

class AuthService {
  static const _authenticationTimeout = Duration(seconds: 10);
  static const _profileLookupTimeout = Duration(seconds: 7);

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
      // STEP 0: check if university_id is already taken
      final existingUser = await _supabase
          .from('user_info')
          .select('id')
          .eq('university_id', universityId)
          .maybeSingle();

      if (existingUser != null) {
        return const AuthResult(
          success: false,
          error:
              'The ID is already in the database. If you have more questions ask the SAO.',
        );
      }

      // STEP 0.5: check if email is already taken
      final existingEmail = await _supabase
          .from('user_info')
          .select('id')
          .eq('email', institutionalEmail)
          .maybeSingle();

      if (existingEmail != null) {
        return const AuthResult(
          success: false,
          error: 'This email is already registered.',
        );
      }

      // STEP 1: create the user account in supabase auth first
      final authResponse = await _supabase.auth.signUp(
        email: institutionalEmail,
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
        return const AuthResult(
          success: false,
          error: 'Selected role is invalid. Please contact support.',
        );
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
          return const AuthResult(
            success: false,
            error: 'Selected department is invalid. Please contact support.',
          );
        }
        departmentId = deptData['id'];
      }

      // STEP 4: insert the user basic info into user_info table
      await _supabase.from('user_info').insert({
        'id': userId,
        'first_name': firstName,
        'last_name': lastName,
        'address': address,
        'email': institutionalEmail,
        'account_status':
            'pending', // all new accounts need admin approval before they can login
        'university_id': universityId,
        'employment_status': employmentStatus,
      });

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
      }

      debugPrint('--- [AUTH] SIGN UP SUCCESS ---');
      return const AuthResult(success: true);
    } on SocketException {
      // no internet, we catch it separately so the error message is friendly
      return const AuthResult(
        success: false,
        error: 'No internet connection. Please check your WiFi or mobile data.',
      );
    } catch (e) {
      debugPrint('[AUTH] Sign Up Error: $e');
      final msg = e.toString();
      // some network errors dont throw SocketException, so we check the message too
      if (msg.contains('SocketException') ||
          msg.contains('Failed host lookup') ||
          msg.contains('errno = 7')) {
        return const AuthResult(
          success: false,
          error:
              'No internet connection. Please check your WiFi or mobile data.',
        );
      }
      return const AuthResult(
        success: false,
        error: 'Registration failed. Please try again.',
      );
    }
  }

  // 2. SIGN IN
  // this is where user try to log in, it do several checks before letting them in
  Future<AuthResult> signIn({
    required String idOrEmail,
    required String password,
  }) async {
    final timer = Stopwatch()..start();
    debugPrint('--- [AUTH] SIGN IN ATTEMPT START ---');

    try {
      String emailToUse = idOrEmail;

      // STEP 1: if user type their university ID instead of email, we convert it here
      // we use a generic error message on fail so attacker cant tell if an ID exist or not
      if (!idOrEmail.contains('@')) {
        final userSearch = await _supabase
            .from('user_info')
            .select('email')
            .eq('university_id', idOrEmail)
            .maybeSingle();

        if (userSearch == null) {
          // we give the same error whether ID exist or not, security measure ni siya
          return const AuthResult(
            success: false,
            error: 'Incorrect ID or password. Please try again.',
          );
        }
        emailToUse = userSearch['email'];
      }

      // STEP 2: now we actually try to login with supabase auth using the email
      final response = await _supabase.auth
          .signInWithPassword(email: emailToUse, password: password)
          .timeout(_authenticationTimeout);
      debugPrint(
        '[AUTH] Credentials verified in ${timer.elapsedMilliseconds}ms.',
      );

      // STEP 3: fetch the user role and account status so we know where to send them
      // we null-check first because supabase can sometimes be sneaky
      if (response.user == null) {
        return const AuthResult(
          success: false,
          error: 'Authentication failed. Please try again.',
        );
      }
      final String uid = response.user!.id;

      String? role;
      String? status;

      // Resolve both role sources concurrently. Previously the SAO lookup had
      // to wait for the department lookup to finish, and neither request had a
      // deadline, so the sign-in spinner could remain active indefinitely.
      final departmentLookup = _supabase
          .from('department_table')
          .select('user_info!user_id(account_status), roles!roles(Roles)')
          .eq('user_id', uid)
          .maybeSingle();
      final saoLookup = _supabase
          .from('Sao_users')
          .select('user_info!user_id(account_status), roles!role_id(Roles)')
          .eq('user_id', uid)
          .maybeSingle();

      final profileRows = await Future.wait([
        departmentLookup,
        saoLookup,
      ]).timeout(_profileLookupTimeout);

      final profileData = profileRows[0] ?? profileRows[1];
      if (profileData != null) {
        // Supabase relations may be returned as either an object or a list.
        final ui = profileData['user_info'];
        status = ui is List
            ? (ui.isNotEmpty ? ui[0]['account_status'] : null)
            : ui?['account_status'];
        final r = profileData['roles'];
        role = r is List ? (r.isNotEmpty ? r[0]['Roles'] : null) : r?['Roles'];
      }

      debugPrint(
        '[AUTH] Profile resolved in ${timer.elapsedMilliseconds}ms total.',
      );

      // if we still cant find role or status, something seriously wrong with the profile
      if (role == null || status == null) {
        await signOut(); // sign them out first before returning error, clean it up
        return const AuthResult(
          success: false,
          error: 'User profile incomplete. Please contact support.',
        );
      }

      // account must be approved by admin before they can login
      if (status == 'disabled') {
        await signOut();
        return const AuthResult(
          success: false,
          error: 'Your account has been deactivated by the administration.',
        );
      }

      if (status != 'approved') {
        await signOut();
        return const AuthResult(
          success: false,
          error: 'Account pending admin approval.',
        );
      }

      debugPrint(
        '--- [AUTH] SIGN IN SUCCESS (${timer.elapsedMilliseconds}ms) ---',
      );
      return AuthResult(success: true, role: role, userId: response.user!.id);
    } on TimeoutException {
      debugPrint(
        '[AUTH] Sign in timed out after ${timer.elapsedMilliseconds}ms.',
      );
      try {
        await _supabase.auth
            .signOut(scope: SignOutScope.local)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
      return const AuthResult(
        success: false,
        error:
            'Sign in is taking longer than expected. Check your connection and try again.',
      );
    } on AuthException catch (e) {
      debugPrint('[AUTH] Supabase Auth Error (code only): ${e.statusCode}');
      // check if its a network issue first before anything else
      if (_isNetworkError(e.message)) {
        return const AuthResult(
          success: false,
          error:
              'No internet connection. Please check your WiFi or mobile data.',
        );
      }
      final msg = e.message.toLowerCase();
      // handle the common login errors with friendly messages
      if (msg.contains('invalid login') ||
          msg.contains('invalid credentials') ||
          msg.contains('email not confirmed')) {
        return const AuthResult(
          success: false,
          error: 'Incorrect ID or password. Please try again.',
        );
      }
      if (msg.contains('too many requests') || msg.contains('rate limit')) {
        return const AuthResult(
          success: false,
          error: 'Too many attempts. Please wait a moment and try again.',
        );
      }
      // we never show raw supabase error to user, too technical and scary looking
      return const AuthResult(
        success: false,
        error: 'Sign in failed. Please check your credentials and try again.',
      );
    } on SocketException {
      return const AuthResult(
        success: false,
        error: 'No internet connection. Please check your WiFi or mobile data.',
      );
    } catch (e) {
      debugPrint('[AUTH] Sign In Error (type): ${e.runtimeType}');
      if (_isNetworkError(e.toString())) {
        return const AuthResult(
          success: false,
          error:
              'No internet connection. Please check your WiFi or mobile data.',
        );
      }
      return const AuthResult(
        success: false,
        error: 'Sign in failed. Please check your credentials and try again.',
      );
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
        status = ui is List
            ? (ui.isNotEmpty ? ui[0]['account_status'] : null)
            : ui?['account_status'];
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
          status = ui is List
              ? (ui.isNotEmpty ? ui[0]['account_status'] : null)
              : ui?['account_status'];
          final r = saoData['roles'];
          role = r is List
              ? (r.isNotEmpty ? r[0]['Roles'] : null)
              : r?['Roles'];
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

  // 4. DELETE ACCOUNT
  // this permanently delete the account by calling a supabase cloud function
  // once this run there is no going back, bahala na ang user
  Future<AuthResult> deleteAccount() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      // we cant delete if there is no user logged in, obvious but we check anyway
      if (userId == null)
        return const AuthResult(success: false, error: 'No user logged in.');

      // call the cloud function to handle the deletion on the server side
      await _supabase.functions.invoke('delete-user', body: {'userId': userId});
      await signOut(); // sign them out after deletion, clean finish
      return const AuthResult(success: true);
    } catch (e) {
      // we never expose raw error to UI, just log it here for debugging
      debugPrint('[AUTH] Delete Account Error: $e');
      return const AuthResult(
        success: false,
        error: 'Account deletion failed. Please try again.',
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
      if (userId == null)
        return const AuthResult(success: false, error: 'No user logged in.');

      // update only name fields, we dont touch the rest so dili ma-overwrite
      await _supabase
          .from('user_info')
          .update({'first_name': firstName, 'last_name': lastName})
          .eq('id', userId);

      return const AuthResult(success: true);
    } catch (e) {
      debugPrint('[AUTH] Update Profile Error: $e');
      // return generic message so the raw error dont scare the user
      return const AuthResult(
        success: false,
        error: 'Profile update failed. Please try again.',
      );
    }
  }

  // UPDATE EMAIL
  // update the user email in Supabase Auth and user_info table
  Future<AuthResult> updateEmail(String newEmail) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null)
        return const AuthResult(success: false, error: 'No user logged in.');

      // Check if new email is already used by someone else
      final existingEmail = await _supabase
          .from('user_info')
          .select('id')
          .eq('email', newEmail)
          .maybeSingle();

      if (existingEmail != null && existingEmail['id'] != userId) {
        return const AuthResult(
          success: false,
          error: 'This email is already in use by another account.',
        );
      }

      // 1. Update in Supabase Auth (this sends a confirmation link to the new email)
      await _supabase.auth.updateUser(UserAttributes(email: newEmail));

      // 2. Update in user_info table so the database matches
      await _supabase
          .from('user_info')
          .update({'email': newEmail})
          .eq('id', userId);

      return const AuthResult(success: true);
    } catch (e) {
      debugPrint('[AUTH] Update Email Error: $e');
      return const AuthResult(
        success: false,
        error: 'Email update failed. Ensure the email is not already in use.',
      );
    }
  }

  // 6. FORGOT PASSWORD
  // send a password reset email to the user, pray lang they check their inbox
  Future<AuthResult> sendPasswordResetEmail(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.supabase.ievaluate://reset-password',
      );
      // we always return success here even if email doesnt exist
      // this prevent attacker from knowing which emails are registered, security 101
      return const AuthResult(success: true);
    } on SocketException {
      return const AuthResult(
        success: false,
        error: 'No internet connection. Please check your WiFi or mobile data.',
      );
    } catch (e) {
      debugPrint('[AUTH] Reset Password Error (type): ${e.runtimeType}');
      final msg = e.toString();
      // detect ALL network-related errors (not just SocketException) and surface them to user
      if (_isNetworkError(msg) || msg.contains('Failed host lookup')) {
        return const AuthResult(
          success: false,
          error:
              'No internet connection. Please check your WiFi or mobile data.',
        );
      }
      // for all other errors (e.g. auth service errors) we still return success
      // this prevents attackers from learning which emails are registered — security 101
      return const AuthResult(success: true);
    }
  }

  // 7. UPDATE PASSWORD
  // update the user password directly, this only work when they are already authenticated
  Future<AuthResult> updatePassword(String newPassword) async {
    try {
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
      return const AuthResult(success: true);
    } catch (e) {
      debugPrint('[AUTH] Update Password Error: $e');
      return const AuthResult(
        success: false,
        error: 'Password update failed. Please try again.',
      );
    }
  }

  // 8. FETCH METADATA FOR DROPDOWNS
  // get list of all departments from database, used in signup form dropdowns
  Future<List<String>> getDepartments() async {
    try {
      final List<dynamic> data = await _supabase
          .from('department_name')
          .select('d_name')
          .order(
            'd_name',
            ascending: true,
          ); // sort alphabetically so it look organize
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
