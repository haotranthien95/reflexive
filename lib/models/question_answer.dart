/// One answered question inside a [Session]: the prompt text plus the
/// on-device audio file that answers it.
///
/// [audioPath] is always stored *relative* to the app documents directory
/// (e.g. `recordings/1754575182000.m4a`) and resolved to an absolute path only
/// at play time via `toAbsolutePath()`.
class QuestionAnswer {
  const QuestionAnswer({
    this.id,
    required this.sessionId,
    required this.questionText,
    required this.audioPath,
    required this.createdAt,
  });

  final int? id;
  final int sessionId;
  final String questionText;
  final String audioPath;
  final DateTime createdAt;

  factory QuestionAnswer.fromMap(Map<String, Object?> map) => QuestionAnswer(
        id: map['id'] as int?,
        sessionId: map['session_id'] as int,
        questionText: map['question_text'] as String,
        audioPath: map['audio_path'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'question_text': questionText,
        'audio_path': audioPath,
        'created_at': createdAt.toIso8601String(),
      };
}
