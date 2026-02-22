# Laptop Dashboard Mobile

Flutter-based mobile app and Go daemon for monitoring laptop statistics and performing remote actions (like sleep).

## Project Structure

- `lib/`: Flutter mobile app source code.
  - `main.dart`: Core application logic, including UI, state management, and notification handling.
  - `widgets/`: Reusable UI components (`StatusCard`, `LogCard`).
- `daemon/go/`: Go daemon that runs on the laptop.
  - `main.go`: Entry point; starts the HTTP server and handles graceful shutdown.
  - `router.go`: Route registration.
  - `stats_handlers.go`: `/stats` endpoint — CPU, RAM, temperature, battery.
  - `sleep_handlers.go`: `/sleep` endpoint — suspends the laptop.
  - `notification_handlers.go`: `/phone-notification` endpoint — mirrors phone notifications via `notify-send`.
  - `upload_handlers.go`: `/upload` endpoint — receives files sent from the phone.
  - `lid_handlers.go`: `/inhibit-lid-sleep` endpoint — toggles lid-close suspend behaviour.
  - `helpers.go`: Shared HTTP helpers, path validation, lid state persistence.
  - `logging.go`: Log setup (file + stdout via `lumberjack`).
  - `config.go`: Constants (port, etc.).
  - `models.go`: Shared response structs.
- `android/`: Android-specific configuration and build files.

## Features

- **Real-time Monitoring**: Tracks CPU usage, RAM usage, CPU temperature, and Battery percentage.
- **Persistent Notifications**: Displays live laptop statistics in the Android status bar.
- **Remote Sleep**: Put the laptop to sleep directly from the mobile app via `systemctl suspend`.
- **IP Persistence**: Remembers the laptop's IP address across app launches.
- **Phone Notification Sync**: Forwards Android notifications to the laptop for desktop popups (Reverse Sync).
- **Custom Polling**: Configurable refresh interval for battery and performance stats (1s to 30s).
- **File Transfer**: Send files from the phone to the laptop's `~/Downloads/phone_transfers/` directory.
- **Lid Inhibit**: Prevent the laptop from sleeping when the lid is closed.
- **Welcome Tour**: A walkthrough for first-time users.
- **Settings Menu**: Sidebar (Drawer) navigation to separate Dashboard, File Transfer, and Settings.

## Tech Stack

- **Frontend**: Flutter (Dart)
  - `http`: For daemon API requests.
  - `flutter_local_notifications`: For persistent status bar updates.
  - `shared_preferences`: For persisting IP, onboarding state, and preferences.
  - `permission_handler`: For managing notification and system permissions.
  - `file_picker` / `dio`: For file selection and chunked uploads.
- **Native Android (Kotlin)**:
  - `MethodChannel`: For checking notification access and opening system settings.
  - `EventChannel`: For streaming live notifications to the Dart side.
  - `NotificationListenerService`: For intercepting system notifications.
- **Backend (Laptop)**: Go
  - `gopsutil/v3`: For CPU and RAM statistics.
  - `upower` (CLI): For battery statistics on Linux.
  - `loginctl` (CLI): For lid-close behaviour.
  - `notify-send` (CLI): For displaying mirrored notifications on the laptop.
  - `lumberjack`: For rotating log files.

## Build & Run

### Daemon

```bash
cd daemon/go
go run .
```

### Mobile App

```bash
# Get dependencies
flutter pub get

# Build APK
flutter build apk --release
```

## Maintenance

- **Daemon Logs**: Located at `daemon/go/stats_daemon.log`.
- **Uploaded Files**: Saved to `~/Downloads/phone_transfers/` on the laptop.
- **Git Repository**: [https://github.com/CosmicPegasis/laptop-dashboard-mobile](https://github.com/CosmicPegasis/laptop-dashboard-mobile)

## How To Contribute

Always write tests For all new features.
Delete tests for redundant or deprecated features.


# How to Write Git Commits
Always add which agent, in which editor was used to write the commit
Break down the diffs into smaller logically related commits when committing code.