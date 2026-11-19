import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_database.dart';
import '../../domain/models/attendance.dart';
import '../../domain/models/employee.dart';

class CachedValue<T> {
  const CachedValue({required this.value, required this.updatedAtUtc});
  final T value;
  final DateTime updatedAtUtc;
}

class CacheStore {
  CacheStore(this._db);

  final AppDatabase _db;

  static const _kEmployee = 'employee_me';
  static const _kAttendance = 'attendance_history';

  Future<void> _putJson(String key, Object value, DateTime nowUtc) async {
    await _db.db.insert(
      'cache_kv',
      {
        'key': key,
        'json_value': jsonEncode(value),
        'updated_at_utc': nowUtc.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<CachedValue<dynamic>?> _getJson(String key) async {
    final rows = await _db.db.query(
      'cache_kv',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return CachedValue(
      value: jsonDecode(row['json_value'] as String),
      updatedAtUtc: DateTime.parse(row['updated_at_utc'] as String).toUtc(),
    );
  }

  Future<void> saveEmployee(Employee employee, DateTime nowUtc) =>
      _putJson(_kEmployee, employee.toJson(), nowUtc);

  Future<CachedValue<Employee>?> readEmployee() async {
    final cached = await _getJson(_kEmployee);
    if (cached == null) return null;
    return CachedValue(
      value: Employee.fromJson(cached.value as Map<String, dynamic>),
      updatedAtUtc: cached.updatedAtUtc,
    );
  }

  Future<void> saveAttendanceHistory(
    List<AttendanceRecord> records,
    DateTime nowUtc,
  ) =>
      _putJson(
        _kAttendance,
        {'records': records.map((r) => r.toJson()).toList()},
        nowUtc,
      );

  Future<CachedValue<List<AttendanceRecord>>?> readAttendanceHistory() async {
    final cached = await _getJson(_kAttendance);
    if (cached == null) return null;
    final map = cached.value as Map<String, dynamic>;
    final list = (map['records'] as List<dynamic>? ?? const [])
        .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    return CachedValue(value: list, updatedAtUtc: cached.updatedAtUtc);
  }
}
