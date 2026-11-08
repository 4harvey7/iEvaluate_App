// lib/core/services/update_service.dart
// In-app updates for the sideloaded APK. The newest row of public.app_releases
// (migration 035) says which build is current; the APK itself lives on
// GitHub Releases. Android only, and a failed check never blocks the app.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One row of public.app_releases.
class AppRelease {
  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String sha256;
  final String? notes;
  final bool force;

  const AppRelease({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.sha256,
    this.notes,
    this.force = false,
  });

  factory AppRelease.fromMap(Map<String, dynamic> m) => AppRelease(
        versionCode: (m['version_code'] as num).toInt(),
        versionName: m['version_name'] as String,
        apkUrl: m['apk_url'] as String,
        sha256: m['sha256'] as String,
        notes: m['notes'] as String?,
        force: m['force'] == true,
      );
}

/// Thrown by [UpdateService.downloadAndInstall]; [message] is shown to the user.
class UpdateException implements Exception {
  final String message;
  const UpdateException(this.message);
  @override
  String toString() => message;
}

class UpdateService {
  static const offlineMessage =
      'You appear to be offline. Check your connection and try again.';

  /// Set by UpdateCheckGate so the startup dialog runs once per app start.
  static bool startupCheckDone = false;

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// True when [releaseCode] is newer than the installed build number.
  /// An unreadable build number never triggers an update.
  static bool isNewer(int releaseCode, String installedBuild) {
    final installed = int.tryParse(installedBuild.trim());
    return installed != null && releaseCode > installed;
  }

  /// Compares a stored hash with a computed hex digest, ignoring case/spaces.
  static bool hashMatches(String expected, String actualHex) =>
      expected.trim().toLowerCase() == actualHex.trim().toLowerCase();

  /// "iEvaluate Version 1.0.0 (build 1)" from the installed package.
  static Future<String> installedVersionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return 'iEvaluate Version ${info.version} (build ${info.buildNumber})';
    } catch (_) {
      return 'iEvaluate';
    }
  }

  /// Newest release if it is newer than the installed build. Never throws:
  /// on failure (offline, table missing) returns an [error] message instead.
  static Future<({AppRelease? release, String? error})> check() async {
    if (!_supported) return (release: null, error: null);
    try {
      final info = await PackageInfo.fromPlatform();
      final row = await Supabase.instance.client
          .from('app_releases')
          .select()
          .order('version_code', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return (release: null, error: null);
      final release = AppRelease.fromMap(row);
      return (
        release: isNewer(release.versionCode, info.buildNumber) ? release : null,
        error: null,
      );
    } on SocketException {
      return (release: null, error: offlineMessage);
    } on http.ClientException {
      return (release: null, error: offlineMessage);
    } catch (e) {
      debugPrint('[UPDATE] check failed: $e');
      return (release: null, error: 'Could not check for updates right now.');
    }
  }

  /// GET [uri], retrying after each of [delays] only on a transient 502/503/504
  /// (GitHub's edge). Any other status is returned as-is.
  @visibleForTesting
  static Future<http.StreamedResponse> sendWithRetry(
    http.Client client,
    Uri uri, {
    List<Duration> delays = const [
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 6),
    ],
  }) async {
    for (var i = 0;; i++) {
      final res = await client.send(http.Request('GET', uri));
      if (i >= delays.length || ![502, 503, 504].contains(res.statusCode)) {
        return res;
      }
      await res.stream.drain<void>();
      await Future<void>.delayed(delays[i]);
    }
  }

  /// Downloads the APK, verifies its SHA-256, then opens the system installer.
  /// [onProgress] gets 0..1, or null when the size is unknown.
  static Future<void> downloadAndInstall(
    AppRelease release,
    void Function(double? progress) onProgress,
  ) async {
    if (!_supported) {
      throw const UpdateException('Updates are only available on Android.');
    }
    final uri = Uri.tryParse(release.apkUrl);
    if (uri == null || uri.scheme != 'https') {
      throw const UpdateException('The update link is not secure (HTTPS only).');
    }

    final file =
        File(p.join((await getTemporaryDirectory()).path, 'update.apk'));
    final client = http.Client();
    try {
      final res = await sendWithRetry(client, uri);
      if (res.statusCode != 200) {
        throw UpdateException('Download failed (HTTP ${res.statusCode}).');
      }
      final total = res.contentLength;
      var received = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(total == null || total == 0 ? null : received / total);
        }
      } finally {
        await sink.close();
      }

      final digest = await sha256.bind(file.openRead()).first;
      if (!hashMatches(release.sha256, digest.toString())) {
        throw const UpdateException(
            'Checksum mismatch: the downloaded file is damaged or not the '
            'official release. Nothing was installed.');
      }
    } catch (e) {
      // Never leave a partial or tampered APK behind.
      if (await file.exists()) await file.delete();
      if (e is UpdateException) rethrow;
      if (e is SocketException || e is http.ClientException) {
        throw const UpdateException(offlineMessage);
      }
      throw UpdateException('Download failed: $e');
    } finally {
      client.close();
    }

    final result = await OpenFilex.open(file.path,
        type: 'application/vnd.android.package-archive');
    if (result.type == ResultType.permissionDenied) {
      throw const UpdateException(
          'Install permission denied. Allow "Install unknown apps" for '
          'iEvaluate in Android Settings, then try again.');
    }
    if (result.type != ResultType.done) {
      throw UpdateException('Could not open the installer: ${result.message}');
    }
  }
}
