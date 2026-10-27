class UserSummary {
  const UserSummary({required this.id, required this.name, required this.color});

  factory UserSummary.fromJson(Map<String, dynamic> j) => UserSummary(
    id: (j['id'] as num).toInt(),
    name: j['name'] as String? ?? '',
    color: j['color'] as String? ?? '',
  );

  final int id;
  final String name;
  final String color;
}

class ServerInfo {
  const ServerInfo({required this.name, required this.initialized, required this.users});

  factory ServerInfo.fromJson(Map<String, dynamic> j) => ServerInfo(
    name: j['name'] as String? ?? '',
    initialized: j['initialized'] as bool? ?? false,
    users: [
      for (final u in j['users'] as List? ?? const [])
        UserSummary.fromJson(u as Map<String, dynamic>),
    ],
  );

  final String name;
  final bool initialized;
  final List<UserSummary> users;
}
