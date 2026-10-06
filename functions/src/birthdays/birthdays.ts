import { C, db } from "../shared/admin.js";
import { LocalNow } from "../shared/dates.js";
import { activeUsers, notify } from "../shared/notify.js";
import { isBirthdayOn } from "../shared/rules.js";
import { BirthdayWoman, planBirthdayNotifications } from "./birthdayPlan.js";

/** Runs once a day (morning). Deterministic ids make reruns harmless. */
export async function runBirthdays(now: LocalNow, settings: Record<string, unknown>): Promise<number> {
  // Feb 28 in non-leap years must also include Feb 29 birthdays.
  const days = [now.day];
  if (now.month === 2 && now.day === 28 && !isBirthdayOn(2, 29, now.year, 2, 29)) days.push(29);
  const snaps = await Promise.all(
    days.map((d) =>
      db.collection(C.women).where("active", "==", true).where("birthMonth", "==", now.month).where("birthDay", "==", d).get(),
    ),
  );
  const women: BirthdayWoman[] = snaps
    .flatMap((s) => s.docs)
    .map((d) => ({ id: d.id, name: d.get("fullName"), servantId: d.get("assignedServantId") ?? null }));
  if (women.length === 0) return 0;
  const fathers = (await activeUsers("father")).map((u) => u.id);
  const plan = planBirthdayNotifications(women, fathers, settings.notifyFatherBirthdays !== false, now.year);
  let sent = 0;
  for (const p of plan) {
    const created = await notify({
      id: p.id,
      recipientId: p.recipientId,
      title: `🎂 اليوم عيد ميلاد السيدة ${p.woman.name}`,
      message: "لا تنسي تهنئتها اليوم.",
      type: "birthday",
      relatedEntityId: p.woman.id,
      relatedEntityType: "woman",
    });
    if (created) sent++;
  }
  return sent;
}
