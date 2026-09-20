// lib/core/services/automation_service.dart
//
// ── Automation & n8n Gateway ──────────────────────────────────────────────────
// Shields the backend IP from reverse engineering and network sniffing.
//
// Instead of making unauthenticated HTTP calls directly to the server IP
// (http://5.104.84.162:5678), all requests route through the Supabase Edge Function
// `n8n-proxy`. The Edge Function verifies the user's session JWT and role,
// attaches secure headers, and forwards requests internally.
//
// The raw server IP is NEVER exposed inside the compiled APK/IPA.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env.dart';

class AutomationResponse {
  final bool isSuccess;
  final int statusCode;
  final dynamic data;
  final String? errorMessage;

  AutomationResponse({
    required this.isSuccess,
    required this.statusCode,
    this.data,
    this.errorMessage,
  });
}

class AutomationService {
  AutomationService._();
  static final AutomationService instance = AutomationService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Executes an automation action.
  /// Uses the secure Supabase Edge Function proxy by default so the server IP is hidden.
  Future<AutomationResponse> invokeAction({
    required String action,
    Map<String, dynamic>? payload,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    // If explicitly configured for direct local development (e.g. localhost:5678)
    if (Env.useDirectN8n && Env.n8nBaseUrl.isNotEmpty) {
      return _invokeDirect(action: action, payload: payload, timeout: timeout);
    }

    try {
      final response = await _supabase.functions.invoke(
        'n8n-proxy',
        body: {
          'action': action,
          'payload': payload ?? {},
        },
      ).timeout(timeout);

      final status = response.status;
      final data = response.data;

      if (status >= 200 && status < 300) {
        return AutomationResponse(
          isSuccess: true,
          statusCode: status,
          data: data,
        );
      } else {
        final errorMsg = data is Map ? (data['error'] ?? data['message']) : data?.toString();
        return AutomationResponse(
          isSuccess: false,
          statusCode: status,
          data: data,
          errorMessage: errorMsg?.toString() ?? 'Server error ($status)',
        );
      }
    } on FunctionException catch (fe) {
      debugPrint('[AutomationService] Edge function error: ${fe.status} ${fe.details}');
      final details = fe.details;
      String? errorMsg;
      if (details is Map) {
        errorMsg = details['error']?.toString() ?? details['message']?.toString();
      }
      return AutomationResponse(
        isSuccess: false,
        statusCode: fe.status,
        data: details,
        errorMessage: errorMsg ?? fe.reasonPhrase ?? 'Automation gateway error',
      );
    } catch (e) {
      debugPrint('[AutomationService] Exception: $e');
      return AutomationResponse(
        isSuccess: false,
        statusCode: 500,
        errorMessage: e.toString(),
      );
    }
  }

  /// Direct fallback only used when `USE_DIRECT_N8N=true` is set for local testing.
  Future<AutomationResponse> _invokeDirect({
    required String action,
    Map<String, dynamic>? payload,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    try {
      final url = _directUrlForAction(action);
      if (url.isEmpty) {
        return AutomationResponse(
          isSuccess: false,
          statusCode: 400,
          errorMessage: 'Unknown direct action: $action',
        );
      }

      final isGet = action == 'health' || action == 'health-check';
      final uri = Uri.parse(url);

      final http.Response res;
      if (isGet) {
        res = await http.get(uri).timeout(timeout);
      } else {
        res = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload ?? {}),
        ).timeout(timeout);
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = res.body;
      }

      return AutomationResponse(
        isSuccess: res.statusCode >= 200 && res.statusCode < 300,
        statusCode: res.statusCode,
        data: decoded,
        errorMessage: res.statusCode >= 400 ? 'HTTP ${res.statusCode}: ${res.body}' : null,
      );
    } catch (e) {
      return AutomationResponse(
        isSuccess: false,
        statusCode: 500,
        errorMessage: e.toString(),
      );
    }
  }

  String _directUrlForAction(String action) {
    switch (action) {
      case 'health':
      case 'health-check':
        return Env.n8nHealthUrl;
      case 'scan-upload':
        return Env.n8nScanUploadUrl;
      case 'link-upload':
        return Env.n8nLinkUploadUrl;
      case 'crop-ocr':
        return Env.n8nCropOcrUrl;
      case 'manual-correction':
        return Env.n8nManualCorrectionUrl;
      case 'bulk-import':
        return Env.n8nSubjectBulkImportUrl;
      case 'import-error-correction':
        return Env.n8nImportErrorCorrectionUrl;
      default:
        return '';
    }
  }

  // ── Convenience Methods ────────────────────────────────────────────────────

  Future<bool> checkHealth() async {
    final res = await invokeAction(
      action: 'health-check',
      timeout: const Duration(seconds: 8),
    );
    return res.isSuccess;
  }

  Future<AutomationResponse> uploadScan(Map<String, dynamic> payload) {
    return invokeAction(
      action: 'scan-upload',
      payload: payload,
      timeout: const Duration(seconds: 60),
    );
  }

  Future<AutomationResponse> uploadLink(Map<String, dynamic> payload) {
    return invokeAction(
      action: 'link-upload',
      payload: payload,
      timeout: const Duration(seconds: 120),
    );
  }

  Future<AutomationResponse> submitManualCorrection(Map<String, dynamic> payload) {
    return invokeAction(
      action: 'manual-correction',
      payload: payload,
      timeout: const Duration(seconds: 45),
    );
  }

  Future<AutomationResponse> submitImportErrorCorrection(Map<String, dynamic> payload) {
    return invokeAction(
      action: 'import-error-correction',
      payload: payload,
      timeout: const Duration(seconds: 45),
    );
  }

  Future<AutomationResponse> bulkImportSubjects(Map<String, dynamic> payload) {
    return invokeAction(
      action: 'bulk-import',
      payload: payload,
      timeout: const Duration(seconds: 60),
    );
  }
}
