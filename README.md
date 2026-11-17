# PaisaPilot

An on-device, UPI-first expense tracker for India. Flutter, Android first.

Your transactions never leave the phone: PaisaPilot reads bank alerts from the SMS inbox, card alerts from Gmail and
bank statements from PDF, all on the device, and keeps everything in a local SQLite database.

## Features

- **SMS import:** reads Canara (six alert formats), ICICI, CGG Bank, FamPay and slice card alerts from the inbox.
  A payment that arrives as two alerts (a UPI alert and a balance-only alert) is stored once.
- **Gmail import:** slice savings-account alerts, read with read-only Gmail access straight from the phone.
- **Statement import:** Canara e-passbook PDFs are read on the phone (PDFium) and reconciled against the app:
  the statement's count for its dates must match what the app has, or the app flags duplicates or missing rows.
- **Home:** spent, received and net per month, spending by category, recent transactions.
- **Activity:** search, category tabs, spent/received filter, largest-first sort; tap a transaction to set its
  category (optionally for everything from that payee), attach photos (kept privately on the phone) or delete it.
- **Categories:** keyword rules first; user labels win over rules.

## Layout

- `app/` - the Flutter app (`app/lib/import` parsers and importer, `app/lib/data` drift database, `app/lib/ui`).
- `docs/schema.sql` - the SQLite schema (mirrored by `app/lib/data/schema.drift`).
- `docs/ai-agent-plan.md` - plan for an AI assistant (on hold).
- `tools/` - the original Python reference parsers and categoriser.

## Build

Requires Flutter 3.50 (Dart 3.14) and the Android SDK.

```sh
cd app
flutter pub get
dart run build_runner build                       # drift code
flutter test --timeout 60s --dart-define-from-file=../data/personal_rules.json
flutter build apk --debug --dart-define-from-file=../data/personal_rules.json
```

`data/` is git-ignored and holds private files only. `data/personal_rules.json` adds personal categoriser keywords
(your own name for self transfers, family names, and so on); copy `personal_rules.example.json` there and edit it.
Without it the app still builds; those rules just match nothing.

Gmail import needs your own Google Cloud OAuth clients (an Android client for the package name and signing key,
and a Web client whose ID replaces `_serverClientId` in `app/lib/import/gmail_source.dart`).
