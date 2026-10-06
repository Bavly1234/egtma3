# Egtma3 — اجتماع السيدات

A Flutter + Firebase app for running a church women's meeting: Wednesday
attendance, automatic follow-up (افتقاد) suggestions, servants' and women's
statistics, three-day conferences, birthdays, a daily Bible verse, push
notifications, and Excel import/export.

The UI is Arabic and right-to-left, with large fonts and buttons designed for
older users. Code and database fields are in English.

---

## Stack

| Layer | Technology |
|---|---|
| App | Flutter 3.47 (Dart 3.13), Riverpod 3, go_router |
| Auth | Firebase Authentication (email/password) |
| Database | Cloud Firestore (offline persistence on) |
| Backend | Cloud Functions 2nd gen, TypeScript, Node 22, `us-central1` |
| Push | Firebase Cloud Messaging |
| Quality | Crashlytics, Analytics, App Check |
| Excel | `excel`, `file_picker`, `file_saver` |

Firebase project: **`egtma3-church-app`** (Firestore location `nam5`).

---

## Architecture

```
lib/
  core/            constants (enums, Firestore paths, business rules), theme,
                   shared widgets, services (sync status, FCM, dialer/WhatsApp),
                   routing (go_router + role guard), error mapping, logging
  features/<feature>/
    domain/        pure models + business logic (unit-tested, no Firebase)
    data/          repositories (the only code that talks to Firebase)
    presentation/  screens, widgets, Riverpod providers/controllers
functions/src/
  shared/          rules.ts (business rules), dates, notify, guards, admin
  attendance/      onAttendanceWritten — absence analysis + suggestions
  followups/       follow-up counters, activeSuggestionType
  women/           street counts, reassignment propagation, renames
  notifications/   FCM push trigger, reminder jobs
  birthdays/       birthday notifications
  verse/           daily verse publisher
  scheduler/       hourlyTick — one scheduler drives all timed jobs
  users/           createServant, setUserActive, setUserRole, bootstrapFather
  demo/            seedDemoData / removeDemoData
```

Each feature has its own `domain`, `data`, and `presentation` folders. Widgets
contain no business logic: the rules live in `domain/` (Dart) and
`functions/src/shared/rules.ts` (TypeScript), and both copies are tested.

### Firestore collections

| Collection | Contents |
|---|---|
| `users/{uid}` | name, email, phone, role (`father`/`servant`), active, notificationPrefs, textScale, fcmTokens |
| `women/{id}` | fullName, nameNormalized, searchKeywords, streetId, streetName, address, phone (normalised), dateOfBirth, birthMonth, birthDay, active, assignedServantId/Name, notes. **Maintained by functions:** consecutiveAbsences, totalPresent, totalAbsent, phoneCalls, homeVisits, lastCallAt, lastVisitAt, lastAttendanceDate, activeSuggestionType |
| `streets/{id}` | name, nameNormalized, womenCount (functions) |
| `attendance/{meetingId}_{womanId}` | meetingId (`yyyy-MM-dd`), womanId, servantId, streetId, status, markedBy, markedAt. The deterministic id makes duplicates impossible. |
| `meetings/{yyyy-MM-dd}` | present/absent counters, byStreet, byServant (functions) |
| `follow_ups/{id}` | Immutable history of calls, visits and notes: woman, servant, type, result, notes, occurredAt, suggestionId |
| `follow_up_suggestions/{id}` | type (`phone`/`home_visit`), status, consecutiveAbsences, streakStartMeetingId, reason, assigned servant |
| `conferences/{id}` | name, `days[3]` (id, index, date), dayIds |
| `conference_attendance/{conf}_{day}_{woman}` | conferenceId, conferenceDayId, womanId, attendanceStatus, timestamp. Separate from Wednesday attendance. |
| `notifications/{dedupeId}` | recipientId, title, message, type, relatedEntityId/Type, createdAt, readAt |
| `daily_verses/{yyyy-MM-dd}`, `verse_pool/{id}` | Arabic verse text and reference |
| `settings/app` | reminder hours, birthday and verse toggles |
| `audit_logs/{id}` | append-only: action, actor, entity, summary, createdAt |

**Design decisions**
- Conference days are embedded in the conference document rather than stored
  in a `days` subcollection. A conference always has exactly three days, so a
  subcollection would only add reads.
- Attendance history is never stored inside the woman document.
- Statistics use Firestore `count()` aggregations and function-maintained
  `meetings` counters, never full collection scans.
- The women list uses equality filters in Firestore with pagination of 30.
  Range-type filters (absence count, attendance %) are applied in memory to
  each loaded page.

---

## Roles and permissions

| | خادمة (servant) | الأب الكاهن (father) |
|---|---|---|
| Her assigned women: view, attendance, calls/visits/notes | ✅ | ✅ all women |
| Edit woman notes | ✅ assigned only | ✅ |
| Add / edit / delete / deactivate women | ❌ | ✅ |
| Assign servants, streets, conferences, users | ❌ | ✅ |
| Statistics | her own | everything |
| Excel import/export, audit log, settings | ❌ | ✅ |
| Dismiss a suggestion | ❌ | ✅ |

Permissions are enforced in three places: the UI (`Permissions`), the router
guard (`Routes.isFatherOnly`), and, authoritatively, `firestore.rules` and the
callable functions (`requireFather`). Servants cannot read women who are not
assigned to them, cannot write server-maintained counters, and cannot create
suggestions or notifications. Follow-up history and audit logs cannot be
edited.

---

## Business logic

### Absence rules

| Rule | Behaviour |
|---|---|
| A | **2 consecutive Wednesday absences** → `افتقاد تليفوني` (phone) suggestion |
| B | **4 or more** → `افتقاد منزلي` (home visit). Higher priority; any still-active phone suggestion is cancelled as "escalated". |
| C | Attending resets the count; older absences are ignored. |
| D | Never two active suggestions of the same type. |
| E | Completed suggestions stay in history. Each absence streak (identified by its first missed meeting) produces at most one suggestion of each type, so nothing is re-created week after week. |

When she attends again, suggestions nobody has started yet (`pending`/`assigned`)
are cancelled. Work already `in_progress` is kept.

Statuses: `pending, assigned, in_progress, completed, dismissed, cancelled`.

The authoritative implementation is `functions/src/attendance/onAttendanceWritten.ts`.
It runs in a Firestore transaction, recomputes the streak from the attendance
records, and calls `decide()` from `rules.ts`. The Dart mirror is
`lib/features/attendance/domain/absence_rules.dart`.

### Other rules
- **Rule F:** conference attendance lives in `conference_attendance` and never
  affects Wednesday statistics.
- **Rule G:** birthday notification ids are `birthday_{woman}_{recipient}_{year}`
  and are created with `create()`, so there is exactly one per year per
  recipient. Feb 29 birthdays are celebrated on Feb 28 in non-leap years.
- **Rule H:** Excel duplicates are skipped (see below).

### Automation (`hourlyTick`, Africa/Cairo time)
| Hour | Job |
|---|---|
| 06:00 | Publish آية اليوم and notify |
| 08:00 | Birthday notifications to the servant (and the father, if enabled) |
| 09:00 | Conference "tomorrow" / "today" reminders |
| settings (default 10:00) | Pending follow-up reminder per servant |
| Tue, settings (default 18:00) | "غداً اجتماع السيدات" |
| Wed, settings (default 21:00) | Reminder to servants whose attendance is incomplete |

Every notification has a deterministic id, so retries never duplicate. The
`onNotificationCreated` trigger pushes each notification through FCM,
respects the user's preferences, and removes invalid tokens.

---

## Excel format

The first row holds the headers, in any order. English or Arabic both work:

| Field | Accepted headers |
|---|---|
| Name | `name`, `الاسم` |
| Street | `street`, `الشارع` |
| Address | `address`, `العنوان` |
| Phone | `phone`, `mobile`, `التليفون`, `الهاتف`, `الموبايل` |
| Date of birth | `date of birth`, `dob`, `تاريخ الميلاد` |

- Dates can be `15/03/1970`, `1970-03-15`, Arabic digits, or real Excel dates.
- Phones are normalised: `+201012345678`, `00201012345678` and `1012345678`
  all become `01012345678`.
- **Duplicates.** A row is a duplicate if it has the same phone and the same
  name or birth date; or the same name and birth date; or the same name and
  address. Matching is done after Arabic normalisation (أ/إ/آ→ا, ى→ي, ة→ه, no
  diacritics or "السيدة"). This applies against the database and within the
  file itself. A shared family phone on its own is not a duplicate.
- The preview shows **new / duplicate / invalid** rows. Only "new" rows are
  written, and only after confirmation. Existing records are never deleted.

Export (father only) covers all women, the women matching the **current
filters** on the women screen, attendance, follow-ups, a conference's
attendance, and servant statistics for a date range.

---

## Setup

### Prerequisites
Flutter 3.47+, Node 22+, Firebase CLI (`npm i -g firebase-tools`), FlutterFire
CLI (`dart pub global activate flutterfire_cli`), and Java 17 for Android.

```bash
cd C:\egtma3
flutter pub get
cd functions && npm install && cd ..
```

### Firebase (already done for `egtma3-church-app`)
```bash
firebase login
firebase use egtma3-church-app
dart pub global run flutterfire_cli:flutterfire configure --project=egtma3-church-app --platforms=android,ios,web
firebase deploy --only firestore          # rules + indexes
```

### Manual steps (cannot be automated from the CLI)
1. **Upgrade to the Blaze plan** (required for Cloud Functions):
   https://console.firebase.google.com/project/egtma3-church-app/usage/details
2. **Enable Email/Password sign-in:** Console → Authentication → Sign-in method
   → Email/Password → Enable.
3. Deploy functions:
   ```bash
   firebase deploy --only functions
   ```
   The first deploy asks for `BOOTSTRAP_CODE` and `ALLOW_DEMO_DATA` if
   `functions/.env` is missing. A `.env` with a random code was generated
   locally and is git-ignored.
4. **Create the father account:** open the app → "الإعداد الأول" → enter name,
   email, password and the `BOOTSTRAP_CODE` from `functions/.env`. This only
   works while no father exists.
5. **App Check:** Console → App Check → register Play Integrity (Android) and
   App Attest (iOS). For debug builds, add the debug token printed in logcat.
   Turn on enforcement only after verifying.
6. **iOS push:** upload an APNs auth key (Console → Project settings → Cloud
   Messaging), enable Push Notifications and Background Modes → Remote
   notifications in Xcode, then run `flutterfire configure` on a Mac.
7. **Web push (optional):** generate a VAPID key (Cloud Messaging → Web
   configuration) and build with `--dart-define=FCM_VAPID_KEY=...`.
8. **Password-reset email language:** optionally edit the template in
   Authentication → Templates.

---

## Running

```bash
flutter run                      # device/emulator
flutter run -d chrome            # web
cd functions && npm run serve    # local emulators (functions, firestore, auth)
```

### Demo data
With `ALLOW_DEMO_DATA=true` in `functions/.env`, go to Settings (father) →
"إضافة بيانات تجريبية". This adds 18 women, 2 demo servants, 3 streets,
6 Wednesdays of attendance (which trigger real phone and home-visit
suggestions), and one conference. Everything is flagged `isDemo`. Remove it
with "حذف البيانات التجريبية", and set `ALLOW_DEMO_DATA=false` before
production.

---

## Testing

```bash
flutter analyze
flutter test                                 # unit + widget + repository tests
flutter test integration_test -d <device>    # on-device smoke test
cd functions && npm test                     # server business-rule tests
```

| Suite | Covers |
|---|---|
| `test/unit/absence_rules_test.dart` | Rules A–E and the spec scenario |
| `test/unit/utils_test.dart` | Phone normalisation, Arabic text, dates, birthdays (Rule G) |
| `test/unit/excel_import_test.dart` | Column detection, validation, duplicates (Rule H), xlsx round trip |
| `test/unit/filters_permissions_conference_test.dart` | Filters, role permissions and router guard, conference statistics (Rule F) |
| `test/unit/repositories_test.dart` | Real repositories on in-memory Firestore: CRUD, scoping, no duplicate attendance, conference separation, follow-up history, notification center |
| `test/widget/widgets_test.dart` | Attendance screen interaction, accessible cards |
| `functions/src/__tests__` | Server rules A–G, scheduler planning, birthday recipients, Cairo time |

---

## Build and deploy

```bash
flutter build apk --release          # Android APK
flutter build appbundle --release    # Play Store
flutter build web --release && firebase deploy --only hosting
firebase deploy --only functions
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

Release signing: create `android/key.properties` and a keystore (both
git-ignored) and reference them in `android/app/build.gradle.kts`.

## Production checklist
- [ ] Blaze plan, Email/Password enabled, functions deployed
- [ ] Father created through the bootstrap screen, then servants added from المستخدمون
- [ ] `ALLOW_DEMO_DATA=false`, demo data removed
- [ ] App Check enforced after verification
- [ ] Release signing configured
- [ ] Review `settings/app` reminder hours

## Security notes
- No secrets in the app. `firebase_options.dart` contains public client
  identifiers only.
- `functions/.env` (bootstrap code) is git-ignored. Never add service-account
  keys to the repository.
- Logs never include names, phones or addresses. Crashlytics only collects in
  release builds.
