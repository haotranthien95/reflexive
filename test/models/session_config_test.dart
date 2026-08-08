import 'package:englishreflex/models/session_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// [SessionConfig] is a logic-free immutable value object, so one
/// construction-and-readback case is the whole file.
///
/// Its worth is not in catching a bug today — there is no code here to be wrong.
/// It is that the field set becomes a compile-time contract: Phase 3 adds
/// Firestore-sourced questions filtered on `topics` and `level`, and this test
/// stops that phase from quietly reshaping the value the whole loop reads. A
/// removed or renamed field fails to compile HERE, next to the reason.
void main() {
  test('carries every session setting through unchanged', () {
    const config = SessionConfig(
      topics: ['Daily life', 'Travel'],
      level: 'B2',
      questionCount: 7,
      thinkingSeconds: 12,
      answerSeconds: 45,
      autoReplay: false,
    );

    expect(config.topics, ['Daily life', 'Travel']);
    expect(config.level, 'B2');
    expect(config.questionCount, 7);
    expect(config.thinkingSeconds, 12);
    expect(config.answerSeconds, 45);
    expect(config.autoReplay, isFalse);
  });

  test('is const-constructible, so a session config is a compile-time value',
      () {
    // The `const` here is the assertion: it fails to compile if a mutable or
    // non-const field is ever added, which is what keeps a session's settings
    // fixed for its whole lifetime (D-18).
    const config = SessionConfig(
      topics: ['Work & study'],
      level: 'B1',
      questionCount: 10,
      thinkingSeconds: 5,
      answerSeconds: 60,
      autoReplay: true,
    );

    expect(config.topics.single, 'Work & study');
  });
}
