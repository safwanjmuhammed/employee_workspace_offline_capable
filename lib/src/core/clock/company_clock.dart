import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Provides "now" and "today" in the configured company timezone.
///
/// Injected via Riverpod so tests can freeze or shift time deterministically.
abstract interface class CompanyClock {
  DateTime nowUtc();
  DateTime nowInCompanyTz();
  String todayWorkDate();
  String toWorkDate(DateTime utcInstant);
  DateTime toCompanyTz(DateTime utcInstant);
  String get timezoneName;
}

class SystemCompanyClock implements CompanyClock {
  SystemCompanyClock({
    required this.timezoneName,
    DateTime Function()? nowProvider,
  }) : _nowProvider = nowProvider ?? (() => DateTime.now().toUtc()) {
    ensureTimezoneInitialized();
    _location = tz.getLocation(timezoneName);
  }

  static bool _initialized = false;

  static void ensureTimezoneInitialized() {
    if (!_initialized) {
      tz_data.initializeTimeZones();
      _initialized = true;
    }
  }

  @override
  final String timezoneName;
  final DateTime Function() _nowProvider;
  late final tz.Location _location;

  @override
  DateTime nowUtc() => _nowProvider().toUtc();

  @override
  DateTime nowInCompanyTz() => tz.TZDateTime.from(nowUtc(), _location);

  @override
  DateTime toCompanyTz(DateTime utcInstant) =>
      tz.TZDateTime.from(utcInstant.toUtc(), _location);

  @override
  String todayWorkDate() => DateFormat('yyyy-MM-dd').format(nowInCompanyTz());

  @override
  String toWorkDate(DateTime utcInstant) =>
      DateFormat('yyyy-MM-dd').format(toCompanyTz(utcInstant));
}
