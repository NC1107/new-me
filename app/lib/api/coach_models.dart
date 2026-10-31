/// Who said a coach chat message.
enum ChatRole { user, assistant }

/// One message of the coach conversation.
class ChatMessage {
  const ChatMessage(this.role, this.text);

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    j['role'] == 'assistant' ? ChatRole.assistant : ChatRole.user,
    j['text'] as String,
  );

  final ChatRole role;
  final String text;

  bool get isUser => role == ChatRole.user;

  Map<String, dynamic> toJson() => {'role': role.name, 'text': text};
}
