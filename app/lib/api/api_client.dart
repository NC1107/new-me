import 'package:dio/dio.dart';

import 'models.dart';

/// Sent on every request as X-Client-Version. Hardcoded because the app has no
/// package_info_plus; api_client_test.dart fails the build when it drifts from pubspec.
const kClientVersion = '0.1.0';

/// Shared secret baked in at build time with --dart-define=NEWME_APP_KEY=...
const String kAppKey = String.fromEnvironment('NEWME_APP_KEY');

enum ApiErrorKind {
  /// 403 bad_app_key: this build is not accepted. Never a sign-out.
  badAppKey,

  /// 426: the server requires a newer client.
  updateRequired,

  /// 422 date_closed: the entry's day is no longer open.
  dateClosed,

  /// No response at all, or a 5xx. Never a sign-out.
  offline,

  /// A reachable host that does not speak the New Me API.
  wrongServer,

  /// Any other rejection, carrying the server's own message.
  other,
}

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.kind = ApiErrorKind.other,
    this.statusCode,
    this.code,
    this.minClientVersion,
  });

  const ApiException.badAppKey({int? statusCode})
    : this(
        'This build is not accepted by the server',
        kind: ApiErrorKind.badAppKey,
        statusCode: statusCode,
        code: 'bad_app_key',
      );

  const ApiException.updateRequired({String? minClientVersion})
    : this(
        'Update required',
        kind: ApiErrorKind.updateRequired,
        statusCode: 426,
        code: 'update_required',
        minClientVersion: minClientVersion,
      );

  const ApiException.dateClosed({String message = 'That day is closed'})
    : this(message, kind: ApiErrorKind.dateClosed, statusCode: 422, code: 'date_closed');

  const ApiException.offline({int? statusCode, String message = 'Offline'})
    : this(message, kind: ApiErrorKind.offline, statusCode: statusCode);

  const ApiException.wrongServer() : this('Not a New Me server', kind: ApiErrorKind.wrongServer);

  factory ApiException.fromDio(DioException e) {
    final response = e.response;
    if (e.error is FormatException) {
      return const ApiException('Unexpected response from the server');
    }
    if (response == null) return const ApiException.offline();

    final status = response.statusCode;
    final data = response.data;
    final body = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    final code = body['code'] as String?;
    final serverMessage = body['error'] as String?;

    if (status == 403 && code == 'bad_app_key') return ApiException.badAppKey(statusCode: status);
    if (status == 426) {
      return ApiException.updateRequired(minClientVersion: body['minClientVersion'] as String?);
    }
    if (status == 422 && code == 'date_closed') {
      return ApiException.dateClosed(message: serverMessage ?? 'That day is closed');
    }
    if (status != null && status >= 500) {
      return ApiException.offline(statusCode: status, message: serverMessage ?? 'Server error');
    }
    return ApiException(
      serverMessage ?? e.message ?? 'Request failed',
      statusCode: status,
      code: code,
    );
  }

  final String message;
  final ApiErrorKind kind;
  final int? statusCode;

  /// The server's machine-readable error code, such as `date_closed`.
  final String? code;

  /// On a 426, the oldest client version the server still accepts.
  final String? minClientVersion;

  @override
  String toString() => 'ApiException($kind, $statusCode): $message';
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    String? token,
    void Function()? onUnauthorized,
    void Function()? onUpdateRequired,
    HttpClientAdapter? adapter,
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           connectTimeout: const Duration(seconds: 15),
           sendTimeout: const Duration(seconds: 15),
           receiveTimeout: const Duration(seconds: 15),
           headers: {
             'X-App-Key': kAppKey,
             'X-Client-Version': kClientVersion,
             if (token != null) 'Authorization': 'Bearer $token',
           },
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) {
          final status = e.response?.statusCode;
          // Only a rejected token means the session is dead; a 401 without one is a login error.
          if (status == 401 && token != null) onUnauthorized?.call();
          if (status == 426) onUpdateRequired?.call();
          handler.next(e);
        },
      ),
    );
  }

  final Dio _dio;

  Future<T> _send<T>(
    Future<Response<dynamic>> Function() request,
    T Function(dynamic) parse,
  ) async {
    try {
      final response = await request();
      return parse(response.data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    } on TypeError {
      throw const ApiException('Unexpected response from the server');
    } on FormatException {
      throw const ApiException('Unexpected response from the server');
    }
  }

  Future<ServerInfo> serverInfo() async {
    try {
      return await _send(() => _dio.get<dynamic>('/api/server-info'), (data) {
        if (data is! Map<String, dynamic> || data['initialized'] is! bool) {
          throw const ApiException.wrongServer();
        }
        return ServerInfo.fromJson(data);
      });
    } on ApiException catch (e) {
      if (e.kind == ApiErrorKind.other) throw const ApiException.wrongServer();
      rethrow;
    }
  }

  Future<InviteCheck> checkInvite(String code) => _send(
    () => _dio.post<dynamic>('/api/invites/check', data: {'code': code}),
    (data) => InviteCheck.fromJson(data as Json),
  );

  Future<JoinResult> join(JoinRequest request) => _send(
    () => _dio.post<dynamic>('/api/join', data: request.toJson()),
    (data) => JoinResult.fromJson(data as Json),
  );

  Future<void> deleteDevice() => _send(() => _dio.delete<dynamic>('/api/devices/me'), (_) {});

  Future<Me> me() => _send(() => _dio.get<dynamic>('/api/me'), (data) => Me.fromJson(data as Json));

  Future<Me> patchMe(MePatch patch) => _send(
    () => _dio.patch<dynamic>('/api/me', data: patch.toJson()),
    (data) => Me.fromJson(data as Json),
  );

  Future<Today> today({String? date}) => _send(
    () => _dio.get<dynamic>('/api/today', queryParameters: {'date': ?date}),
    (data) => Today.fromJson(data as Json),
  );

  Future<Board> board() =>
      _send(() => _dio.get<dynamic>('/api/board'), (data) => Board.fromJson(data as Json));

  Future<List<LogEntry>> logs({required String date}) => _send(
    () => _dio.get<dynamic>('/api/logs', queryParameters: {'date': date}),
    (data) => [for (final j in (data as Json)['logs'] as List) LogEntry.fromJson(j as Json)],
  );

  Future<LogResult> createLog(LogDraft draft) => _send(
    () => _dio.post<dynamic>('/api/logs', data: draft.toJson()),
    (data) => LogResult.fromJson(data as Json),
  );

  Future<LogDeleteResult> deleteLog(LogEntry entry) => _send(
    () => _dio.delete<dynamic>('/api/logs/${entry.id}'),
    (data) => LogDeleteResult.fromJson(data as Json),
  );

  Future<List<RecentMeal>> recentMeals({int limit = 20}) => _send(
    () => _dio.get<dynamic>('/api/meals/recent', queryParameters: {'limit': limit}),
    (data) => [for (final j in (data as Json)['meals'] as List) RecentMeal.fromJson(j as Json)],
  );

  Future<HealthDailyResult> putHealthDaily(List<HealthItem> items) => _send(
    () => _dio.put<dynamic>(
      '/api/health/daily',
      data: {
        'items': [for (final i in items) i.toJson()],
      },
    ),
    (data) => HealthDailyResult.fromJson(data as Json),
  );

  Future<HealthTrend> healthTrends(String metric, int days) => _send(
    () =>
        _dio.get<dynamic>('/api/health/trends', queryParameters: {'metric': metric, 'days': days}),
    (data) => HealthTrend.fromJson(data as Json),
  );

  Future<Invite> createInvite() =>
      _send(() => _dio.post<dynamic>('/api/invites'), (data) => Invite.fromJson(data as Json));
}
