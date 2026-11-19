import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Manages the local SQLite database for cached API data and the ordered
/// attendance sync outbox.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const int _version = 1;
  static const String defaultFileName = 'employee_workspace.db';

  static Future<AppDatabase> open({
    String? customPath,
    DatabaseFactory? factory,
  }) async {
    final dbFactory = factory ?? databaseFactory;
    final path = customPath ??
        p.join(await dbFactory.getDatabasesPath(), defaultFileName);

    final database = await dbFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _version,
        onCreate: _onCreate,
      ),
    );
    return AppDatabase._(database);
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Key-value JSON cache for employee profile and attendance history.
    await db.execute('''
      CREATE TABLE cache_kv (
        key TEXT PRIMARY KEY,
        json_value TEXT NOT NULL,
        updated_at_utc TEXT NOT NULL
      )
    ''');

    // Ordered outbox for offline-first check-in / check-out events.
    await db.execute('''
      CREATE TABLE attendance_outbox (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        work_date TEXT NOT NULL,
        occurred_at_utc TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy_meters REAL NOT NULL,
        sync_status TEXT NOT NULL,
        reject_reason TEXT,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at_utc TEXT NOT NULL
      )
    ''');

    // Prevents duplicate non-rejected events for the same (work_date, type).
    await db.execute('''
      CREATE UNIQUE INDEX idx_outbox_active_day_type
      ON attendance_outbox(work_date, type)
      WHERE sync_status != 'rejected'
    ''');
  }

  Future<void> clearAll() async {
    await db.transaction((txn) async {
      await txn.delete('attendance_outbox');
      await txn.delete('cache_kv');
    });
  }

  Future<void> close() => db.close();
}
