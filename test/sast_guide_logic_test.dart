import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ievaluateapp_final/sast_guide/sast_guide_logic.dart';

void main() {
  test('shows once per term, per user; unknown term never shows', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    bool show(String u, String? t) =>
        sastGuideShouldShow(prefs: prefs, userId: u, termId: t);

    expect(show('u1', 'T1'), isTrue);
    expect(show('u1', null), isFalse);
    expect(show('u1', ''), isFalse);
    await sastGuideAcknowledge(prefs: prefs, userId: 'u1', termId: 'T1');
    expect(prefs.getString('sast_guide_ack_u1'), 'T1');
    expect(show('u1', 'T1'), isFalse);
    expect(show('u2', 'T1'), isTrue);
    expect(show('u1', 'T2'), isTrue);
  });
}
