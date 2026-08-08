/// A single practice session.
///
/// In Phase 1 a session contains exactly one `question_answers` row; Phase 2
/// adds more rows per session without any schema migration (D-05).
class Session {
  const Session({this.id, required this.createdAt});

  final int? id;
  final DateTime createdAt;

  factory Session.fromMap(Map<String, Object?> map) => Session(
        id: map['id'] as int?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'created_at': createdAt.toIso8601String(),
      };
}
