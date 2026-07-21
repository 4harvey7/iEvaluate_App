import 'package:flutter_dotenv/flutter_dotenv.dart';

// Single source of truth for all environment variables.
// To change server IP or any URL: edit .env only — nothing else.
//
// ── Test vs Production mode ────────────────────────────────────────────────
// In .env set USE_N8N_TEST=true  → all webhooks use "webhook-test/" prefix
//                      =false → all webhooks use "webhook/"        prefix
class Env {
  // ── Test mode flag ────────────────────────────────────────────────────────
  /// true  = n8n webhook-test URLs  (click "Test Webhook" in n8n first)
  /// false = n8n production webhook  (workflow must be Active in n8n)
  static bool get useN8nTest =>
      (dotenv.env['USE_N8N_TEST'] ?? 'false').toLowerCase() == 'true';

  /// Automatically returns 'webhook-test' or 'webhook' based on the flag.
  static String get _webhookPrefix =>
      useN8nTest ? 'webhook-test' : 'webhook';

  // ── Supabase ──────────────────────────────────────────────────────────────
  static String get supabaseUrl =>
      dotenv.env['SUPABASE_URL'] ?? _error('SUPABASE_URL');

  static String get supabaseAnonKey =>
      dotenv.env['SUPABASE_ANON_KEY'] ?? _error('SUPABASE_ANON_KEY');

  // ── Base URLs ─────────────────────────────────────────────────────────────
  static String get n8nBaseUrl =>
      dotenv.env['N8N_BASE_URL'] ?? _error('N8N_BASE_URL');

  static String get pythonApiBaseUrl =>
      dotenv.env['PYTHON_API_BASE_URL'] ?? _error('PYTHON_API_BASE_URL');

  // ── Full n8n Webhook URLs ─────────────────────────────────────────────────
  // Paths come from .env but the prefix (webhook vs webhook-test) is
  // swapped automatically by the USE_N8N_TEST flag.

  static String get n8nHealthUrl =>
      '$n8nBaseUrl/$_webhookPrefix/'
      '${_path('N8N_WEBHOOK_HEALTH')}';

  static String get n8nScanUploadUrl =>
      '$n8nBaseUrl/$_webhookPrefix/'
      '${_path('N8N_WEBHOOK_SCAN_UPLOAD')}';

  static String get n8nLinkUploadUrl =>
      '$n8nBaseUrl/$_webhookPrefix/'
      '${_path('N8N_WEBHOOK_LINK_UPLOAD')}';

  static String get n8nCropOcrUrl =>
      '$n8nBaseUrl/$_webhookPrefix/'
      '${_path('N8N_WEBHOOK_CROP_OCR')}';

  static String get n8nManualCorrectionUrl =>
      '$n8nBaseUrl/$_webhookPrefix/'
      '${_path('N8N_WEBHOOK_MANUAL_CORRECTION')}';

  static String get n8nSubjectBulkImportUrl =>
      '$n8nBaseUrl/$_webhookPrefix/'
      '${_path('N8N_WEBHOOK_SUBJECT_BULK_IMPORT')}';

  // ── Full Python API URLs ──────────────────────────────────────────────────
  static String get pythonProcessCropUrl =>
      '$pythonApiBaseUrl/${_path('PYTHON_PROCESS_CROP')}';

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Extracts just the path segment (everything after "webhook/") from .env.
  /// e.g. "webhook/sast-scan-upload" → "sast-scan-upload"
  static String _path(String key) {
    final raw = dotenv.env[key] ?? _error(key);
    // Strip leading "webhook/" or "webhook-test/" if present so the
    // prefix is always applied fresh from _webhookPrefix.
    return raw.replaceFirst(RegExp(r'^webhook(-test)?/'), '');
  }

  static String _error(String key) =>
      throw Exception('Environment variable $key not found in .env file');
}