# Laptop Dashboard Mobile

Flutter-based mobile app and Go daemon for monitoring laptop statistics and performing remote actions (like sleep).

## Project Structure

- `lib/`: Flutter mobile app source code.
  - `main.dart`: Core application logic, including UI, state management, and notification handling.
- `daemon/`: Python daemon that runs on the laptop.
  - `stats_daemon.py`: Collects CPU, RAM, Temperature, and Battery stats and serves them over HTTP (port 8081).
- `android/`: Android-specific configuration and build files.

## Features

- **Real-time Monitoring**: Tracks CPU usage, RAM usage, CPU temperature, and Battery percentage.
- **Persistent Notifications**: Displays live laptop statistics in the Android status bar.
- **Remote Sleep**: Put the laptop to sleep directly from the mobile app via `systemctl suspend`.
- **IP Persistence**: Remembers the laptop's IP address across app launches.
- **Phone Notification Sync**: Forwards Android notifications to the laptop for desktop popups (Reverse Sync).
- **Custom Polling**: Configurable refresh interval for battery and performance stats (1s to 30s).
- **Welcome Tour**: A walkthrough for first-time users.
- **Settings Menu**: Sidebar (Drawer) navigation to separate Dashboard and Settings.

## Tech Stack

- **Frontend**: Flutter (Dart)
  - `http`: For daemon API requests.
  - `flutter_local_notifications`: For persistent status bar updates.
  - `shared_preferences`: For persisting IP, onboarding state, and preferences.
  - `permission_handler`: For managing notification and system permissions.
- **Native Android (Kotlin)**:
  - `MethodChannel`: For checking notification access and opening system settings.
  - `EventChannel`: For streaming live notifications to the Dart side.
  - `NotificationListenerService`: For intercepting system notifications.
- **Backend (Laptop)**: Go
  - `psutil`: For system statistics.
  - `upower`: Fallback for battery statistics on certain Linux setups.
  - `http.server`: Minimal API server handling `/stats`, `/sleep`, and `/phone-notification`.
  - `notify-send`: For displaying mirrored notifications on the laptop.

## Build & Run

### Daemon
```bash
cd daemon/go
go run main.go
```

### Mobile App
```bash
# Get dependencies
flutter pub get

# Build APK
flutter build apk --release
```

## Maintenance

- **Daemon Logs**: Located at `daemon/stats_daemon.log`.
- **Git Repository**: [https://github.com/CosmicPegasis/laptop-dashboard-mobile](https://github.com/CosmicPegasis/laptop-dashboard-mobile)

## How To Contribute

Always write tests For all new features.
Delete tests for redundant or deprecated features.


# How to Write Git Commits

Break down the diffs into smaller logically related commits when committing code.