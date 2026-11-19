/// Compile-time configuration with `--dart-define` / `--dart-define-from-file` overrides.
abstract final class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  static const String companyTimezone = String.fromEnvironment(
    'COMPANY_TZ',
    defaultValue: 'Asia/Kolkata',
  );

  static const double defaultOfficeLat = 10.0101;
  static const double defaultOfficeLng = 76.3637;
  static const double defaultOfficeRadiusMeters = 200.0;

  static const Duration connectTimeout = Duration(seconds: 8);
  static const Duration receiveTimeout = Duration(seconds: 10);
}
