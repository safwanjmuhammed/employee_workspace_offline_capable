# Offline-Capable Employee Workspace

An offline-first Flutter application showcasing reliable local persistence, ordered outbox synchronization, and idempotent retries—allowing employees to view their workspace dashboard, perform geofenced attendance check-in/check-out (online or offline), and synchronize queued events reliably. *(Leave application is deferred from the current phase.)*

---

## 1. Architecture & State Management

The codebase follows a clean 4-layer separation inside `lib/src/`:

```
lib/
  main.dart                          # Opens SQLite, initializes timezone DB, launches ProviderScope
  src/
    app.dart                         # MaterialApp & Material 3 theme
    config/app_config.dart           # Compile-time defaults & --dart-define overrides
    core/
      clock/company_clock.dart       # Company-timezone clock (Asia/Kolkata by default)
      db/app_database.dart           # SQLite schema: cache_kv + attendance_outbox
      dio_api_service/               # Dio client, IApiService, interceptor, ApiException
      location/                      # Haversine distance + real/simulated LocationService
      network/                       # connectivity_plus + simulated offline toggle
      sync/                          # SyncEngine (pure core abstractions, zero feature imports)
    common/
      atom/                          # StatusChip
      molecule/                      # SyncStatusBar
      organism/                      # Reserved for shared organisms
    feature/
      attendance/
        domain/                      # AttendanceEvent/Record, AttendanceRepository, AttendanceRules, AttendanceService (use case)
        data/                        # OutboxStore, AttendanceRemoteDataSource, AttendanceRepositoryImpl
        presentation/                # AttendanceHistoryScreen + Sync Outbox tab
      dashboard/
        domain/                      # Employee, OfficeConfig, WorkspaceSnapshot, DashboardRepository
        data/                        # CacheStore, DashboardRemoteDataSource, DashboardRepositoryImpl
        presentation/                # WorkspaceProviders, DashboardScreen, HomeShell
      simulation/
        presentation/                # DevPanelSheet (location, offline, scenario, URL)
```

### State Management Justification
- **Riverpod (`flutter_riverpod` without codegen):** Provides both dependency injection and reactive state (`AsyncNotifier` / `Notifier`). Every external dependency (`AppDatabase`, `CompanyClock`, `DioApiService`, `LocationService`, `ConnectivityService`) is exposed as a provider and easily overridden in unit and widget tests without reflection or build-runner overhead.
- **No business logic in widgets:** Widgets only render `WorkspaceSnapshot` / `DevSettings` and invoke methods on `WorkspaceController`.

---

## 2. Offline Storage, Sync Ordering & Idempotency

### Local Persistence (`sqflite`)
- `cache_kv`: Stores the latest JSON responses for `/employee/me`, `/attendance`, `/leave/balance`, and `/leave/requests` along with `updated_at_utc` for the offline banner.
- `attendance_outbox`: Ordered queue with `seq INTEGER PRIMARY KEY AUTOINCREMENT`, `event_id TEXT UNIQUE`, `type` (`check_in` / `check_out`), `work_date`, `occurred_at_utc`, GPS coordinates, `sync_status` (`pending` | `synced` | `rejected`), `reject_reason`, `attempts`, and `last_error`.
- A partial unique index `idx_outbox_active_day_type ON attendance_outbox(work_date, type) WHERE sync_status != 'rejected'` provides a database-level guard against duplicate same-day check-in or check-out events.

### Single Write Path & Strict Ordering
1. Every valid check-in or check-out (online or offline) is written to `attendance_outbox` **first** with status `Pending Sync`.
2. `SyncEngine.syncPending()` uses an in-memory mutex so concurrent triggers (app startup, new event, manual **Sync Now**, or connectivity restoration) cannot run simultaneously.
3. Pending events are sent **strictly in `seq ASC` order**, one at a time:
   - `200` / `201`: Marked `Synced`.
   - `409 ATTENDANCE_EXISTS` or `422`: Marked `Rejected` with the server's reason so the user can see it clearly in the Sync Outbox.
   - Transient failure (offline, timeout, 5xx, network error): Increments `attempts`, records `last_error`, and **stops the loop immediately** so a `check_out` can never overtake a `check_in`.

### Event Identity, Idempotency & Timeout Recovery
- A UUID v4 `eventId` is generated **once at tap time** and persisted in `attendance_outbox`.
- Every sync attempt sends `eventId` in both the JSON payload and the `Idempotency-Key` HTTP header.
- If the server commits an event and the response is lost to a timeout, the event stays `Pending Sync`. On retry, the client sends the exact same `eventId` / `Idempotency-Key`. A production server stores `eventId` as a unique key and returns `200 { "replayed": true }` without inserting a duplicate record; a *different* `eventId` for an already-recorded `(employeeId, workDate, type)` returns `409 ATTENDANCE_EXISTS`.

---

## 3. Device-Side vs Production Server Validation

Device-side checks (geofence, once-per-day check-in, check-out after check-in, leave form rules) give instant feedback and work offline, **but can be bypassed on a rooted/modified client**. A production backend must re-verify:
1. **Authenticated employee identity** from the auth token/session (never trust client-supplied employee IDs).
2. **Authoritative server time & company timezone** (record `occurredAt` for audit, validate against server clock with an allowed skew window).
3. **Geofence & location integrity** (distance `<= 200 m`, accuracy threshold, mock-location flags).
4. **Attendance state machine** (one check-in per `(employee, workDate)`, check-out only after check-in, strict ordering) inside a DB transaction.
5. **Idempotency key uniqueness** on `(employeeId, eventId)`.
6. **All leave rules** (date bounds, min reason length, balance sufficiency, and overlap against `Pending`/`Approved` requests using row-level locking).

---

## 4. Setup & Mock API Instructions (nginx without Docker)

### Prerequisites
- Flutter SDK (tested on Dart `^3.13.7`)
- `nginx` (native binary on Windows/macOS/Linux; no Docker required)

### 1. Start the Mock API
From the repository root:
```powershell
cd mock_api\nginx
nginx.exe -p . -c nginx.conf
```
*(On macOS/Linux: `nginx -p mock_api/nginx -c nginx.conf -g "daemon off;"`)*

Verify it is running:
```powershell
curl http://localhost:8080/health
# {"status":"ok"}
```

### 2. Connecting the App / Remote Access
- **Android Emulator:** Uses `http://10.0.2.2:8080` by default (already configured).
- **Physical Android Device over USB:** Run `adb reverse tcp:8080 tcp:8080` and set Base URL to `http://127.0.0.1:8080` in the in-app **Simulation & Testing Controls** (tune icon in AppBar) or via `--dart-define=API_BASE_URL=http://127.0.0.1:8080`.
- **Remote Access (ngrok):** Expose port `8080` with `ngrok http 8080` and paste the HTTPS ngrok URL into **Mock API Base URL** in **Simulation & Testing Controls** (or pass `--dart-define=API_BASE_URL=https://<your-id>.ngrok-free.app`).

### 3. Configure `API_BASE_URL` (Without Committing Secrets)
Copy `.env.example.json` to `.env.json` (which is git-ignored) and set your `API_BASE_URL`:
```powershell
Copy-Item .env.example.json .env.json
```
Edit `.env.json` with your ngrok/LAN URL, then run or build:
```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --dart-define-from-file=.env.json
```

---

## 5. Simulation & Testing Guide

Tap the **tune icon** (top-right of the AppBar) to open **Simulation & Testing Controls**:
- **Simulate Offline:** Short-circuits Dio requests and emits offline connectivity events (useful even against localhost/USB).
- **Location Simulation:** Switch between `Real GPS`, `Inside Office (25 m)`, `Outside Office (~1.4 km)`, `Permission Denied`, `Permanently Denied`, `Location Service Off`, and `GPS Unavailable`.
- **Mock API Scenario (`X-Mock-Scenario` header):**
  - `normal`: Standard 200/201 responses.
  - `slow`: ~3 s delay before responding.
  - `timeout`: Hangs >10 s so Dio times out.
  - `server_error`: Returns HTTP 500.
  - `duplicate_attendance`: `POST /attendance/events` returns `409 ATTENDANCE_EXISTS` -> event is marked `Rejected`.
  - `attendance_rejected`: `POST /attendance/events` returns `422`.
  - `replay`: `POST /attendance/events` returns `200 { "replayed": true }`.
  - `leave_reject`: `POST /leave/requests` returns `422` with inline field errors even when local validation passes.

---

## 6. Completed Features

- **Employee Dashboard:** Displays employee name, ID, department, company timezone, today's attendance status (`Not Checked In`, `Checked In`, `Checked Out`), check-in/check-out times, live elapsed working duration, latest 5 attendance records, and distinct loading, error (with retry), empty, and offline states.
- **Geofenced Attendance Check-In & Check-Out:** Enforces once-per-day check-in, check-out only after check-in, re-entry + DB unique-index duplicate guards, 200 m Haversine geofence check, configurable company timezone (`COMPANY_TZ`), and handling for denied, permanently denied, disabled, and unavailable GPS states.
- **Offline Storage & Ordered Synchronization:** Persists cached API data (`cache_kv`) and queued events (`attendance_outbox`) in SQLite (`sqflite`); preserves pending events across app restarts; distinguishes `Pending Sync`, `Synced`, and `Rejected` states; supports manual **Sync Now** and automatic sync on reconnect; processes events strictly in `seq ASC` order; halts on transient errors; and sends a persistent UUID v4 `Idempotency-Key` on every retry.
- **Simulation & Testing Controls:** In-app panel for simulating offline mode, GPS/permission states, `X-Mock-Scenario` fault injection (`slow`, `timeout`, `server_error`, `duplicate_attendance`, `attendance_rejected`, `replay`), runtime base URL override, and local data reset.
- **Mock API & Postman Collection:** Stateless `nginx` mock server (`mock_api/nginx/`) with scenario-based fault injection and a ready-to-import Postman collection (`mock_api/employee_workspace_postman_collection.json`).
- **Automated Tests:** Unit, persistence, idempotency, and widget tests covering attendance rules, timeout + idempotent retry, SQLite restart persistence & ordering, `409` conflict rejection, and dashboard loading/pending-sync UI states.

---

## 7. Assumptions, Limitations & Trade-offs

- **Minimal UI / Future Design System Extraction:** This phase intentionally prioritizes offline-first architecture, ordered synchronization, and idempotency over visual polish. The presentation layer uses standard Material 3 widgets directly and will be extracted into a dedicated design system (tokens, typography, and reusable components) in a later phase.
- **Stateless nginx mock (Option A):** `mock_api/nginx` serves static JSON fixtures and uses `X-Mock-Scenario` for fault injection. Because plain nginx is stateless, `POST`ed check-ins/check-outs are not persisted on the server across `GET` refreshes; instead, the Flutter app merges cached server history with the local SQLite outbox (`AttendanceRules.mergeHistoryWithOutbox`). Idempotency replay (`accept_then_timeout` -> `200 replayed: true`) is thoroughly verified in `test/attendance_idempotency_test.dart` using a stateful Dio `HttpClientAdapter`.
- **Single employee & no login:** Per scope.
- **No background sync when app is terminated:** Per scope.

---

## 8. AI Tools Disclosure
AI coding assistance was used to scaffold boilerplate, structure tests, and draft documentation. All architecture decisions, state/sync logic, and tests were reviewed and verified.
