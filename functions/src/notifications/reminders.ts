import { C, db, Timestamp } from "../shared/admin.js";
import { addDays, displayDate, LocalNow } from "../shared/dates.js";
import { activeUsers, notify } from "../shared/notify.js";
import { ACTIVE_STATUSES, OVERDUE_DAYS } from "../shared/rules.js";

/** Tuesday: "غداً اجتماع السيدات". */
export async function meetingReminder(now: LocalNow): Promise<void> {
  const meetingId = addDays(now.dayId, 1);
  const users = await activeUsers();
  await Promise.all(
    users.map((u) =>
      notify({
        id: `meeting_reminder_${meetingId}_${u.id}`,
        recipientId: u.id,
        title: "غداً اجتماع السيدات",
        message: `اجتماع الأربعاء ${displayDate(meetingId)}. يرجى تسجيل الحضور.`,
        type: "reminder",
        relatedEntityId: meetingId,
        relatedEntityType: "meeting",
      }),
    ),
  );
}

/** Wednesday evening: remind servants who still have unmarked women. */
export async function attendanceReminder(now: LocalNow): Promise<void> {
  const meetingId = now.dayId;
  const servants = await activeUsers("servant");
  for (const s of servants) {
    const [assigned, marked] = await Promise.all([
      db.collection(C.women).where("assignedServantId", "==", s.id).where("active", "==", true).count().get(),
      db.collection(C.attendance).where("meetingId", "==", meetingId).where("servantId", "==", s.id).count().get(),
    ]);
    const missing = assigned.data().count - marked.data().count;
    if (missing <= 0) continue;
    await notify({
      id: `attendance_reminder_${meetingId}_${s.id}`,
      recipientId: s.id,
      title: "لم يتم تسجيل الحضور بالكامل",
      message: `باقي ${missing} سيدة لم يُسجل حضورها في اجتماع اليوم.`,
      type: "attendance",
      relatedEntityId: meetingId,
      relatedEntityType: "meeting",
    });
  }
}

/** Daily: pending follow-ups per servant (one reminder per servant per day). */
export async function followUpReminder(now: LocalNow): Promise<void> {
  const pending = await db.collection(C.suggestions).where("status", "in", ACTIVE_STATUSES).get();
  const overdueBefore = Timestamp.fromMillis(Date.now() - OVERDUE_DAYS * 86400000);
  const byServant = new Map<string, { total: number; overdue: number }>();
  for (const d of pending.docs) {
    const sid = d.get("assignedServantId");
    if (!sid) continue;
    const e = byServant.get(sid) ?? { total: 0, overdue: 0 };
    e.total++;
    const created = d.get("createdAt") as Timestamp | undefined;
    if (created && created.toMillis() < overdueBefore.toMillis()) e.overdue++;
    byServant.set(sid, e);
  }
  for (const [sid, e] of byServant) {
    await notify({
      id: `followup_reminder_${now.dayId}_${sid}`,
      recipientId: sid,
      title: "افتقاد في انتظارك",
      message: `لديك ${e.total} افتقاد لم يتم${e.overdue ? ` (منها ${e.overdue} متأخر)` : ""}.`,
      type: "reminder",
      relatedEntityType: "suggestion",
    });
  }
}

/** Daily: conference tomorrow / conference today. */
export async function conferenceReminders(now: LocalNow): Promise<void> {
  const tomorrow = addDays(now.dayId, 1);
  const [todaySnap, tomorrowSnap] = await Promise.all([
    db.collection(C.conferences).where("dayIds", "array-contains", now.dayId).get(),
    db.collection(C.conferences).where("dayIds", "array-contains", tomorrow).get(),
  ]);
  if (todaySnap.empty && tomorrowSnap.empty) return;
  const users = await activeUsers();
  const jobs: Promise<boolean>[] = [];
  for (const c of tomorrowSnap.docs) {
    for (const u of users) {
      jobs.push(
        notify({
          id: `conference_upcoming_${c.id}_${tomorrow}_${u.id}`,
          recipientId: u.id,
          title: `غداً ${c.get("name")}`,
          message: `يبدأ يوم من أيام المؤتمر غداً ${displayDate(tomorrow)}.`,
          type: "conference",
          relatedEntityId: c.id,
          relatedEntityType: "conference",
        }),
      );
    }
  }
  for (const c of todaySnap.docs) {
    for (const u of users) {
      jobs.push(
        notify({
          id: `conference_today_${c.id}_${now.dayId}_${u.id}`,
          recipientId: u.id,
          title: `اليوم ${c.get("name")}`,
          message: "لا تنسي تسجيل حضور المؤتمر.",
          type: "conference",
          relatedEntityId: c.id,
          relatedEntityType: "conference",
        }),
      );
    }
  }
  await Promise.all(jobs);
}
