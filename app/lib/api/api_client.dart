import 'package:dio/dio.dart';

import 'models.dart';

/// Sent on every request as X-Client-Version. Hardcoded because the app has no
/// package_info_plus; api_client_test.dart fails the build when it drifts from pubspec.
const kClientVersion = '0.1.0';

/// Shared secret baked in at build time with --dart-define=NEWME_APP_KEY=...
const String kAppKey = String.fromEnvironment('NEWME_APP_KEY');

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    final serverMessage = data is Map<String, dynamic> ? data['error'] as String? : null;
    return ApiException(
      serverMessage ?? e.message ?? 'Request failed',
      statusCode: e.response?.statusCode,
    );
  }

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    String? token,
    void Function()? onUnauthorized,
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
    if (onUnauthorized != null) {
      _dio.interceptors.add(
        InterceptorsWrapper(
          onError: (e, handler) {
            // Only a rejected token means the session is dead; a 401 without one is a login error.
            if (e.response?.statusCode == 401 && token != null) onUnauthorized();
            handler.next(e);
          },
        ),
      );
    }
  }

  final Dio _dio;

  Future<ServerInfo> serverInfo() async {
    try {
      final r = await _dio.get<Map<String, dynamic>>('/api/server-info');
      return ServerInfo.fromJson(r.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
