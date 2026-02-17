# AGENTS.md

## Project Overview
Flutter mobile app with a Python daemon.

## Tech Stack
- **Mobile**: Flutter (Dart)
- **Daemon**: Python (`http.server`, `psutil`)

## Build Instructions
- Build Android APK: `flutter build apk --release`

## Dev Tips
- The stats daemon runs on port `8081`.
- Log files are located at `daemon/stats_daemon.log`.

## Conventions
- Use standard logging practices for both Flutter and Python components.
- Keep manifest permissions updated when adding new features that require system access.
