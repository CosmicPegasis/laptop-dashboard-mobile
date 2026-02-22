# Laptop Dashboard Mobile

Flutter app + Go daemon for monitoring laptop stats from your phone and running remote actions.

## Features

- Live laptop telemetry (CPU, RAM, temperature, battery)
- Remote suspend (`/sleep` endpoint)
- Persistent Android status notification with laptop stats
- Reverse sync: forwards phone notifications to the laptop daemon (`/phone-notification`)
- File transfer: send files from phone to laptop (`/upload`)
- Lid inhibit: prevent laptop from sleeping on lid close

## Run the daemon (laptop)

```bash
cd daemon/go
go run .
```

Daemon listens on `0.0.0.0:8081`. Logs are written to `daemon/go/stats_daemon.log`.

## Run the app (phone)

```bash
flutter pub get
flutter run
```

## Reverse sync setup

1. In the app, open `Settings`.
2. Enable `Forward phone notifications to laptop`.
3. Tap `Open notification access` and allow this app.
4. Keep the daemon running on your laptop.

When enabled, new phone notifications are POSTed to:

- `http://<laptop-ip>:8081/phone-notification`

The daemon logs each event and attempts a desktop popup using `notify-send` if installed.
