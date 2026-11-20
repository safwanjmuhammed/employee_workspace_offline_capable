# Mock Server Setup Guide (From Scratch)

This guide walks through setting up, verifying, exposing via `ngrok`, and stopping the stateless `nginx` mock API server in sequential command order.

> **Reference files:**
> - Server config: `mock_api/nginx/nginx.conf`
> - Shared fault-injection rules: `mock_api/nginx/scenario.conf`
> - Static JSON fixtures: `mock_api/nginx/data/employee.json`, `mock_api/nginx/data/attendance.json`
> - App compile-time config: `lib/src/config/app_config.dart`

---

## Step 1: Install Prerequisites

### Windows (PowerShell)

1. Install `nginx` (or download and extract the Windows zip and add its folder to `PATH`):
   ```powershell
   winget install nginxinc.nginx
   ```
2. *(Optional, for physical devices over the internet)* Install `ngrok` and authenticate once:
   ```powershell
   winget install Ngrok.Ngrok
   ngrok config add-authtoken <YOUR_NGROK_AUTHTOKEN>
   ```
3. Verify both binaries are available:
   ```powershell
   nginx.exe -v
   ngrok version
   ```

### macOS / Linux *(Alternative)*

```bash
# macOS
brew install nginx ngrok

# Ubuntu / Debian
sudo apt update && sudo apt install -y nginx
```

---

## Step 2: Prepare `nginx` Working Directories

`mock_api/nginx/.gitignore` ignores `logs/*.log`, `logs/*.pid`, and `temp/*`, so on a fresh clone create `logs` and `temp` before starting `nginx`:

```powershell
cd mock_api\nginx
mkdir logs, temp -Force
```

*(macOS / Linux from repo root:)*

```bash
mkdir -p mock_api/nginx/logs mock_api/nginx/temp
```

---

## Step 3: Validate the `nginx` Configuration

Test `nginx.conf` and `scenario.conf` for syntax errors before starting:

```powershell
# From mock_api\nginx
nginx.exe -p . -c nginx.conf -t
```

Expected output ends with:
```text
nginx: the configuration file ...nginx.conf syntax is ok
nginx: configuration file ...nginx.conf test is successful
```

---

## Step 4: Start the Mock Server (Port `8080`)

### Windows

```powershell
# From mock_api\nginx
nginx.exe -p . -c nginx.conf
```

### macOS / Linux

```bash
# From repository root (runs in foreground)
nginx -p mock_api/nginx -c nginx.conf -g "daemon off;"
```

---

## Step 5: Verify Endpoints & Fault-Injection Scenarios

Run these commands sequentially in a new terminal (on Windows PowerShell use `curl.exe`, not `curl`, which aliases `Invoke-WebRequest`):

1. **Health check:**
   ```powershell
   curl.exe http://localhost:8080/health
   # Expected: {"status":"ok"}
   ```

2. **Employee profile & office geofence config:**
   ```powershell
   curl.exe http://localhost:8080/employee/me
   ```

3. **Attendance history:**
   ```powershell
   curl.exe "http://localhost:8080/attendance?month=2026-11"
   ```

4. **Check-in / Check-out (`POST`):**
   ```powershell
   curl.exe -i -X POST http://localhost:8080/attendance/events -H "Content-Type: application/json" -d "{\"eventId\":\"test-evt-1\",\"type\":\"check_in\"}"
   # Expected: HTTP/1.1 201 Created
   ```

5. **Test fault-injection scenarios (`X-Mock-Scenario` header or `?mock_scenario=`):**
   ```powershell
   # 500 server error
   curl.exe -i http://localhost:8080/employee/me -H "X-Mock-Scenario: server_error"

   # ~3s artificial delay then 200 OK
   curl.exe -i http://localhost:8080/employee/me -H "X-Mock-Scenario: slow"

   # 409 conflict on POST /attendance/events
   curl.exe -i -X POST http://localhost:8080/attendance/events -H "X-Mock-Scenario: duplicate_attendance"

   # 422 validation rejection on POST /attendance/events
   curl.exe -i -X POST http://localhost:8080/attendance/events -H "X-Mock-Scenario: attendance_rejected"

   # 200 idempotent replay on POST /attendance/events
   curl.exe -i -X POST http://localhost:8080/attendance/events -H "X-Mock-Scenario: replay"
   ```

---

## Step 6: Connect the Flutter App

Choose **one** of the three connection methods below depending on your target device.

### Option A: Android Emulator (Default)

No tunnel or extra flags needed (`AppConfig.baseUrl` defaults to `http://10.0.2.2:8080`, which maps to host `localhost:8080`):

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

Or use the **Employee Workspace (Debug - Local Emulator)** launch configuration in `.vscode/launch.json`.

---

### Option B: Physical Android Device over USB (`adb reverse`)

1. Forward device port `8080` to host port `8080`:
   ```powershell
   adb reverse tcp:8080 tcp:8080
   ```
2. Run the app pointing at `127.0.0.1:8080`:
   ```powershell
   flutter pub get
   flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080
   ```
   Or use **Employee Workspace (Debug - USB Device)** in `.vscode/launch.json`.

---

### Option C: Physical Device / Remote Testing via `ngrok`

1. **Start the `ngrok` tunnel** (in a separate terminal, keep it open):
   ```powershell
   ngrok http 8080
   ```
   Copy the `Forwarding` HTTPS URL from `ngrok` output (e.g. `https://<your-id>.ngrok-free.app`).

2. **Verify the tunnel reaches `nginx`:**
   ```powershell
   curl.exe -H "ngrok-skip-browser-warning: true" https://<your-id>.ngrok-free.app/health
   # Expected: {"status":"ok"}
   ```
   *(The Flutter app automatically sends `ngrok-skip-browser-warning: true` in `DioApiService`.)*

3. **Create `.env.json` from the template** (from repository root):
   ```powershell
   Copy-Item .env.example.json .env.json
   ```

4. **Edit `.env.json`** with your `ngrok` URL:
   ```json
   {
     "API_BASE_URL": "https://<your-id>.ngrok-free.app",
     "COMPANY_TZ": "Asia/Kolkata"
   }
   ```

5. **Run or build the Flutter app with `.env.json`:**
   ```powershell
   flutter pub get
   flutter run --dart-define-from-file=.env.json
   ```
   Or press `F5` in VS Code with **Employee Workspace (Debug - .env.json)** selected.

   To build a shareable debug APK with the `ngrok` URL baked in:
   ```powershell
   flutter build apk --debug --dart-define-from-file=.env.json
   ```

> **Tip:** You can also change `API_BASE_URL` at runtime without rebuilding by tapping the **tune icon** in the app's AppBar (**Simulation & Testing Controls** -> **Mock API Base URL**).

---

## Step 7: Inspect Logs, Reload, and Stop the Server

Run these from `mock_api\nginx`:

1. **View request and error logs:**
   ```powershell
   Get-Content logs\access.log -Tail 20
   Get-Content logs\error.log -Tail 20
   ```

2. **Reload after editing `nginx.conf`, `scenario.conf`, or `data/*.json`:**
   ```powershell
   nginx.exe -p . -c nginx.conf -t
   nginx.exe -p . -c nginx.conf -s reload
   ```

3. **Stop `nginx` cleanly:**
   ```powershell
   nginx.exe -p . -c nginx.conf -s stop
   ```

4. **Force-stop if `nginx.pid` is stale or unresponsive (Windows):**
   ```powershell
   Stop-Process -Name nginx -Force
   ```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `nginx: [emerg] open() ".../logs/error.log" failed` | `logs/` or `temp/` folder missing | Run `mkdir logs, temp -Force` inside `mock_api\nginx`. |
| `bind() to 0.0.0.0:8080 failed` | Port `8080` is already in use (or an older `nginx` instance is running) | Stop the existing process (`nginx.exe -p . -c nginx.conf -s stop` or `Get-NetTCPConnection -LocalPort 8080`). |
| `ngrok` returns an HTML warning page in browser/curl | Free `ngrok` interstitial page | Pass header `ngrok-skip-browser-warning: true` (already configured in `DioApiService`). |
| App receives `404` or `ERR_NGROK_3200` | `ngrok` restarted with a new URL or stopped | Update `.env.json` (or runtime **Mock API Base URL** in the app's tune panel) with the active `ngrok` URL. |
