// lib/gatherer/services/stamp.dart
//
// The numbering-machine stamp on the SAST form.
//
// Every paper form gets a stamped number (black ink, evenly spaced digits)
// before the student fills it in. n8n reads it with Gemini; the number is the
// key that stops the same paper form being counted twice in one term:
// (term_id, stamp_no) is unique in sast_all_raw_data_survey.
//
// Rules shared with n8n and the website (Stamp Phase B contract):
//   - digits only, 3 to 12 of them, stored as TEXT exactly as printed —
//     leading zeros are part of the number ("0100005" is not "100005");
//   - a form may have no stamp at all, which is sent as null;
//   - a stamp already saved for the term is refused with HTTP 409
//     {success:false, code:'duplicate_stamp', message, duplicate_of}.
//
// Everything here is pure Dart so it can be unit-tested without a device.
import 'package:intl/intl.dart';

/// Validation and wording for stamp numbers.
class Stamp {
  Stamp._();

  static const int minDigits = 3;
  static const int maxDigits = 12;

  static final RegExp _valid = RegExp(r'^[0-9]{3,12}$');
  static final RegExp _nonDigit = RegExp(r'[^0-9]');

  /// The review reasons that are about the stamp.
  static const String missing = 'stamp_missing';
  static const String unreadable = 'stamp_unreadable';
  static const String multiple = 'multiple_stamps';
  static const String duplicate = 'duplicate_stamp';
  static const String checkFailed = 'stamp_check_failed';

  /// Reasons that need staff to type a stamp (or say there is none) before
  /// the correction can be sent.
  static const Set<String> needsStaffReasons = {missing, unreadable, multiple};

  /// True for a well-formed stamp number (3-12 digits, nothing else).
  static bool isValid(String? value) =>
      value != null && _valid.hasMatch(value);

  /// What staff typed, reduced to its digits. Leading zeros are kept; spaces,
  /// dashes and anything else that is not a digit are dropped (the same as
  /// n8n does with what Gemini reads). Null in, '' out.
  static String normalize(String? input) =>
      (input ?? '').trim().replaceAll(_nonDigit, '');

  /// Why [input] is not an acceptable stamp number, or null when it is.
  /// An empty field is not judged here: whether "no stamp" is allowed depends
  /// on the screen (see FailedScanDetailScreen).
  static String? validationError(String? input) {
    final digits = normalize(input);
    if (digits.isEmpty) return null;
    if (digits.length < minDigits) {
      return 'A stamp number has at least $minDigits digits.';
    }
    if (digits.length > maxDigits) {
      return 'A stamp number has at most $maxDigits digits.';
    }
    return null;
  }

  /// The value sent as `stamp_no`: the digits when valid, null when the field
  /// is empty or the form has no stamp. Callers check [validationError] first.
  static String? toPayload(String? input, {bool noStamp = false}) {
    if (noStamp) return null;
    final digits = normalize(input);
    return isValid(digits) ? digits : null;
  }

  /// The reason code without any ":detail" suffix n8n may append.
  static String reasonCode(Object? raw) {
    final s = (raw ?? '').toString().trim();
    final i = s.indexOf(':');
    return (i >= 0 ? s.substring(0, i) : s).trim().toLowerCase();
  }

  /// Short label for a list chip, or null when [code] is not a stamp reason.
  static String? reasonLabel(Object? code) {
    switch (reasonCode(code)) {
      case missing:
        return 'No stamp found';
      case unreadable:
        return 'Stamp unreadable';
      case multiple:
        return 'Several stamps';
      case duplicate:
        return 'Already scanned';
      case checkFailed:
        return 'Stamp not checked';
      default:
        return null;
    }
  }

  /// Plain-English explanation for staff, or null when [code] is not a stamp
  /// reason.
  static String? reasonText(Object? code) {
    switch (reasonCode(code)) {
      case missing:
        return 'No stamp number was found on this form. Type the number '
            'printed by the numbering stamp, or tick "This form has no stamp".';
      case unreadable:
        return 'The stamp number could not be read clearly. Check the paper '
            'or the photo and type the number.';
      case multiple:
        return 'More than one stamped number was found. Pick the right one '
            'or type it.';
      case duplicate:
        return 'This stamp number is already saved for this term, so this '
            'form was already scanned and is not counted again.';
      case checkFailed:
        return "The stamp check couldn't run; check the stamp number before "
            'crediting.';
      default:
        return null;
    }
  }

  /// Plain-English meaning of `partial_data.stamp_status`.
  static String statusLabel(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'ok':
        return 'Read';
      case 'missing':
        return 'Not found';
      case 'unreadable':
        return 'Unreadable';
      case 'multiple':
        return 'Several found';
      default:
        return 'Not checked';
    }
  }
}

/// The stamp facts of one `failed_scan_queue` row.
class QueueStamp {
  /// The single stamp number read (or set by staff), else null.
  final String? stampNo;

  /// 'gemini', 'staff' or 'override'; null when there is no stamp.
  final String? source;

  /// 'ok', 'missing', 'unreadable' or 'multiple' (null on older rows).
  final String? status;

  /// Valid stamp numbers Gemini saw, in order, without duplicates.
  final List<String> candidates;

  /// The stamp reasons among the row's review_reasons (codes).
  final List<String> reasons;

  /// The already-saved row this one duplicates (DUP object), if any.
  final Map<String, dynamic>? duplicateOf;

  const QueueStamp({
    this.stampNo,
    this.source,
    this.status,
    this.candidates = const [],
    this.reasons = const [],
    this.duplicateOf,
  });

  /// Reads the `stamp_no` / `stamp_source` columns, falling back to the same
  /// keys inside `partial_data` (rows written before the columns existed, or
  /// a select that left them out), plus `partial_data.stamp_status`,
  /// `stamp_candidates` and `duplicate_of`.
  factory QueueStamp.fromRow(Map<String, dynamic> row) {
    final partial = row['partial_data'] is Map
        ? Map<String, dynamic>.from(row['partial_data'] as Map)
        : <String, dynamic>{};

    String? str(Object? v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty || s == 'null') ? null : s;
    }

    final column = str(row['stamp_no']);
    final fromPartial = str(partial['stamp_no']);
    final stampNo = Stamp.isValid(column)
        ? column
        : (Stamp.isValid(fromPartial) ? fromPartial : null);

    final candidates = <String>[];
    final rawCandidates = partial['stamp_candidates'];
    if (rawCandidates is List) {
      for (final c in rawCandidates) {
        final s = str(c);
        if (Stamp.isValid(s) && !candidates.contains(s)) candidates.add(s!);
      }
    }

    final reasons = <String>[];
    final rawReasons = row['review_reasons'];
    if (rawReasons is List) {
      for (final r in rawReasons) {
        final code = Stamp.reasonCode(r);
        if (Stamp.reasonLabel(code) != null && !reasons.contains(code)) {
          reasons.add(code);
        }
      }
    }

    final dup = partial['duplicate_of'];

    return QueueStamp(
      stampNo: stampNo,
      source: stampNo == null
          ? null
          : (str(row['stamp_source']) ?? str(partial['stamp_source'])),
      status: str(partial['stamp_status']),
      candidates: candidates,
      reasons: reasons,
      duplicateOf: dup is Map ? Map<String, dynamic>.from(dup) : null,
    );
  }

  /// True when staff must give a stamp (or say there is none) to submit.
  bool get needsStaffInput =>
      reasons.any(Stamp.needsStaffReasons.contains) ||
      status == 'missing' ||
      status == 'unreadable' ||
      status == 'multiple';

  /// Candidates to offer as one-tap choices (only useful when there are
  /// several, or when the single one was not taken as the stamp).
  List<String> get choices =>
      (candidates.length > 1 || (candidates.isNotEmpty && stampNo == null))
          ? candidates
          : const [];
}

/// The n8n answer `409 {success:false, code:'duplicate_stamp', ...}` to a
/// manual correction whose stamp is already saved for the term.
class DuplicateStampAnswer {
  final String message;
  final String? stampNo;
  final String? submittedDate; // 'YYYY-MM-DD' of the saved row, if known
  final Map<String, dynamic>? duplicateOf;

  const DuplicateStampAnswer({
    required this.message,
    this.stampNo,
    this.submittedDate,
    this.duplicateOf,
  });

  /// Null unless [data] (Map, or a List whose first item is a Map) carries
  /// `code: 'duplicate_stamp'`. The status code is not required to be 409:
  /// the proxy passes n8n's status through, but the body is what decides.
  static DuplicateStampAnswer? tryParse(int statusCode, dynamic data) {
    Map<String, dynamic>? m;
    if (data is Map) {
      m = Map<String, dynamic>.from(data);
    } else if (data is List && data.isNotEmpty && data.first is Map) {
      m = Map<String, dynamic>.from(data.first as Map);
    }
    if (m == null) return null;
    final code = (m['code'] ?? m['reason'] ?? m['error'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (code != Stamp.duplicate) return null;

    final dup = m['duplicate_of'] is Map
        ? Map<String, dynamic>.from(m['duplicate_of'] as Map)
        : null;
    String? str(Object? v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty || s == 'null') ? null : s;
    }

    final date = str(dup?['submitted_date']);
    return DuplicateStampAnswer(
      message: str(m['message']) ??
          'This stamp number is already saved for this term.',
      stampNo: str(dup?['stamp_no']) ?? str(m['stamp_no']),
      submittedDate: (date != null && date.length >= 10)
          ? date.substring(0, 10)
          : date,
      duplicateOf: dup,
    );
  }

  /// [submittedDate] as "Oct 3, 2026" (or as given when it is not a date).
  String? get submittedDateLabel {
    final d = submittedDate;
    if (d == null) return null;
    final parsed = DateTime.tryParse(d);
    return parsed == null ? d : DateFormat('MMM d, yyyy').format(parsed);
  }

  /// What the correction screen shows.
  String get explanation {
    final number = stampNo != null ? 'Stamp $stampNo' : 'This stamp number';
    final date = submittedDateLabel;
    final when = date != null ? ' (saved on $date)' : '';
    return '$number is already saved this term$when, so that form is '
        'already counted. Check the number on the paper and fix it, or '
        'discard this scan if it is the same form.';
  }
}

/// What the phone scan webhook said about an upload that n8n discarded on its
/// own (the form is not counted; nothing for the gatherer to retry).
enum ScanDiscard { duplicateStamp, tooFewAnswers }

class ScanAnswer {
  final ScanDiscard discard;
  final String message;
  final String? stampNo;

  const ScanAnswer(this.discard, this.message, {this.stampNo});

  static const String _autoPrefix = 'discarded automatically';
  static final RegExp _stampInMessage = RegExp(r'stamp\s+([0-9]{3,12})');

  /// Recognises an automatic discard in the n8n answer, else null.
  ///
  /// Duplicate stamp: `auto_rejected: 'duplicate_stamp'`, `duplicate_stamp`
  /// in `review_reasons`, or the message "Discarded automatically: this form
  /// was already scanned (stamp N), so it is not counted.".
  /// Fewer than 5 answers: any other "Discarded automatically: ..." message.
  static ScanAnswer? tryParse(dynamic data) {
    Map<String, dynamic>? m;
    if (data is Map) {
      m = Map<String, dynamic>.from(data);
    } else if (data is List && data.isNotEmpty && data.first is Map) {
      m = Map<String, dynamic>.from(data.first as Map);
    } else if (data is String && data.trim().isNotEmpty) {
      m = {'message': data};
    }
    if (m == null) return null;

    final message = (m['message'] ?? m['review_note'] ?? m['note'] ?? '')
        .toString()
        .trim();
    final lower = message.toLowerCase();
    final autoRejected = (m['auto_rejected'] ?? '').toString().toLowerCase();
    final reasons = m['review_reasons'] is List
        ? (m['review_reasons'] as List).map(Stamp.reasonCode).toList()
        : const <String>[];

    final isDuplicate = autoRejected == Stamp.duplicate ||
        reasons.contains(Stamp.duplicate) ||
        (lower.startsWith(_autoPrefix) && lower.contains('already scanned'));
    if (isDuplicate) {
      final fromField = m['stamp_no']?.toString().trim();
      final stampNo = Stamp.isValid(fromField)
          ? fromField
          : _stampInMessage.firstMatch(lower)?.group(1);
      return ScanAnswer(
        ScanDiscard.duplicateStamp,
        message.isNotEmpty
            ? message
            : 'Discarded automatically: this form was already scanned'
                '${stampNo != null ? ' (stamp $stampNo)' : ''}, so it is not '
                'counted.',
        stampNo: stampNo,
      );
    }
    if (lower.startsWith(_autoPrefix)) {
      return ScanAnswer(ScanDiscard.tooFewAnswers, message);
    }
    return null;
  }

  /// Stored on the local ScanTask as `outcome`.
  String get outcomeCode =>
      discard == ScanDiscard.duplicateStamp ? Stamp.duplicate : 'too_few_answers';
}
