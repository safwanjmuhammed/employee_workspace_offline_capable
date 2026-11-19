import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../config/app_config.dart';
import 'api_exception.dart';
import 'api_service_interceptor.dart';
import 'interface/api_service_interface.dart';

class DioApiService implements IApiService {
  DioApiService({
    String? baseUrl,
    Dio? dio,
    bool Function()? isSimulatedOffline,
    String Function()? mockScenario,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl ?? AppConfig.baseUrl,
               connectTimeout: AppConfig.connectTimeout,
               receiveTimeout: AppConfig.receiveTimeout,
               headers: const {
                 'Accept': 'application/json',
                 'Content-Type': 'application/json',
                 'ngrok-skip-browser-warning': 'true',
               },
             ),
           ) {
    if (dio == null) {
      _dio.interceptors.add(
        DioServiceInterceptor(
          isSimulatedOffline: isSimulatedOffline,
          mockScenario: mockScenario,
        ),
      );
    }
  }

  final Dio _dio;

  Dio get dio => _dio;

  void updateBaseUrl(String newBaseUrl) {
    _dio.options.baseUrl = newBaseUrl.trim();
  }

  /// The [get], [post], [put], [patch] and [delete] methods redirect here.
  Future<Response> _request(
    String path, {
    required String method,
    Object? data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool loader = true,
    Options? options,
  }) async {
    try {
      final mergedOptions = (options ?? Options()).copyWith(method: method);

      final response = await _dio.request(
        path,
        data: data,
        options: mergedOptions,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      );

      return response;
    } on DioException catch (err) {
      if (kDebugMode) {
        debugPrint(
          '[API ERROR] ${err.type} ${err.response?.statusCode}: ${err.message}',
        );
      }
      throw ApiException.fromDioException(err);
    } on ApiException {
      rethrow;
    } catch (err) {
      throw ApiException(kind: ApiErrorKind.unknown, message: err.toString());
    }
  }

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool loader = true,
    CancelToken? cancelToken,
    Options? options,
  }) => _request(
    path,
    method: IApiService.GET,
    queryParameters: queryParameters,
    loader: loader,
    cancelToken: cancelToken,
    options: options,
  );

  @override
  Future<Response> post(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool loader = true,
    CancelToken? cancelToken,
    Options? options,
  }) => _request(
    path,
    method: IApiService.POST,
    data: data,
    queryParameters: queryParameters,
    loader: loader,
    cancelToken: cancelToken,
    options: options,
  );

  @override
  Future<Response> put(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool loader = true,
    CancelToken? cancelToken,
    Options? options,
  }) => _request(
    path,
    method: IApiService.PUT,
    data: data,
    queryParameters: queryParameters,
    loader: loader,
    cancelToken: cancelToken,
    options: options,
  );

  @override
  Future<Response> patch(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool loader = true,
    CancelToken? cancelToken,
    Options? options,
  }) => _request(
    path,
    method: IApiService.PATCH,
    data: data,
    queryParameters: queryParameters,
    loader: loader,
    cancelToken: cancelToken,
    options: options,
  );

  @override
  Future<Response> fileUpload(
    String path, {
    required FormData data,
    String method = IApiService.PUT,
    Map<String, dynamic>? queryParameters,
    bool loader = true,
    CancelToken? cancelToken,
    Options? options,
  }) => _request(
    path,
    method: method,
    data: data,
    queryParameters: queryParameters,
    loader: loader,
    cancelToken: cancelToken,
    options: options,
  );

  @override
  Future<Response> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
    Object? data,
    bool loader = true,
    CancelToken? cancelToken,
    Options? options,
  }) => _request(
    path,
    data: data,
    method: IApiService.DELETE,
    queryParameters: queryParameters,
    loader: loader,
    cancelToken: cancelToken,
    options: options,
  );
}
