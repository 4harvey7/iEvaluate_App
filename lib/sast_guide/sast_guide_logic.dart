// lib/sast_guide/sast_guide_logic.dart
// Once-per-semester rule for the SAST Guidelines screen. Local only.
import 'package:shared_preferences/shared_preferences.dart';

String sastGuideAckKey(String userId) => 'sast_guide_ack_$userId';

/// True when the guide should auto-show: a term is known and it differs from
/// the term this user last acknowledged. Unknown term -> never show.
bool sastGuideShouldShow({
  required SharedPreferences prefs,
  required String userId,
  required String? termId,
}) {
  if (userId.isEmpty || termId == null || termId.isEmpty) return false;
  return prefs.getString(sastGuideAckKey(userId)) != termId;
}

Future<void> sastGuideAcknowledge({
  required SharedPreferences prefs,
  required String userId,
  required String termId,
}) async {
  await prefs.setString(sastGuideAckKey(userId), termId);
}
