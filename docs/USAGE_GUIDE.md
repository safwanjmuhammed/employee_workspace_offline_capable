# Usage & Testing Guide — Offline-Capable Employee Workspace

This guide explains how to install and test the provided debug APK against the hosted mock API, as well as how to run the project and tests from source.

---

## 1. Installing & Opening the Provided Debug APK

1. Install the provided debug APK on an Android device (the mock API URL is preconfigured and hosted via `ngrok`).
2. Open **Employee Workspace** on the device.
3. If you ever need to point the app to a different mock URL, tap the **tune icon** (top-right of the AppBar) to open **Simulation & Testing Controls** and update **Mock API Base URL**.

---

## 2. Using Simulation & Testing Controls (In-App)

Tap the **tune icon** in the top-right AppBar at any time to control:

| Control | Options | Purpose |
|---|---|---|
| **Simulate Offline** | On / Off | Short-circuits network calls and triggers connectivity change events so offline mode can be tested reliably on any network. |
| **Location Simulation** | `Real GPS`, `Inside Office (25 m)`, `Outside Office (~1.4 km)`, `Permission Denied`, `Permanently Denied`, `Location Service Off`, `GPS Unavailable` | Test the 200 m geofence and all location permission / GPS error states without spoofing OS GPS. |
| **Mock API Scenario** | `normal`, `slow`, `timeout`, `server_error`, `duplicate_attendance`, `attendance_rejected`, `replay` | Sends the `X-Mock-Scenario` header to `nginx` to test 3s latency, timeouts, 500s, 409 conflicts, 422 rejections, and 200 idempotent replays. |
| **Mock API Base URL** | Any HTTP/HTTPS URL | Override the API endpoint at runtime without rebuilding. |
| **Clear Local Cache & Outbox** | Button | Resets SQLite (`cache_kv` + `attendance_outbox`) to test cold-start loading/error states. |

---

## 3. Step-by-Step Verification Walkthrough

1. **Dashboard Loading & Caching:**
   - Launch the app -> verify the loading indicator, followed by the employee header (`EMP-1024`), today's status (`Not Checked In`), and the latest 5 attendance records.
2. **Geofence & Permission Handling:**
   - Open **Simulation & Testing Controls** -> set Location to **Outside Office (~1.4 km)** -> tap **Check In** -> verify the distance error message.
   - Test **Permission Denied**, **Permanently Denied** (shows *Settings* action), and **Location Service Off** (shows *Enable GPS* action).
3. **Online Check-In:**
   - Set Location to **Inside Office (25 m)** -> tap **Check In** -> verify status becomes **Checked In**, the **Synced** chip appears, and the elapsed timer starts ticking.
4. **Offline Check-Out & App Restart Persistence:**
   - Enable **Simulate Offline** -> tap **Check Out** -> verify status becomes **Checked Out** with a **Pending Sync** chip and top banner (`1 pending sync`).
   - Force-close and reopen the app -> verify the **Pending Sync** check-out is preserved from SQLite.
5. **Reconnection & Sync:**
   - Disable **Simulate Offline** -> verify automatic sync (or tap **Sync Now**), transitioning the event to **Synced**.
   - Open the **Attendance** tab -> **Sync Outbox** sub-tab to inspect event IDs, timestamps, and sync states (`Pending Sync`, `Synced`, `Rejected`).
6. **Conflict (409) Handling:**
   - Clear local data, set Mock Scenario to **Duplicate Attendance (409)**, and tap **Check In** -> verify the outbox event is marked **Rejected** with the server reason.

---

## 4. Running From Source & Automated Tests (Optional)

1. Copy `.env.example.json` to `.env.json` and set `API_BASE_URL`:
   ```powershell
   Copy-Item .env.example.json .env.json
   ```
2. Run the app or tests:
   ```powershell
   flutter pub get
   flutter run --dart-define-from-file=.env.json
   flutter test
   ```
   - `test/attendance_rules_test.dart`: Check-out without check-in rejected; duplicate same-day check-in rejected; 200 m geofence check.
   - `test/attendance_idempotency_test.dart`: Repeated taps & `accept_then_timeout` + retry with same `Idempotency-Key` produce a single server record.
   - `test/outbox_persistence_test.dart`: Pending check-in & check-out survive SQLite close/reopen and sync in strict `seq` order; 409 marks event `Rejected`.
   - `test/dashboard_widget_test.dart`: Loading state and `Pending Sync` / offline UI indicators.

To test the mock API directly in Postman, import `mock_api/employee_workspace_postman_collection.json` and set `baseUrl` to the hosted `ngrok` URL.
