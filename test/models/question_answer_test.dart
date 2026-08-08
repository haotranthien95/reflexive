import 'package:englishreflex/models/question_answer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QuestionAnswer', () {
    test('fromMap(toMap()) round-trips every field', () {
      final original = QuestionAnswer(
        id: 3,
        sessionId: 12,
        questionText: 'What did you do this morning?',
        audioPath: 'recordings/1754575182000.m4a',
        createdAt: DateTime.parse('2026-08-07T14:30:00.000'),
      );

      final restored = QuestionAnswer.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.sessionId, original.sessionId);
      expect(restored.questionText, original.questionText);
      expect(restored.audioPath, original.audioPath);
      expect(restored.createdAt, original.createdAt);
    });

    test('toMap omits id when null so SQLite can autoincrement', () {
      final answer = QuestionAnswer(
        sessionId: 1,
        questionText: 'Describe your favourite place to relax.',
        audioPath: 'recordings/1.m4a',
        createdAt: DateTime.parse('2026-08-07T14:30:00'),
      );

      expect(answer.toMap().containsKey('id'), isFalse);
      expect(answer.toMap()['session_id'], 1);
    });

    test('audioPath stays relative — never an absolute device path', () {
      final answer = QuestionAnswer.fromMap({
        'id': 1,
        'session_id': 1,
        'question_text': 'Tell me about a meal you really enjoyed.',
        'audio_path': 'recordings/1754575182000.m4a',
        'created_at': '2026-08-07T14:30:00.000',
      });

      expect(answer.audioPath.startsWith('/'), isFalse);
      expect(answer.audioPath, startsWith('recordings/'));
    });
  });
}
