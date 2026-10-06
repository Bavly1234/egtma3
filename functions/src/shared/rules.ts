/**
 * Pure business rules. Mirrors lib/features/attendance/domain/absence_rules.dart
 * and lib/features/birthdays/domain/birthday_rules.dart in the Flutter app.
 * This server copy is the authority: only Cloud Functions create suggestions.
 */

export const PHONE_THRESHOLD = 2;
export const HOME_VISIT_THRESHOLD = 4;
export const OVERDUE_DAYS = 7;

export type AttendanceStatus = "present" | "absent";
export type SuggestionType = "phone" | "home_visit";
export type SuggestionStatus =
  | "pending"
  | "assigned"
  | "in_progress"
  | "completed"
  | "dismissed"
  | "cancelled";

export const ACTIVE_STATUSES: SuggestionStatus[] = ["pending", "assigned", "in_progress"];

export const isActive = (s: SuggestionStatus): boolean => ACTIVE_STATUSES.includes(s);

export interface Mark {
  meetingId: string; // yyyy-MM-dd
  status: AttendanceStatus;
}

export interface Streak {
  count: number;
  startMeetingId: string | null;
}

export interface ExistingSuggestion {
  id: string;
  type: SuggestionType;
  status: SuggestionStatus;
  streakStartMeetingId: string | null;
}

export interface Decision {
  create: SuggestionType | null;
  cancelIds: string[];
}

/** Rule C: count absences from the latest meeting back to the first attendance. */
export function computeStreak(marks: Mark[]): Streak {
  const sorted = [...marks].sort((a, b) => b.meetingId.localeCompare(a.meetingId));
  let count = 0;
  let start: string | null = null;
  for (const m of sorted) {
    if (m.status === "present") break;
    count++;
    start = m.meetingId;
  }
  return count === 0 ? { count: 0, startMeetingId: null } : { count, startMeetingId: start };
}

export function requiredType(consecutive: number): SuggestionType | null {
  if (consecutive >= HOME_VISIT_THRESHOLD) return "home_visit"; // Rule B
  if (consecutive >= PHONE_THRESHOLD) return "phone"; // Rule A
  return null;
}

/**
 * Rules A, B, D, E.
 *  - never create when an active suggestion of the same type exists (D)
 *  - one suggestion per type per absence streak, so completed ones are not
 *    re-created next week and remain in history (E)
 *  - escalating to a home visit cancels any active phone suggestion
 *  - attending again cancels suggestions nobody has started (pending/assigned)
 */
export function decide(streak: Streak, existing: ExistingSuggestion[]): Decision {
  if (streak.count === 0) {
    return {
      create: null,
      cancelIds: existing
        .filter((s) => s.status === "pending" || s.status === "assigned")
        .map((s) => s.id),
    };
  }
  const type = requiredType(streak.count);
  if (type === null) return { create: null, cancelIds: [] };

  const activeOf = (t: SuggestionType) => existing.some((s) => s.type === t && isActive(s.status));
  const forStreak = (t: SuggestionType) =>
    existing.some((s) => s.type === t && s.streakStartMeetingId === streak.startMeetingId);

  const cancelIds: string[] = [];
  if (type === "home_visit") {
    cancelIds.push(
      ...existing.filter((s) => s.type === "phone" && isActive(s.status)).map((s) => s.id),
    );
  } else if (activeOf("home_visit")) {
    return { create: null, cancelIds: [] };
  }
  const create = !activeOf(type) && !forStreak(type) ? type : null;
  return { create, cancelIds };
}

/** Feb 29 birthdays are celebrated on Feb 28 in non-leap years. */
export function isBirthdayOn(dobMonth: number, dobDay: number, y: number, m: number, d: number): boolean {
  const leap = (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
  if (dobMonth === 2 && dobDay === 29 && !leap) return m === 2 && d === 28;
  return dobMonth === m && dobDay === d;
}

/** Rule G: deterministic id => one birthday notification per woman/recipient/year. */
export const birthdayNotificationId = (womanId: string, recipientId: string, year: number) =>
  `birthday_${womanId}_${recipientId}_${year}`;

export function suggestionReason(type: SuggestionType, count: number): string {
  return type === "home_visit"
    ? `غائبة منذ ${count} اجتماعات متتالية.`
    : `غابت ${count} اجتماعات متتالية.`;
}
