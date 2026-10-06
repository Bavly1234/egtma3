import { logger } from "firebase-functions";
import { C, db, FieldValue } from "./admin.js";

export type NotificationType =
  | "attendance"
  | "follow_up"
  | "birthday"
  | "conference"
  | "system"
  | "reminder"
  | "verse";

export interface NotificationInput {
  /** Deterministic id => Firestore rejects duplicates (idempotent retries). */
  id: string;
  recipientId: string;
  title: string;
  message: string;
  type: NotificationType;
  relatedEntityId?: string | null;
  relatedEntityType?: "woman" | "suggestion" | "conference" | "meeting" | "verse" | null;
}

/**
 * Creates the in-app notification once. The FCM push is sent by the
 * `onNotificationCreated` trigger, so creating = notifying everywhere.
 * Returns false when it already existed (duplicate avoided).
 */
export async function notify(n: NotificationInput): Promise<boolean> {
  try {
    await db.collection(C.notifications).doc(n.id).create({
      recipientId: n.recipientId,
      title: n.title,
      message: n.message,
      type: n.type,
      relatedEntityId: n.relatedEntityId ?? null,
      relatedEntityType: n.relatedEntityType ?? null,
      createdAt: FieldValue.serverTimestamp(),
      readAt: null,
    });
    return true;
  } catch (e: unknown) {
    if ((e as { code?: number }).code === 6) return false; // ALREADY_EXISTS
    logger.error("notify failed", { id: n.id, error: String(e) });
    throw e;
  }
}

export interface UserLite {
  id: string;
  name: string;
  role: "father" | "servant";
}

export async function activeUsers(role?: "father" | "servant"): Promise<UserLite[]> {
  let q = db.collection(C.users).where("active", "==", true);
  if (role) q = q.where("role", "==", role);
  const snap = await q.get();
  return snap.docs.map((d) => ({ id: d.id, name: d.get("name") ?? "", role: d.get("role") }));
}

export async function appSettings(): Promise<Record<string, unknown>> {
  const s = await db.collection(C.settings).doc("app").get();
  return s.data() ?? {};
}

/** Maps a notification type to the user preference that gates the push. */
export function prefKeyFor(type: NotificationType, id: string): string | null {
  switch (type) {
    case "reminder":
      return id.startsWith("followup_reminder") ? "followUp" : "meetingReminder";
    case "attendance":
      return "attendanceReminder";
    case "follow_up":
      return "followUp";
    case "birthday":
      return "birthday";
    case "conference":
      return "conference";
    case "verse":
      return "dailyVerse";
    default:
      return null;
  }
}
