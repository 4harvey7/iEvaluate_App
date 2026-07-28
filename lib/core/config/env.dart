// lib/core/config/env.dart
//
// ── How secrets are injected ──────────────────────────────────────────────────
// Secrets are NO LONGER bundled as a .env asset file inside the APK/IPA.
// They are compiled in as Dart constants via:
//
//   flutter run  --dart-define-from-file=.env.json
//   flutter build apk --dart-define-from-file=.env.json
//   flutter build ios --dart-define-from-file=.env.json
//
// Create a local `.env.json` file (already git-ignored) with this structure:
// {
//   "SUPABASE_URL": "https://xxxx.supabase.co",
//   "SUPABASE_ANON_KEY": "eyJ...",
//   "N8N_BASE_URL": "http://192.168.x.x:5678",
//   "PYTHON_API_BASE_URL": "http://192.168.x.x:5000",
//   "USE_N8N_TEST": "true",
//   "N8N_WEBHOOK_HEALTH": "webhook/health-check",
//   "N8N_WEBHOOK_SCAN_UPLOAD": "webhook/sast-scan-upload",
//   "N8N_WEBHOOK_LINK_UPLOAD": "webhook/sast-link-upload",
//   "N8N_WEBHOOK_CROP_OCR": "webhook/sast-crop-ocr",
//   "N8N_WEBHOOK_MANUAL_CORRECTION": "webhook/sast-manual-correction",
//   "N8N_WEBHOOK_SUBJECT_BULK_IMPORT": "webhook/subject-bulk-import",
//   "N8N_WEBHOOK_IMPORT_ERROR_CORRECTION": "webhook/import-error-correction",
//   "PYTHON_PROCESS_CROP": "process-crop"
// }
//
// The .env.json file is listed in .gitignore and is NEVER committed.
// ─────────────────────────────────────────────────────────────────────────────

class Env {
  // ── Test mode flag ─────────────────────────────────────────────────────────
  /// true  = n8n webhook-test URLs  (click "Test Webhook" in n8n first)
  /// false = n8n production webhook  (workflow must be Active in n8n)
  static const bool useN8nTest =
      String.fromEnvironment('USE_N8N_TEST', defaultValue: 'false') == 'true';

  /// Automatically returns 'webhook-test' or 'webhook' based on the flag.
  static String get _webhookPrefix =>
      useN8nTest ? 'webhook-test' : 'webhook';

  // ── Supabase ───────────────────────────────────────────────────────────────
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');

  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  // ── Base URLs ──────────────────────────────────────────────────────────────
  static const String n8nBaseUrl =
      String.fromEnvironment('N8N_BASE_URL', defaultValue: '');

  static const String pythonApiBaseUrl =
      String.fromEnvironment('PYTHON_API_BASE_URL', defaultValue: '');

  // ── Full n8n Webhook URLs ──────────────────────────────────────────────────
  static String get n8nHealthUrl =>
      '$n8nBaseUrl/$_webhookPrefix/${_path('N8N_WEBHOOK_HEALTH')}';

  static String get n8nScanUploadUrl =>
      '$n8nBaseUrl/$_webhookPrefix/${_path('N8N_WEBHOOK_SCAN_UPLOAD')}';

  static String get n8nLinkUploadUrl =>
      '$n8nBaseUrl/$_webhookPrefix/${_path('N8N_WEBHOOK_LINK_UPLOAD')}';

  static String get n8nCropOcrUrl =>
      '$n8nBaseUrl/$_webhookPrefix/${_path('N8N_WEBHOOK_CROP_OCR')}';

  static String get n8nManualCorrectionUrl =>
      '$n8nBaseUrl/$_webhookPrefix/${_path('N8N_WEBHOOK_MANUAL_CORRECTION')}';

  static String get n8nSubjectBulkImportUrl =>
      '$n8nBaseUrl/$_webhookPrefix/${_path('N8N_WEBHOOK_SUBJECT_BULK_IMPORT')}';

  static String get n8nImportErrorCorrectionUrl =>
      '$n8nBaseUrl/$_webhookPrefix/${_path('N8N_WEBHOOK_IMPORT_ERROR_CORRECTION')}';

  // ── Full Python API URLs ───────────────────────────────────────────────────
  static String get pythonProcessCropUrl =>
      '$pythonApiBaseUrl/${_path('PYTHON_PROCESS_CROP')}';

  // ── Helpers ────────────────────────────────────────────────────────────────

  static const _rawWebhookPaths = <String, String>{
    'N8N_WEBHOOK_HEALTH':
        String.fromEnvironment('N8N_WEBHOOK_HEALTH', defaultValue: 'webhook/health-check'),
    'N8N_WEBHOOK_SCAN_UPLOAD':
        String.fromEnvironment('N8N_WEBHOOK_SCAN_UPLOAD', defaultValue: 'webhook/sast-scan-upload'),
    'N8N_WEBHOOK_LINK_UPLOAD':
        String.fromEnvironment('N8N_WEBHOOK_LINK_UPLOAD', defaultValue: 'webhook/sast-link-upload'),
    'N8N_WEBHOOK_CROP_OCR':
        String.fromEnvironment('N8N_WEBHOOK_CROP_OCR', defaultValue: 'webhook/sast-crop-ocr'),
    'N8N_WEBHOOK_MANUAL_CORRECTION':
        String.fromEnvironment('N8N_WEBHOOK_MANUAL_CORRECTION', defaultValue: 'webhook/sast-manual-correction'),
    'N8N_WEBHOOK_SUBJECT_BULK_IMPORT':
        String.fromEnvironment('N8N_WEBHOOK_SUBJECT_BULK_IMPORT', defaultValue: 'webhook/subject-bulk-import'),
    'N8N_WEBHOOK_IMPORT_ERROR_CORRECTION':
        String.fromEnvironment('N8N_WEBHOOK_IMPORT_ERROR_CORRECTION', defaultValue: 'webhook/import-error-correction'),
    'PYTHON_PROCESS_CROP':
        String.fromEnvironment('PYTHON_PROCESS_CROP', defaultValue: 'process-crop'),
  };

  /// Strips any leading "webhook/" or "webhook-test/" prefix so the
  /// correct prefix is always injected fresh via [_webhookPrefix].
  static String _path(String key) {
    final raw = _rawWebhookPaths[key] ?? '';
    return raw.replaceFirst(RegExp(r'^webhook(-test)?/'), '');
  }
}