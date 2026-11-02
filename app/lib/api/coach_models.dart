/// Who said a coach chat message.
enum ChatRole { user, assistant }

/// One message of the coach conversation, with whatever the coach did while answering.
class ChatMessage {
  const ChatMessage(this.role, this.text, {this.actions = const []});

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    j['role'] == 'assistant' ? ChatRole.assistant : ChatRole.user,
    j['text'] as String,
    actions: [
      for (final a in (j['actions'] as List<dynamic>? ?? const []))
        CoachAction.fromJson(a as Map<String, dynamic>),
    ],
  );

  final ChatRole role;
  final String text;

  /// Cards and notes shown under the text. They stay on the phone; only role and text are sent.
  final List<CoachAction> actions;

  bool get isUser => role == ChatRole.user;

  ChatMessage withActions(List<CoachAction> next) => ChatMessage(role, text, actions: next);

  /// What is stored on the phone.
  Map<String, dynamic> toJson() => {
    'role': role.name,
    'text': text,
    if (actions.isNotEmpty) 'actions': [for (final a in actions) a.toJson()],
  };

  /// What is sent to the server.
  Map<String, dynamic> toWire() => {'role': role.name, 'text': text};
}

/// The coach's answer and the cards it produced.
class CoachReply {
  const CoachReply(this.text, this.actions);

  factory CoachReply.fromJson(Map<String, dynamic> j) => CoachReply(j['reply'] as String, [
    for (final a in (j['actions'] as List<dynamic>? ?? const []))
      CoachAction.fromJson(a as Map<String, dynamic>),
  ]);

  final String text;
  final List<CoachAction> actions;
}

/// One row of a proposal card: what it is, what it is now, and what it would become.
class CoachChangeLine {
  const CoachChangeLine({required this.label, required this.from, required this.to});

  factory CoachChangeLine.fromJson(Map<String, dynamic> j) => CoachChangeLine(
    label: j['label'] as String,
    from: j['from'] as String,
    to: j['to'] as String,
  );

  final String label;
  final String from;
  final String to;

  Map<String, dynamic> toJson() => {'label': label, 'from': from, 'to': to};
}

/// A change the coach proposed. It is only a suggestion until [applied].
class CoachProposal {
  const CoachProposal({
    required this.id,
    required this.kind,
    required this.summary,
    required this.changes,
    required this.why,
    required this.source,
    required this.status,
    required this.expiresAt,
    required this.canUndo,
  });

  factory CoachProposal.fromJson(Map<String, dynamic> j) => CoachProposal(
    id: j['id'] as int,
    kind: j['kind'] as String,
    summary: j['summary'] as String,
    changes: [
      for (final c in (j['changes'] as List<dynamic>? ?? const []))
        CoachChangeLine.fromJson(c as Map<String, dynamic>),
    ],
    why: j['why'] as String? ?? '',
    source: j['source'] as String? ?? '',
    status: j['status'] as String,
    expiresAt: DateTime.parse(j['expiresAt'] as String),
    canUndo: j['canUndo'] as bool? ?? false,
  );

  final int id;
  final String kind;
  final String summary;
  final List<CoachChangeLine> changes;

  /// One plain line on where the figure comes from; empty when there is none.
  final String why;

  /// computed, guideline or stated.
  final String source;

  /// pending, applied, dismissed, undone or expired.
  final String status;
  final DateTime expiresAt;
  final bool canUndo;

  bool get pending => status == 'pending';
  bool get applied => status == 'applied';

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'summary': summary,
    'changes': [for (final c in changes) c.toJson()],
    'why': why,
    'source': source,
    'status': status,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'canUndo': canUndo,
  };
}

/// One short thing the person told the coach.
class CoachFact {
  const CoachFact({required this.id, required this.category, required this.text});

  factory CoachFact.fromJson(Map<String, dynamic> j) =>
      CoachFact(id: j['id'] as int, category: j['category'] as String, text: j['text'] as String);

  final int id;
  final String category;
  final String text;

  Map<String, dynamic> toJson() => {'id': id, 'category': category, 'text': text};
}

/// Something the coach did while answering: a proposal card, or a note that it saved or
/// forgot a fact.
class CoachAction {
  const CoachAction.proposal(CoachProposal this.proposal) : type = 'proposal', fact = null;
  const CoachAction.factSaved(CoachFact this.fact) : type = 'fact_saved', proposal = null;
  const CoachAction.factRemoved(CoachFact this.fact) : type = 'fact_removed', proposal = null;

  factory CoachAction.fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'proposal':
        return CoachAction.proposal(CoachProposal.fromJson(j['proposal'] as Map<String, dynamic>));
      case 'fact_removed':
        return CoachAction.factRemoved(CoachFact.fromJson(j['fact'] as Map<String, dynamic>));
      default:
        return CoachAction.factSaved(CoachFact.fromJson(j['fact'] as Map<String, dynamic>));
    }
  }

  final String type;
  final CoachProposal? proposal;
  final CoachFact? fact;

  Map<String, dynamic> toJson() => {
    'type': type,
    if (proposal != null) 'proposal': proposal!.toJson(),
    if (fact != null) 'fact': fact!.toJson(),
  };
}
