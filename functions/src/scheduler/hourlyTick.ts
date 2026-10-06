import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { TIME_ZONE } from "../shared/admin.js";
import { localNow } from "../shared/dates.js";
import { jobsFor } from "./jobs.js";
import { appSettings } from "../shared/notify.js";
import { runBirthdays } from "../birthdays/birthdays.js";
import { attendanceReminder, conferenceReminders, followUpReminder, meetingReminder } from "../notifications/reminders.js";
import { publishDailyVerse } from "../verse/dailyVerse.js";

/**
 * One hourly scheduler drives every time-based automation (one Cloud
 * Scheduler job instead of six). Every job is idempotent via deterministic
 * notification ids, so retries never duplicate notifications.
 */
export const hourlyTick = onSchedule({ schedule: "0 * * * *", timeZone: TIME_ZONE, retryCount: 2 }, async () => {
  const now = localNow();
  const settings = await appSettings();
  const jobs = jobsFor(now, settings);
  const run: Record<string, () => Promise<unknown>> = {
    verse: () => publishDailyVerse(now, settings),
    birthdays: () => runBirthdays(now, settings),
    conferences: () => conferenceReminders(now),
    followUps: () => followUpReminder(now),
    meeting: () => meetingReminder(now),
    attendance: () => attendanceReminder(now),
  };
  for (const j of jobs) {
    try {
      await run[j]();
      logger.info(`job ${j} done`, { dayId: now.dayId, hour: now.hour });
    } catch (e) {
      logger.error(`job ${j} failed`, { error: String(e) });
    }
  }
});
