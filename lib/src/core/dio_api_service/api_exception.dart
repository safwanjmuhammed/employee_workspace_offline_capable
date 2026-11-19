import 'package:dio/dio.dart';

enum ApiErrorKind {
  offline,
  timeout,
  conflict,
  validation,
  server,
  network,
  unknown,
}

/// Normalized API error thrown by [DioApiService] so domain/sync layers
/// never depend on raw [DioException] internals.
class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
    this.fieldErrors = const {},
  });

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final String? code;
  final Map<String, String> fieldErrors;

  bool get isTransient =>
      kind == ApiErrorKind.offline ||
      kind == ApiErrorKind.timeout ||
      kind == ApiErrorKind.server ||
      kind == ApiErrorKind.network;

  factory ApiException.fromDioException(DioException err) {
    if (err.error is ApiException) {
      return err.error! as ApiException;
    }

    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          kind: ApiErrorKind.timeout,
          message: 'Request timed out. Please try again.',
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          kind: ApiErrorKind.network,
          message: 'Unable to reach the server.',
        );
      case DioExceptionType.badResponse:
        final status = err.response?.statusCode;
        final body = err.response?.data;
        String? code;
        String message = 'Server returned status $status.';
        final fieldErrors = <String, String>{};

        if (body is Map<String, dynamic>) {
          code = body['code']?.toString();
          if (body['message'] != null) {
            message = body['message'].toString();
          }
          final rawErrors = body['errors'];
          if (rawErrors is Map) {
            for (final entry in rawErrors.entries) {
              fieldErrors[entry.key.toString()] = entry.value.toString();
            }
          }
        }

        if (status == 409) {
          return ApiException(
            kind: ApiErrorKind.conflict,
            statusCode: status,
            code: code ?? 'CONFLICT',
            message: message,
            fieldErrors: fieldErrors,
          );
        }
        if (status == 422 || status == 400) {
          return ApiException(
            kind: ApiErrorKind.validation,
            statusCode: status,
            code: code ?? 'VALIDATION_FAILED',
            message: message,
            fieldErrors: fieldErrors,
          );
        }
        if (status != null && status >= 500) {
          return ApiException(
            kind: ApiErrorKind.server,
            statusCode: status,
            code: code ?? 'SERVER_ERROR',
            message: message,
          );
        }
        return ApiException(
          kind: ApiErrorKind.unknown,
          statusCode: status,
          code: code,
          message: message,
          fieldErrors: fieldErrors,
        );
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.unknown:
        return ApiException(
          kind: ApiErrorKind.network,
          message: err.message ?? 'Network error occurred.',
        );
    }
  }

  @override
  String toString() => 'ApiException($kind, status=$statusCode, code=$code, $message)';
}
