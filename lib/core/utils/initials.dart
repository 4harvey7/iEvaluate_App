/// Avatar initials for a full display name: first word + last word.
///
/// A middle name (or a two-word first name) is skipped on purpose:
/// "Rodz Harvey Licayan" gives "RL". Every avatar (drawers, every Settings
/// card, Live System Metrics) must use this so one account never shows two
/// different sets of initials (DEF-05, DEF-R8, DEF-V5).
String initialsOf(String fullName) {
  final words = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first[0].toUpperCase();
  return '${words.first[0]}${words.last[0]}'.toUpperCase();
}
