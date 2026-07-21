import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// A simple wrapper to send both success/failure and data back to the UI.
class AuthResult {
  final bool success;
  final String? error;
  final String? role;
  final String? userId; // Add this to hold the Supabase User ID
  const AuthResult({required this.success, this.error, this.role, this.userId});
}

class AuthService {
  // The 'client' is our primary way to talk to Supabase.
  final _supabase = Supabase.instance.client;

  // returns the current session if it exists
  Session? get currentSession => _supabase.auth.currentSession;

  // 1. SIGN UP
  Future<AuthResult> signUp({
    required String firstName,
    required String lastName,
    required String address,
    required String universityId,
    required String institutionalEmail,
    required String departmentName,
    required String roleName,
    required String password,
  }) async {
    debugPrint('--- [AUTH] SIGN UP ATTEMPT START ---');
    debugPrint('Email: $institutionalEmail, Role: $roleName, Dept: $departmentName');

    try {
      // STEP 1: Create the user in Supabase Auth
      final authResponse = await _supabase.auth.signUp(
        email: institutionalEmail,
        password: password,
      );

      if (authResponse.user == null) {
        debugPrint('[AUTH] Error: Auth response user is null');
        return const AuthResult(success: false, error: 'Registration failed.');
      }

      final String userId = authResponse.user!.id;
      debugPrint('[AUTH] Auth account created! UserID: $userId');

      // STEP 2: Find the Role ID
      debugPrint('[AUTH] Lookup role: "$roleName"');
      final roleData = await _supabase
          .from('roles')
          .select('id')
          .eq('Roles', roleName)
          .maybeSingle();

      if (roleData == null) {
        debugPrint('[AUTH] Error: Role "$roleName" not found.');
        return AuthResult(success: false, error: 'Role "$roleName" not found.');
      }
      final int roleId = roleData['id'];
      debugPrint('[AUTH] Found Role ID: $roleId');

      // STEP 3: Handle Department (Skip for SAO roles)
      bool isSao = roleName.toUpperCase().contains('SAO');
      int? departmentId;

      if (!isSao) {
        debugPrint('[AUTH] Lookup department: "$departmentName"');
        final deptData = await _supabase
            .from('department_name')
            .select('id')
            .eq('d_name', departmentName)
            .maybeSingle();

        if (deptData == null) {
          debugPrint('[AUTH] Error: Department "$departmentName" not found.');
          return AuthResult(success: false, error: 'Department "$departmentName" not found.');
        }
        departmentId = deptData['id'];
        debugPrint('[AUTH] Found Department ID: $departmentId');
      }

      // STEP 4: Insert into 'user_info'
      debugPrint('[AUTH] Inserting user profile into user_info...');
      await _supabase.from('user_info').insert({
        'id': userId,
        'first_name': firstName,
        'last_name': lastName,
        'address': address,
        'email': institutionalEmail,
        'account_status': 'pending', // All accounts require admin approval
        'university_id': universityId,
      });

      // STEP 5: Link user to the correct table based on role
      if (isSao) {
        debugPrint('[AUTH] Linking user to Sao_users...');
        await _supabase.from('Sao_users').insert({
          'user_id': userId,
          'role_id': roleId, // Fixed: schema uses 'role_id' singular
        });
      } else {
        debugPrint('[AUTH] Linking user to department_table...');
        await _supabase.from('department_table').insert({
          'user_id': userId,
          'Department_name_ID': departmentId,
          'roles': roleId, // Department table uses roles
        });
      }

      debugPrint('--- [AUTH] SIGN UP SUCCESS ---');
      return const AuthResult(success: true);
    } on SocketException {
      debugPrint('[AUTH] No internet connection during sign up.');
      return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
    } catch (e) {
      debugPrint('[AUTH] !!! SIGN UP ERROR !!!');
      debugPrint('Error details: $e');
      final msg = e.toString();
      if (msg.contains('SocketException') || msg.contains('Failed host lookup') || msg.contains('errno = 7')) {
        return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
      }
      return AuthResult(success: false, error: 'Registration failed. Please try again.');
    }
  }

  // 2. SIGN IN
  Future<AuthResult> signIn({
    required String idOrEmail,
    required String password,
  }) async {
    debugPrint('--- [AUTH] SIGN IN ATTEMPT START ---');
    debugPrint('Identifier: $idOrEmail');

    try {
      String emailToUse = idOrEmail;

      // 1. Resolve email from University ID if needed
      if (!idOrEmail.contains('@')) {
        debugPrint('[AUTH] Searching for email by University ID...');
        final userSearch = await _supabase
            .from('user_info')
            .select('email')
            .eq('university_id', idOrEmail)
            .maybeSingle();

        if (userSearch == null) {
          debugPrint('[AUTH] Error: University ID not found.');
          return const AuthResult(success: false, error: 'User ID not found.');
        }
        emailToUse = userSearch['email'];
      }

      // 2. Login with Supabase Auth
      debugPrint('[AUTH] Attempting password authentication...');
      final response = await _supabase.auth.signInWithPassword(
        email: emailToUse,
        password: password,
      );
      debugPrint('[AUTH] Auth successful.');

      // 3. Fetch Role and Status
      final String uid = response.user!.id;
      debugPrint('[AUTH] Fetching role and approval status for UID: $uid');
      String? role;
      String? status;

      // Step A: Check department_table (Instructors)
      debugPrint('[AUTH] Checking department_table...');
      var userData = await _supabase
          .from('department_table')
          .select('user_info!user_id(account_status), roles!roles(Roles)')
          .eq('user_id', uid)
          .maybeSingle();

      if (userData != null) {
        debugPrint('[AUTH] User found in department_table');
        final ui = userData['user_info'];
        status = ui is List ? (ui.isNotEmpty ? ui[0]['account_status'] : null) : ui?['account_status'];
        final r = userData['roles'];
        role = r is List ? (r.isNotEmpty ? r[0]['Roles'] : null) : r?['Roles'];
      } else {
        // Step B: Check Sao_users (Admins/Staff)
        debugPrint('[AUTH] User not in department_table. Checking Sao_users...');
        var saoData = await _supabase
            .from('Sao_users')
            .select('user_info!user_id(account_status), roles!role_id(Roles)')
            .eq('user_id', uid)
            .maybeSingle();

        if (saoData != null) {
          debugPrint('[AUTH] User found in Sao_users');
          final ui = saoData['user_info'];
          status = ui is List ? (ui.isNotEmpty ? ui[0]['account_status'] : null) : ui?['account_status'];
          final r = saoData['roles'];
          role = r is List ? (r.isNotEmpty ? r[0]['Roles'] : null) : r?['Roles'];
        } else {
          debugPrint('[AUTH] User not found in Sao_users either.');
        }
      }

      // Validation
      if (role == null || status == null) {
        debugPrint('[AUTH] Error: Role or Status missing. Role: $role, Status: $status');
        await signOut();
        return const AuthResult(success: false, error: 'User profile incomplete.');
      }

      debugPrint('[AUTH] Status: $status, Role: $role');
      if (status != 'approved') {
        debugPrint('[AUTH] Blocked: Account status is $status');
        await signOut();
        return const AuthResult(success: false, error: 'Account pending admin approval.');
      }

      debugPrint('--- [AUTH] SIGN IN SUCCESS ---');
      return AuthResult(success: true, role: role, userId: response.user!.id);
    } on AuthException catch (e) {
      debugPrint('[AUTH] Supabase Auth Error: ${e.message}');
      // Supabase SDK wraps SocketException inside AuthException — check for it first
      if (_isNetworkError(e.message)) {
        return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
      }
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid login') || msg.contains('invalid credentials') || msg.contains('email not confirmed')) {
        return const AuthResult(success: false, error: 'Incorrect email or password. Please try again.');
      }
      if (msg.contains('too many requests') || msg.contains('rate limit')) {
        return const AuthResult(success: false, error: 'Too many attempts. Please wait a moment and try again.');
      }
      return AuthResult(success: false, error: e.message);
    } on SocketException {
      debugPrint('[AUTH] No internet (SocketException).');
      return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
    } catch (e) {
      debugPrint('[AUTH] Unknown Error: $e');
      if (_isNetworkError(e.toString())) {
        return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
      }
      return const AuthResult(success: false, error: 'Sign in failed. Please check your credentials and try again.');
    }
  }

  /// Fetches the user's name and other info from user_info.
  Future<Map<String, dynamic>?> getUserInfo(String uid) async {
    try {
      final data = await _supabase
          .from('user_info')
          .select('first_name, last_name, university_id, email')
          .eq('id', uid)
          .maybeSingle();
      return data;
    } catch (e) {
      debugPrint('[AUTH] Error fetching user info: $e');
      return null;
    }
  }

  /// Fetches the role and status for a given user ID.
  /// Returns a map with 'role' and 'status' or null if not found.
  Future<Map<String, String?>?> getUserProfile(String uid) async {
    try {
      String? role;
      String? status;

      // Check department_table (Instructors)
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
        // Check Sao_users (Admins/Staff)
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

      if (role != null && status != null) {
        return {'role': role, 'status': status};
      }
      return null;
    } catch (e) {
      debugPrint('[AUTH] Error fetching user profile: $e');
      return null;
    }
  }

  // 3. SIGN OUT
  Future<void> signOut() async {
    debugPrint('[AUTH] User signing out...');
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('[AUTH] Error during signOut: $e');
    }
  }

  // 4. DELETE ACCOUNT
  Future<AuthResult> deleteAccount() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return const AuthResult(success: false, error: 'No user logged in.');

      debugPrint('[AUTH] Requesting account deletion for: $userId');
      // We use an edge function because deleting from auth.users requires service role
      await _supabase.functions.invoke('delete-user', body: {'userId': userId});
      
      await signOut();
      return const AuthResult(success: true);
    } catch (e) {
      debugPrint('[AUTH] Delete Account Error: $e');
      return AuthResult(success: false, error: e.toString());
    }
  }

  // 5. UPDATE PROFILE
  Future<AuthResult> updateProfile({
    required String firstName,
    required String lastName,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return const AuthResult(success: false, error: 'No user logged in.');

      await _supabase.from('user_info').update({
        'first_name': firstName,
        'last_name': lastName,
      }).eq('id', userId);

      return const AuthResult(success: true);
    } catch (e) {
      return AuthResult(success: false, error: e.toString());
    }
  }

  // 6. FORGOT PASSWORD
  Future<AuthResult> sendPasswordResetEmail(String email) async {
    try {
      debugPrint('[AUTH] Requesting password reset for: $email');
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'io.supabase.ievaluate://reset-password',
      );
      return const AuthResult(success: true);
    } on SocketException {
      return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
    } catch (e) {
      debugPrint('[AUTH] Reset Password Error: $e');
      final msg = e.toString();
      if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
        return const AuthResult(success: false, error: 'No internet connection. Please check your WiFi or mobile data.');
      }
      return AuthResult(success: false, error: 'Could not send reset email. Please try again.');
    }
  }

  // 7. UPDATE PASSWORD
  Future<AuthResult> updatePassword(String newPassword) async {
    try {
      debugPrint('[AUTH] Updating password for current user...');
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      return const AuthResult(success: true);
    } catch (e) {
      debugPrint('[AUTH] Update Password Error: $e');
      return AuthResult(success: false, error: e.toString());
    }
  }

  // 8. FETCH METADATA FOR DROPDOWNS
  Future<List<String>> getDepartments() async {
    try {
      final List<dynamic> data = await _supabase
          .from('department_name')
          .select('d_name')
          .order('d_name', ascending: true);
      return data.map((e) => e['d_name'] as String).toList();
    } catch (e) {
      debugPrint('[AUTH] Error fetching departments: $e');
      return [];
    }
  }

  Future<List<String>> getRoles() async {
    try {
      final List<dynamic> data = await _supabase
          .from('roles')
          .select('Roles')
          .order('Roles', ascending: true);
      return data.map((e) => e['Roles'] as String).toList();
    } catch (e) {
      debugPrint('[AUTH] Error fetching roles: $e');
      return [];
    }
  }

  /// Returns true if the error string indicates a network/connectivity failure.
  /// Supabase SDK often wraps SocketException inside AuthException or ClientException,
  /// so we check the message text rather than relying on the exception type alone.
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
