import { birthdayNotificationId } from "../shared/rules.js";

export interface BirthdayWoman {
  id: string;
  name: string;
  servantId: string | null;
}

/** Pure: who gets notified about which birthday (Rule G ids). */
export function planBirthdayNotifications(
  women: BirthdayWoman[],
  fatherIds: string[],
  notifyFathers: boolean,
  year: number,
): { id: string; recipientId: string; woman: BirthdayWoman }[] {
  const out: { id: string; recipientId: string; woman: BirthdayWoman }[] = [];
  for (const w of women) {
    const recipients = new Set<string>();
    if (w.servantId) recipients.add(w.servantId);
    if (notifyFathers || !w.servantId) fatherIds.forEach((f) => recipients.add(f));
    for (const r of recipients) out.push({ id: birthdayNotificationId(w.id, r, year), recipientId: r, woman: w });
  }
  return out;
}

