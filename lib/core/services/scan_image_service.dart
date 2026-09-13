// lib/core/services/scan_image_service.dart
// Centralised helper for loading a scan image from the scan_error_images table.
// Both the Gatherer and SAO-Admin review screens share this logic so any
// future change only needs touching in one place.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ScanImageService {
  ScanImageService._(); // static-only class, no instances

  /// Fetches raw image bytes for a scan record from [scan_error_images].
  ///
  /// [scanImageId] is the UUID value of the scan_image_id FK column on either
  /// failed_scan_queue or import_errors. Returns null when:
  ///   - scanImageId is null or empty (record has no image)
  ///   - the row does not exist in scan_error_images
  ///   - image_base64 is blank
  ///   - any network or decode error occurs
  ///
  /// Never throws -- callers can safely treat null as no image available.
  static Future<Uint8List?> fetchScanImageBytes(
    SupabaseClient supabase,
    String? scanImageId,
  ) async {
    if (scanImageId == null || scanImageId.trim().isEmpty) return null;

    try {
      final result = await supabase
          .from('scan_error_images')
          .select('image_base64')
          .eq('id', scanImageId)
          .maybeSingle();

      if (result == null) return null;

      final b64 = result['image_base64']?.toString();
      if (b64 == null || b64.isEmpty) return null;

      return base64Decode(b64);
    } catch (e) {
      debugPrint('[ScanImageService] Failed to load image: $e');
      return null;
    }
  }
}
