import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/utils/initials.dart';

void main() {
  test('first word + last word, so drawer and Settings agree (DEF-R8)', () {
    // Two-word first name: the drawer used to show the first TWO words.
    expect(initialsOf('Dan Harvey Jones'), 'DJ');
    expect(initialsOf('rodz licayan'), 'RL');
    expect(initialsOf('  Solo  '), 'S');
    expect(initialsOf(''), '?');
  });

  test('Settings cards pass first + last name and get the drawer initials (DEF-V5)', () {
    // first_name "UAT Test", last_name "Throwaway Alpha": Settings showed "UT".
    expect(initialsOf('UAT Test Throwaway Alpha'), 'UA');
    expect(initialsOf(' '), '?'); // name not loaded yet
  });
}
