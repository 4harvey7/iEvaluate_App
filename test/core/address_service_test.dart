// The matching and composing behind the registration barangay picker.
//
// Pure functions, no Supabase. What matters here is ranking -- typing "la"
// must offer Lamacan before Talaga, or the thing you are most likely typing
// gets buried under alphabetically-earlier mid-word matches.
import 'package:flutter_test/flutter_test.dart';
import 'package:ievaluateapp_final/core/services/address_service.dart';

const argao = <AddressLocation>[
  AddressLocation(barangay: 'Poblacion', municipality: 'Argao', province: 'Cebu', isCampusArea: true),
  AddressLocation(barangay: 'Lamacan', municipality: 'Argao', province: 'Cebu', isCampusArea: true),
  AddressLocation(barangay: 'Langtad', municipality: 'Argao', province: 'Cebu', isCampusArea: true),
  AddressLocation(barangay: 'Talaga', municipality: 'Argao', province: 'Cebu', isCampusArea: true),
  AddressLocation(barangay: 'Talo-ot', municipality: 'Argao', province: 'Cebu', isCampusArea: true),
];

const elsewhere = <AddressLocation>[
  AddressLocation(barangay: 'Poblacion', municipality: 'Dalaguete', province: 'Cebu'),
  AddressLocation(barangay: 'Poblacion', municipality: 'Cebu City', province: 'Cebu'),
];

const all = [...argao, ...elsewhere];

void main() {
  group('AddressLocation', () {
    test('label reads as a Philippine address', () {
      expect(argao[1].label, 'Lamacan, Argao, Cebu');
    });

    test('a missing part does not leave a dangling comma', () {
      const partial = AddressLocation(
        barangay: 'Lamacan',
        municipality: 'Argao',
        province: '',
      );
      expect(partial.label, 'Lamacan, Argao');
    });

    test('equality is by place, not by identity', () {
      // Two rows for the same place must not both appear as options.
      const a = AddressLocation(barangay: 'Lamacan', municipality: 'Argao', province: 'Cebu');
      const b = AddressLocation(
          barangay: 'Lamacan', municipality: 'Argao', province: 'Cebu', isCampusArea: true);
      expect(a, b);
      expect({a, b}.length, 1);
    });
  });

  group('search ranking', () {
    test('prefix matches come before mid-word matches', () {
      // "la" starts Lamacan and Langtad, and appears mid-word in Talaga and in
      // "PobLAcion". The two prefix hits are what the user is actually typing,
      // so they must lead.
      final results = AddressService.search(all, 'la');
      final names = results.map((r) => r.barangay).toList();

      expect(names.sublist(0, 2), ['Lamacan', 'Langtad']);
      expect(names, contains('Talaga'));
      // Talo-ot is t-a-l-o: no "la" anywhere, so it is correctly absent.
      expect(names, isNot(contains('Talo-ot')));
    });

    test('a later prefix match still outranks an earlier mid-word match', () {
      // Talaga appears before Langtad in the source list, so a naive
      // single-pass filter would put it first.
      final results = AddressService.search([argao[3], argao[2]], 'la');
      expect(results.first.barangay, 'Langtad');
    });

    test('matches the municipality and province too', () {
      final results = AddressService.search(all, 'dalaguete');
      expect(results, hasLength(1));
      expect(results.first.municipality, 'Dalaguete');
    });

    test('is case and whitespace insensitive', () {
      expect(AddressService.search(all, '  LAMACAN '), isNotEmpty);
      expect(AddressService.search(all, 'lamacan').first.barangay, 'Lamacan');
    });

    test('an empty box still offers the campus town', () {
      // So the field advertises that it has suggestions before you type.
      final results = AddressService.search(all, '');
      expect(results, isNotEmpty);
      expect(results.every((r) => r.isCampusArea), isTrue);
    });

    test('no match returns nothing rather than everything', () {
      // Nothing found means the user types their own; offering unrelated
      // places would be worse than offering none.
      expect(AddressService.search(all, 'zzzz'), isEmpty);
    });

    test('respects the limit', () {
      expect(AddressService.search(all, 'a', limit: 2), hasLength(2));
    });

    test('an empty list is not an error', () {
      // The fetch failed or the migration has not run: the field degrades to
      // plain free text, which is what it was before.
      expect(AddressService.search(const [], 'lamacan'), isEmpty);
      expect(AddressService.search(const [], ''), isEmpty);
    });
  });

  group('compose', () {
    test('joins street and location', () {
      expect(
        AddressService.compose('Purok 3', 'Lamacan, Argao, Cebu'),
        'Purok 3, Lamacan, Argao, Cebu',
      );
    });

    test('trims stray whitespace', () {
      expect(
        AddressService.compose('  Purok 3  ', '  Lamacan, Argao, Cebu '),
        'Purok 3, Lamacan, Argao, Cebu',
      );
    });

    test('a blank half leaves no dangling comma', () {
      expect(AddressService.compose('', 'Lamacan, Argao, Cebu'), 'Lamacan, Argao, Cebu');
      expect(AddressService.compose('Purok 3', ''), 'Purok 3');
      expect(AddressService.compose('   ', '  '), '');
    });
  });
}
