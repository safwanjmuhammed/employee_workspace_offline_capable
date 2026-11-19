import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_exception.dart';

/// Attaches mock scenario headers (for the nginx mock server) and enforces
/// the developer "Simulate Offline" switch before any network call is made.
class DioServiceInterceptor extends Interceptor {
  DioServiceInterceptor({
    bool Function()? isSimulatedOffline,
    String Function()? mockScenario,
  })  : _isSimulatedOffline = isSimulatedOffline ?? (() => false),
        _mockScenario = mockScenario ?? (() => 'normal');

  final bool Function() _isSimulatedOffline;
  final String Function() _mockScenario;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_isSimulatedOffline()) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const ApiException(
            kind: ApiErrorKind.offline,
            message: 'Simulated offline mode is enabled.',
          ),
        ),
      );
      return;
    }

    final scenario = _mockScenario();
    if (scenario.isNotEmpty && scenario != 'normal') {
      options.headers['X-Mock-Scenario'] = scenario;
    }

    if (kDebugMode) {
      debugPrint(
        '[API] ${options.method} ${options.baseUrl}${options.path} '
        '(scenario=$scenario)',
      );
    }
    super.onRequest(options, handler);
  }
}
