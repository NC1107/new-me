import '../api/api_client.dart';

/// What a person sees for a failed request; the server's own message is kept when it has one.
String errorCopy(Object error) {
  if (error is! ApiException) return 'Something went wrong.';
  return switch (error.kind) {
    ApiErrorKind.offline => 'You are offline. Check your connection and try again.',
    ApiErrorKind.badAppKey =>
      'This build is not accepted by the server. Update it from TestFlight.',
    ApiErrorKind.dateClosed => 'That day is closed for new entries.',
    _ => error.message,
  };
}
