/// The one place that decides whether a subject code or name about to be saved
/// collides with a subject that already exists.
///
/// This lives outside manage_subjects_screen.dart for one reason: the rule had
/// already been written once, in-line, and still leaked (BUG-2026-TC-A07). The
/// leak was not in the comparison -- that part was right -- but in the
/// CONDITION guarding it, which asked which button had opened the form instead
/// of which subject was being written. Pulled out here the rule is stated once,
/// takes its context as arguments, and is covered by
/// test/sao_admin/subject_duplicate_check_test.dart for every entry point
/// including the ones the original guard skipped.
library;

/// Normalises a subject code for comparison.
///
/// MUST stay identical to the DB index in migration 20240130000018:
/// `upper(btrim(subject_code))`. If the two ever disagree, the app and the
/// database disagree about what counts as taken, and the app's answer is the
/// one the user sees.
String normSubjectCode(Object? v) => (v ?? '').toString().trim().toUpperCase();

/// Normalises a subject name for comparison.
///
/// Deliberately looser than the code rule: this one only raises a warning the
/// admin can override, so it should also catch "Programming  1" against
/// "Programming 1". There is no DB index on subject_name to match -- two
/// departments running a same-named course under different codes is legitimate.
String normSubjectName(Object? v) => (v ?? '')
    .toString()
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ');

/// What the caller should do before saving.
class SubjectDuplicateVerdict {
  /// The subject already holding this code, when it is a DIFFERENT subject
  /// from the one being saved. Non-null means REFUSE the save: a code
  /// identifies exactly one subject across every term.
  final Map<String, dynamic>? codeTakenBy;

  /// A different subject already using this name under a different code.
  /// Non-null means WARN and let the admin decide.
  final Map<String, dynamic>? nameClashWith;

  const SubjectDuplicateVerdict({this.codeTakenBy, this.nameClashWith});

  /// Nothing to say -- save may proceed.
  bool get isClear => codeTakenBy == null && nameClashWith == null;
}

/// Decides whether [code]/[name] may be saved.
///
/// [subjects] is every existing subject row, each carrying at least `id`,
/// `subject_code` and `subject_name`. Comparison happens here rather than as a
/// PostgREST filter because PostgREST cannot express `upper(btrim(...))`, and
/// matching the DB index exactly matters more than the round trip saved.
///
/// [sheetSubjectId] is the subject the form is already operating on, or null
/// when it is creating a new one. This is the whole hinge of the rule: a row
/// matching *itself* is not a duplicate, and a row matching anything else
/// always is. Stating it this way needs no exception for the edit form or the
/// add-instructor form, which is exactly where the previous entry-point-based
/// guard let collisions through.
///
/// [originalName] is the name the anchored subject already carries, or null on
/// a fresh add. A name clash is only worth raising when the admin actually
/// CHANGED the name: two subjects may legitimately share one (via "Create
/// anyway"), and warning about a value that was left exactly as it was would
/// nag on every save for the rest of that subject's life.
SubjectDuplicateVerdict checkSubjectDuplicates({
  required Iterable<Map<String, dynamic>> subjects,
  required String code,
  required String name,
  required String? sheetSubjectId,
  String? originalName,
}) {
  final wantCode = normSubjectCode(code);
  final wantName = normSubjectName(name);

  // "Is this row the subject the form is working on?" Both ids must be present
  // and equal. Comparing them directly would make a row with a missing id read
  // as self on a fresh add (null == null) and wave a real collision through --
  // the same shape of mistake as the entry-point guard this replaced, so it is
  // spelled out rather than left to `!=`.
  bool isSelf(String? rowId) =>
      rowId != null && sheetSubjectId != null && rowId == sheetSubjectId;

  Map<String, dynamic>? codeMatch;
  Map<String, dynamic>? nameMatch;

  for (final row in subjects) {
    final rowId = row['id']?.toString();

    if (normSubjectCode(row['subject_code']) == wantCode) {
      // Whoever holds this code is judged by the code rule alone. If it turns
      // out to be a different subject the save is refused outright, and its
      // name is then beside the point.
      codeMatch ??= row;
      continue;
    }

    // Skipping this form's own subject is what lets the edit form re-save a
    // subject under its existing name without being warned about itself,
    // while still catching a rename onto some other subject's name.
    if (!isSelf(rowId) && normSubjectName(row['subject_name']) == wantName) {
      nameMatch ??= row;
    }
  }

  final codeTaken =
      (codeMatch != null && !isSelf(codeMatch['id']?.toString()))
          ? codeMatch
          : null;

  final nameUnchanged =
      originalName != null && normSubjectName(originalName) == wantName;

  return SubjectDuplicateVerdict(
    codeTakenBy: codeTaken,
    // A refusal outranks a warning: there is nothing to ask about a save that
    // is not going to happen.
    nameClashWith:
        (codeTaken == null && !nameUnchanged) ? nameMatch : null,
  );
}
