import { onDocumentCreated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { C, db, FieldValue } from "../shared/admin.js";
import { ACTIVE_STATUSES, SuggestionType } from "../shared/rules.js";

/**
 * Keeps the woman's call/visit summary in sync with the historical
 * follow_ups records (never a blind counter: derived from each record).
 */
export const onFollowUpCreated = onDocumentCreated("follow_ups/{id}", async (event) => {
  const f = event.data?.data();
  if (!f) return;
  const womanRef = db.collection(C.women).doc(f.womanId);
  const occurredAt = f.occurredAt ?? FieldValue.serverTimestamp();
  if (f.type === "phone_call") {
    await womanRef.update({ phoneCalls: FieldValue.increment(1), lastCallAt: occurredAt }).catch(() => undefined);
  } else if (f.type === "home_visit") {
    await womanRef.update({ homeVisits: FieldValue.increment(1), lastVisitAt: occurredAt }).catch(() => undefined);
  }
});

/**
 * Maintains women.activeSuggestionType ("none" | "phone" | "home_visit") so
 * the women list can filter by follow-up status with a simple equality query.
 */
export const onSuggestionWritten = onDocumentWritten("follow_up_suggestions/{id}", async (event) => {
  const s = event.data?.after.data() ?? event.data?.before.data();
  if (!s) return;
  const active = await db
    .collection(C.suggestions)
    .where("womanId", "==", s.womanId)
    .where("status", "in", ACTIVE_STATUSES)
    .get();
  const types = new Set(active.docs.map((d) => d.get("type") as SuggestionType));
  const value = types.has("home_visit") ? "home_visit" : types.has("phone") ? "phone" : "none";
  await db.collection(C.women).doc(s.womanId).update({ activeSuggestionType: value }).catch(() => undefined);
});
