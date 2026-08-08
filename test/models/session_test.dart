import 'package:englishreflex/models/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Session', () {
    test('fromMap(toMap()) round-trips every field', () {
      final original = Session(
        id: 7,
        createdAt: DateTime.parse('2026-08-07T14:30:00.000'),
      );

      final restored = Session.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.createdAt, original.createdAt);
    });

    test('toMap omits id when null so SQLite can autoincrement', () {
      final session = Session(createdAt: DateTime.parse('2026-08-07T14:30:00'));

      expect(session.toMap().containsKey('id'), isFalse);
      expect(session.toMap()['created_at'], '2026-08-07T14:30:00.000');
    });

    test('fromMap reads a row shaped like the sessions table', () {
      final restored = Session.fromMap({
        'id': 1,
        'created_at': '2026-08-07T09:15:30.000',
      });

      expect(restored.id, 1);
      expect(restored.createdAt, DateTime.parse('2026-08-07T09:15:30.000'));
    });
  });
}
