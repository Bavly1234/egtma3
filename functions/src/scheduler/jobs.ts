import { LocalNow, TUESDAY, WEDNESDAY } from "../shared/dates.js";

export const VERSE_HOUR = 6;
export const BIRTHDAY_HOUR = 8;
export const CONFERENCE_HOUR = 9;

/** Pure: which jobs run at this local hour (unit-tested). */
export function jobsFor(now: LocalNow, s: Record<string, unknown>): string[] {
  const h = (k: string, d: number) => (typeof s[k] === "number" ? (s[k] as number) : d);
  const jobs: string[] = [];
  if (now.hour === VERSE_HOUR) jobs.push("verse");
  if (now.hour === BIRTHDAY_HOUR) jobs.push("birthdays");
  if (now.hour === CONFERENCE_HOUR) jobs.push("conferences");
  if (now.hour === h("followUpReminderHour", 10)) jobs.push("followUps");
  if (now.weekday === TUESDAY && now.hour === h("meetingReminderHour", 18)) jobs.push("meeting");
  if (now.weekday === WEDNESDAY && now.hour === h("attendanceReminderHour", 21)) jobs.push("attendance");
  return jobs;
}

