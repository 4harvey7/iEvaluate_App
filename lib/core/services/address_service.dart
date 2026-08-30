// lib/core/services/address_service.dart
//
// Supplies the barangay list behind the registration address picker, and does
// the matching for the typeahead.
//
// The whole list is fetched once when the registration screen opens -- the same
// moment it already fetches departments and roles -- and filtered in memory
// after that. Roughly a thousand rows of short strings is nothing to hold, and
// filtering locally means suggestions appear as fast as the user types instead
// of one network round trip per keystroke.
//
// If the fetch fails, the list is empty and the picker falls back to plain free
// text. The address is a display-only record, so an unavailable list must never
// be able to block a registration.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One place a person can live, as shown in the picker.
@immutable
class AddressLocation {
  const AddressLocation({
    required this.barangay,
    required this.municipality,
    required this.province,
    this.isCampusArea = false,
  });

  factory AddressLocation.fromRow(Map<String, dynamic> row) {
    return AddressLocation(
      barangay: (row['barangay'] ?? '').toString(),
      municipality: (row['municipality'] ?? '').toString(),
      province: (row['province'] ?? '').toString(),
      isCampusArea: row['is_campus_area'] == true,
    );
  }

  final String barangay;
  final String municipality;
  final String province;

  /// True for the town the campus is in. Sorted to the top, because that is
  /// where nearly all staff live.
  final bool isCampusArea;

  /// What the user sees and what gets stored: "Lamacan, Argao, Cebu".
  String get label => [barangay, municipality, province]
      .where((part) => part.trim().isNotEmpty)
      .join(', ');

  @override
  String toString() => label;

  @override
  bool operator ==(Object other) =>
      other is AddressLocation &&
      other.barangay == barangay &&
      other.municipality == municipality &&
      other.province == province;

  @override
  int get hashCode => Object.hash(barangay, municipality, province);
}

class AddressService {
  AddressService({SupabaseClient? client})
      : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  /// Every known location, campus town first then alphabetical.
  ///
  /// Returns an empty list rather than throwing: the caller degrades to free
  /// text, which is what the field was before this existed.
  Future<List<AddressLocation>> fetchLocations() async {
    try {
      final rows = await _supabase
          .from('address_locations')
          .select('barangay, municipality, province, is_campus_area')
          // Campus town first, then alphabetical inside each group.
          .order('is_campus_area', ascending: false)
          .order('municipality', ascending: true)
          .order('barangay', ascending: true);

      return rows.map<AddressLocation>(AddressLocation.fromRow).toList();
    } catch (e) {
      // Most likely the migration has not been applied, or there is no
      // connection. Neither should stop someone registering.
      debugPrint('[ADDRESS] Could not load locations, falling back to free text: $e');
      return const [];
    }
  }

  /// Suggestions for what the user has typed so far.
  ///
  /// Prefix matches come before mid-word matches, so typing "la" offers
  /// "Lamacan" and "Langtad" before "Talaga" -- otherwise the thing you are
  /// most likely typing gets buried. Within each group the incoming order is
  /// preserved, which keeps the campus town on top.
  static List<AddressLocation> search(
    List<AddressLocation> all,
    String query, {
    int limit = 8,
  }) {
    final q = query.trim().toLowerCase();
    // An empty box offers the campus town rather than nothing at all, so the
    // field advertises that it has suggestions before you type.
    if (q.isEmpty) {
      return all.where((l) => l.isCampusArea).take(limit).toList();
    }

    final prefix = <AddressLocation>[];
    final contains = <AddressLocation>[];
    for (final location in all) {
      final barangay = location.barangay.toLowerCase();
      final label = location.label.toLowerCase();
      if (barangay.startsWith(q)) {
        prefix.add(location);
      } else if (label.contains(q)) {
        contains.add(location);
      }
      // No early exit: a later prefix match should still outrank an earlier
      // contains match.
    }
    return [...prefix, ...contains].take(limit).toList();
  }

  /// Builds the single string stored in `user_info.address`.
  ///
  /// [street] is the house number / street / purok, [locationLabel] whatever the
  /// picker ended up with -- a chosen location or the user's own typing. Either
  /// part may be blank, and the result never has a dangling comma.
  static String compose(String street, String locationLabel) {
    return [street.trim(), locationLabel.trim()]
        .where((part) => part.isNotEmpty)
        .join(', ');
  }
}
