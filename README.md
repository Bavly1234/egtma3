# Egtma3 — اجتماع السيدات

A Flutter + Firebase app for running a church women's meeting: Wednesday
attendance, automatic follow-up (افتقاد) suggestions, servants' and women's
statistics, three-day conferences, birthdays, a daily Bible verse, phone
notifications, and Excel import/export.

**Runs entirely on Firebase's free Spark plan.** There are no Cloud
Functions and no billing account. All automation runs inside the app,
following the same approach as `eftekad_app`.

The UI is Arabic and right-to-left, with large fonts and buttons designed for
older users. Code and database fields are in English.

---

## Stack

| Layer | Technology |
|---|---|
| App | Flutter 3.47 (Dart 3.13), Riverpod 3, go_router |
| Auth | Firebase Authentication (email/password) |
| Database | Cloud Firestore (offline persistence on) |
| Automation | On-device engine (no server): follow-up rules, counters, reminders |
| Notifications | `flutter_local_notifications` (scheduled on the phone) + in-app notification center |
| Quality | Crashlytics, Analytics, App Check |
| Excel | `excel`, `file_picker`, `file_saver` |

Firebase project: **`egtma3-church-app`** (Firestore location `nam5`).

---

## Architecture

```
lib/
  core/            constants (enums, Firestore paths, business rules), theme,
                   shared widgets, services (sync status, local notifications, dialer/WhatsApp),
                   routing (go_router + role guard), error mapping, logging
  features/<feature>/
    domain/        pure models + business logic (unit-tested, no Firebase)
    data/          repositories (the only code that talks to Firebase)
    presentation/  screens, widgets, Riverpod providers/controllers
```

Each feature has its own `domain`, `data`, and `presentation` folders. Widgets
contain no business logic: the rules live in `domain/` and are unit-tested.

### Free-plan design (no server)
| Job a server would normally do | Where it runs now |
|---|---|
| Absence analysis → suggestions | `AbsenceProcessor` runs on the phone right after attendance is saved, even offline |
| Meeting dashboard counters | Incremented in the same batch as each attendance mark |
| Call/visit counters on a woman | Written in the same batch as the follow-up record |
| Street counts, reassignment, cancelling on deactivate | `WomenRepository` |
| Creating accounts | Self sign-up in the app with the join code, checked by Firestore rules |
| Reminders (Tuesday, Wednesday, birthdays, conference, verse, pending follow-ups) | Scheduled on each phone with `flutter_local_notifications`; they fire even when the app is closed |
| A new follow-up created on another phone | Saved to the notification center; the phone shows it immediately if the app is running, otherwise as a summary on next open |

**Duplicate protection without a server.**
- Suggestion ids are deterministic (`{woman}_{type}_{streakStart}`), so two
  phones processing the same absence streak write the same document.
- Notification ids are deterministic too, and the rules allow `create` but
  never `update`, so a repeat is rejected.
- Attendance ids are `{meeting}_{woman}`.

### Firestore collections

| Collection | Contents |
|---|---|
| `users/{uid}` | name, email, phone, role (`father`/`servant`), active, notificationPrefs, textScale |
| `women/{id}` | fullName, nameNormalized, searchKeywords, streetId, streetName, address, phone (normalised), dateOfBirth, birthMonth, birthDay, active, assignedServantId/Name, notes. **Summary fields kept up to date by the app's follow-up engine:** consecutiveAbsences, totalPresent, totalAbsent, phoneCalls, homeVisits, lastCallAt, lastVisitAt, lastAttendanceDate, activeSuggestionType |
| `streets/{id}` | name, nameNormalized, womenCount |
| `attendance/{meetingId}_{womanId}` | meetingId (`yyyy-MM-dd`), womanId, servantId, streetId, status, markedBy, markedAt. The deterministic id makes duplicates impossible. |
| `meetings/{yyyy-MM-dd}` | present/absent counters, byStreet, byServant |
| `follow_ups/{id}` | Immutable history of calls, visits and notes: woman, servant, type, result, notes, occurredAt, suggestionId |
| `follow_up_suggestions/{id}` | type (`phone`/`home_visit`), status, consecutiveAbsences, streakStartMeetingId, reason, assigned servant |
| `conferences/{id}` | name, `days[3]` (id, index, date), dayIds |
| `conference_attendance/{conf}_{day}_{woman}` | conferenceId, conferenceDayId, womanId, attendanceStatus, timestamp. Separate from Wednesday attendance. |
| `notifications/{dedupeId}` | recipientId, title, message, type, relatedEntityId/Type, createdAt, readAt |
| `daily_verses/{yyyy-MM-dd}` | Optional per-day override of the bundled verse pool |
| `settings/app` | reminder hours, birthday and verse toggles, `fatherIds` |
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
| See all women, attendance, follow-ups, conferences | ✅ | ✅ |
| Take attendance, record calls/visits/notes, complete follow-ups | ✅ all women | ✅ |
| Edit woman notes | ✅ | ✅ |
| Add / edit / delete / deactivate women | ❌ | ✅ |
| Assign women to servants, streets, conferences, users | ❌ | ✅ |
| Statistics | her own + church overview | everything |
| Excel import/export, audit log, settings | ❌ | ✅ |
| Dismiss a suggestion | ❌ | ✅ |

**Assignment is optional.** A woman can be assigned to a servant, but every
servant still sees and works on every woman. The assignment shows on each
card ("الخادمة: …", plus "✓ معيّنة لكِ" on your own). The women list has an
"المعيّنات لي فقط" chip, and the women, attendance and follow-up screens can
filter by servant. Servants get birthday reminders for the women assigned to
them, and new follow-ups notify the assigned servant (or the father, if the
woman is unassigned).

Permissions are enforced in three places: the UI (`Permissions`), the router
guard (`Routes.isFatherOnly`), and, authoritatively, `firestore.rules`.
- Any active servant can read everything and record attendance and follow-ups
  for any woman.
- Servants can only change a woman's notes and summary fields; they can't
  rename, delete or reassign her.
- Servants can't dismiss suggestions or change any role.
- Follow-up history and audit logs are append-only.
- Disabling a servant sets `active: false`. The rules then deny her every
  read and write, and the app shows "الحساب غير مفعّل".

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

The rules are in `lib/features/attendance/domain/absence_rules.dart`.
`AbsenceProcessor` applies them after every mark: it recomputes the streak
from the attendance records and writes the suggestions in one batch.

### Other rules
- **Rule F:** conference attendance lives in `conference_attendance` and never
  affects Wednesday statistics.
- **Rule G:** birthday notification ids are `birthday_{woman}_{recipient}_{year}`
  and are created with `create()`, so there is exactly one per year per
  recipient. Feb 29 birthdays are celebrated on Feb 28 in non-leap years.
- **Rule H:** Excel duplicates are skipped (see below).

### Notifications (on the phone)
| When | Notification |
|---|---|
| Tuesday at the configured hour (default 18:00), weekly | "غداً اجتماع السيدات" |
| Wednesday at the configured hour (default 21:00), weekly | Attendance reminder |
| Daily at the configured hour (default 10:00), if anything is pending | "لديك n افتقاد لم يتم" |
| 07:00 each day (next 14 days are scheduled) | 📖 آية اليوم |
| 08:00 on each birthday (next 60 days) | 🎂 Birthday of an assigned woman (father: all women, if enabled) |
| Evening before and morning of each conference day | Conference reminders |
| Immediately, while the app is running | New follow-up suggestions created on another phone |

Reminders are re-planned on login, whenever the app returns to the
foreground, and after settings change. Each user can switch every kind off
in Settings. Birthdays are also written once per year to the in-app
notification center (Rule G).

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
Flutter 3.47+, Firebase CLI (`npm i -g firebase-tools`), FlutterFire
CLI (`dart pub global activate flutterfire_cli`), and Java 17 for Android.

```bash
cd C:\egtma3
flutter pub get
```

### Firebase (already done for `egtma3-church-app`)
```bash
firebase login
firebase use egtma3-church-app
dart pub global run flutterfire_cli:flutterfire configure --project=egtma3-church-app --platforms=android,ios,web
firebase deploy --only firestore          # rules + indexes (free plan)
```

### Manual steps
1. **Enable Email/Password sign-in** (free): Console → Authentication →
   Sign-in method → Email/Password → Enable.
2. **Accounts (same as eftekad_app):** anyone opens the app → "حساب جديد" →
   name, email, password, chooses **خادمة** or **الأب الكاهن**, and enters the
   **join code** (`897373`). Firestore rules check the code; with a wrong code
   the new account is deleted again. To change the code, edit `joinCode()` at
   the top of `firestore.rules` and run `firebase deploy --only firestore:rules`.
3. The father can later disable an account, change its role, or send a
   password-reset email from المستخدمون.
4. **Optional, App Check:** Console → App Check → register Play Integrity
   (Android) and App Attest (iOS) before enforcing.
5. **iOS:** run `flutterfire configure` on a Mac. Local notifications need no
   extra setup.

No Blaze plan, billing account or Cloud Functions are needed.

---

## Running

```bash
flutter run                      # device/emulator
flutter run -d chrome            # web
firebase emulators:start         # local firestore + auth emulators
```

### Demo data
Go to Settings (father) → "إضافة بيانات تجريبية". This adds 18 women
assigned to you, 3 streets, 6 Wednesdays of attendance (which create real
phone and home-visit suggestions), and a conference. Everything is marked
"(تجريبي)" and `isDemo`. Remove it with "حذف البيانات التجريبية" before real
use.

---

## Testing

```bash
flutter analyze
flutter test                                 # unit + widget + repository tests
flutter test integration_test -d <device>    # on-device smoke test
```

| Suite | Covers |
|---|---|
| `test/unit/absence_rules_test.dart` | Rules A–E and the spec scenario |
| `test/unit/utils_test.dart` | Phone normalisation, Arabic text, dates, birthdays (Rule G) |
| `test/unit/excel_import_test.dart` | Column detection, validation, duplicates (Rule H), xlsx round trip |
| `test/unit/filters_permissions_conference_test.dart` | Filters, role permissions and router guard, conference statistics (Rule F) |
| `test/unit/repositories_test.dart` | Real repositories on in-memory Firestore: CRUD, scoping, no duplicate attendance, conference separation, follow-up history, notification center |
| `test/widget/widgets_test.dart` | Attendance screen interaction, accessible cards |
| `test/unit/on_device_engine_test.dart` | On-device engine: spec scenario end to end, no duplicates across two phones, father notified for home visits; reminder planning (hours, birthdays, conferences, verse, preferences, unique ids) |

---

## Build and deploy

```bash
flutter build apk --release          # Android APK
flutter build appbundle --release    # Play Store
flutter build web --release && firebase deploy --only hosting
firebase deploy --only firestore:rules
firebase deploy --only firestore:indexes
```

Release signing: create `android/key.properties` and a keystore (both
git-ignored) and reference them in `android/app/build.gradle.kts`.

## Production checklist
- [ ] Email/Password enabled, rules deployed
- [ ] Father and servants registered with the join code
- [ ] Demo data removed, join code changed if it leaked
- [ ] App Check enforced after verification
- [ ] Release signing configured
- [ ] Review `settings/app` reminder hours

## Security notes
- No secrets in the app. `firebase_options.dart` contains public client
  identifiers only.
- The join code lives only in `firestore.rules` (server side), never in the
  app. Never add service-account keys to the repository.
- Logs never include names, phones or addresses. Crashlytics only collects in
  release builds.
