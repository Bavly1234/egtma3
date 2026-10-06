import { C, db, FieldValue } from "../shared/admin.js";
import { LocalNow } from "../shared/dates.js";
import { activeUsers, notify } from "../shared/notify.js";
import { VERSE_POOL } from "./versePool.js";
import { verseIndexFor } from "./verseIndex.js";

/**
 * Publishes daily_verses/{today} from the Firestore `verse_pool` collection
 * (editable by the father in the console), falling back to the bundled pool.
 * The app reads only daily_verses, so the source can be swapped freely.
 */
export async function publishDailyVerse(now: LocalNow, settings: Record<string, unknown>): Promise<void> {
  const target = db.collection(C.dailyVerses).doc(now.dayId);
  if ((await target.get()).exists) return;

  const poolSnap = await db.collection(C.versePool).orderBy("order").get();
  const pool = poolSnap.empty
    ? VERSE_POOL
    : poolSnap.docs.map((d) => ({ text: d.get("text") as string, reference: d.get("reference") as string }));
  const v = pool[verseIndexFor(now.dayId, pool.length)];
  await target.set({ text: v.text, reference: v.reference, date: now.dayId, createdAt: FieldValue.serverTimestamp() });

  if (settings.verseNotifications === false) return;
  const users = await activeUsers();
  await Promise.all(
    users.map((u) =>
      notify({
        id: `verse_${now.dayId}_${u.id}`,
        recipientId: u.id,
        title: "📖 آية اليوم",
        message: `${v.text} (${v.reference})`,
        type: "verse",
        relatedEntityType: "verse",
      }),
    ),
  );
}
