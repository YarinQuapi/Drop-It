# drop_it

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Home screen widget and fast-end reminder

- **Widget (iOS)**: `ios/DropItWidget` is a WidgetKit extension (small + medium) showing today's
  calories (consumed / target) and the fasting timer (live countdown, or the scheduled window when
  no fast is running). The app writes the data via `lib/widget_sync.dart` (`home_widget`) into the
  App Group `group.dev.yarinlevi.dropit` every time `syncReminders()` runs (launch, resume, fast
  start/stop, add/delete entry, settings change).
- **One-time Apple setup**: enable the *App Groups* capability with `group.dev.yarinlevi.dropit` for
  both the `dev.yarinlevi.dropit` and `dev.yarinlevi.dropit.DropItWidget` App IDs in the developer
  portal (entitlements files are already in the repo). Then long-press the home screen > + > Drop It.
- **Android**: this repo has no `android/` project yet. When it is added, create an
  `AppWidgetProvider` named `DropItWidgetProvider` + layout, register the `<receiver>` in the
  manifest, and read the same keys that `widget_sync.dart` saves (`consumed`, `goal`, `fastRunning`,
  `fastEndsAt`, `fastStartHour`, `fastEndHour`, ...). See the `home_widget` package docs.
- **Fast-end notification**: Settings > "Notify me when my fast ends" (default off, stored locally in
  `prefs.json`). Scheduled for `endsAt` when a fast is running, cancelled on stop or when toggled off.
