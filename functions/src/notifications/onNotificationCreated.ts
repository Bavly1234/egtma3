import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { C, db, FieldValue, messaging } from "../shared/admin.js";
import { NotificationType, prefKeyFor } from "../shared/notify.js";

/**
 * Pushes every in-app notification to the recipient's devices via FCM,
 * respecting her notification preferences, and prunes dead tokens.
 */
export const onNotificationCreated = onDocumentCreated("notifications/{id}", async (event) => {
  const n = event.data?.data();
  if (!n) return;
  const user = await db.collection(C.users).doc(n.recipientId).get();
  if (!user.exists || user.get("active") !== true) return;

  const prefKey = prefKeyFor(n.type as NotificationType, event.params.id);
  const prefs = (user.get("notificationPrefs") ?? {}) as Record<string, boolean>;
  if (prefKey && prefs[prefKey] === false) return;

  const tokens: string[] = user.get("fcmTokens") ?? [];
  if (tokens.length === 0) return;

  const res = await messaging.sendEachForMulticast({
    tokens,
    notification: { title: n.title, body: n.message },
    data: {
      notificationId: event.params.id,
      type: n.type ?? "",
      relatedEntityId: n.relatedEntityId ?? "",
      relatedEntityType: n.relatedEntityType ?? "",
    },
    android: { priority: "high", notification: { channelId: "egtma3_default" } },
  });

  const dead = res.responses
    .map((r, i) => (!r.success && r.error?.code?.includes("registration-token") ? tokens[i] : null))
    .filter((t): t is string => t !== null);
  if (dead.length) {
    await user.ref.update({ fcmTokens: FieldValue.arrayRemove(...dead) });
  }
  logger.info("Push sent", { id: event.params.id, ok: res.successCount, failed: res.failureCount });
});
