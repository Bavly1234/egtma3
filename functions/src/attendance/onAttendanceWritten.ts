import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { logger } from "firebase-functions";
import { C, db, FieldValue } from "../shared/admin.js";
import {
  computeStreak,
  decide,
  ExistingSuggestion,
  Mark,
  suggestionReason,
  SuggestionStatus,
  SuggestionType,
} from "../shared/rules.js";
import { notify } from "../shared/notify.js";

type Status = "present" | "absent" | undefined;

/** +1/-1 counter deltas for one attendance change. */
function deltas(before: Status, after: Status) {
  const d = { present: 0, absent: 0 };
  if (before) d[before] -= 1;
  if (after) d[after] += 1;
  return d;
}

/**
 * Runs on every attendance create/update/delete:
 *  1. maintains meetings/{date} counters (total, by street, by servant)
 *  2. recomputes the woman's consecutive-absence streak and totals
 *  3. creates / cancels follow-up suggestions (transactional, no duplicates)
 *  4. notifies the responsible servant (and the father for home visits)
 *  5. audits status changes of an existing record
 */
export const onAttendanceWritten = onDocumentWritten("attendance/{id}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  const ref = after ?? before;
  if (!ref) return;
  const meetingId: string = ref.meetingId;
  const womanId: string = ref.womanId;
  const bStatus = before?.status as Status;
  const aStatus = after?.status as Status;

  // 1. Meeting counters: one merge write with the net delta per key.
  //    (Triggers are at-least-once; counters are an optimisation for
  //    dashboards. Streaks below are recomputed from source data, so they
  //    are always exact.)
  if (bStatus !== aStatus || before?.streetId !== after?.streetId || before?.servantId !== after?.servantId) {
    const top: Record<string, number> = {};
    const byStreet: Record<string, Record<string, number>> = {};
    const byServant: Record<string, Record<string, number>> = {};
    const add = (status: Status, sign: number, streetId?: string, servantId?: string) => {
      if (!status) return;
      top[status] = (top[status] ?? 0) + sign;
      const st = (byStreet[streetId || "unknown"] ??= {});
      st[status] = (st[status] ?? 0) + sign;
      const sv = (byServant[servantId || "unassigned"] ??= {});
      sv[status] = (sv[status] ?? 0) + sign;
    };
    add(bStatus, -1, before?.streetId, before?.servantId);
    add(aStatus, 1, after?.streetId, after?.servantId);
    const incs = (o: Record<string, number>) =>
      Object.fromEntries(Object.entries(o).filter(([, v]) => v !== 0).map(([k, v]) => [k, FieldValue.increment(v)]));
    const nested = (o: Record<string, Record<string, number>>) =>
      Object.fromEntries(Object.entries(o).map(([k, v]) => [k, incs(v)]));
    await db.collection(C.meetings).doc(meetingId).set(
      { ...incs(top), byStreet: nested(byStreet), byServant: nested(byServant), updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  }

  // 5. Audit changes to an already-recorded status.
  if (before && after && bStatus !== aStatus) {
    await db.collection(C.auditLogs).add({
      action: "attendance_changed",
      actorId: after.markedBy ?? "",
      actorName: "",
      entityType: "attendance",
      entityId: event.params.id,
      summary: `${meetingId}: ${bStatus} → ${aStatus}`,
      createdAt: FieldValue.serverTimestamp(),
    });
  }

  // 2 + 3 in a transaction on the woman document.
  const created = await db.runTransaction(async (tx) => {
    const womanRef = db.collection(C.women).doc(womanId);
    const woman = await tx.get(womanRef);
    if (!woman.exists) return null;

    const marksSnap = await tx.get(
      db.collection(C.attendance).where("womanId", "==", womanId).orderBy("meetingId", "desc").limit(30),
    );
    const marks: Mark[] = marksSnap.docs
      .map((d) => ({ meetingId: d.get("meetingId"), status: d.get("status") }))
      .filter((m) => m.status === "present" || m.status === "absent");
    const streak = computeStreak(marks);

    const sugSnap = await tx.get(
      db.collection(C.suggestions).where("womanId", "==", womanId).orderBy("createdAt", "desc").limit(50),
    );
    const existing: ExistingSuggestion[] = sugSnap.docs.map((d) => ({
      id: d.id,
      type: d.get("type") as SuggestionType,
      status: d.get("status") as SuggestionStatus,
      streakStartMeetingId: d.get("streakStartMeetingId") ?? null,
    }));
    const decision = decide(streak, existing);

    for (const id of decision.cancelIds) {
      tx.update(db.collection(C.suggestions).doc(id), {
        status: "cancelled",
        cancelReason: streak.count === 0 ? "attended" : "escalated",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    let newSuggestion: { id: string; type: SuggestionType } | null = null;
    if (decision.create) {
      const sRef = db.collection(C.suggestions).doc();
      tx.create(sRef, {
        womanId,
        womanName: woman.get("fullName") ?? "",
        type: decision.create,
        status: "pending",
        consecutiveAbsences: streak.count,
        streakStartMeetingId: streak.startMeetingId,
        reason: suggestionReason(decision.create, streak.count),
        assignedServantId: woman.get("assignedServantId") ?? null,
        assignedServantName: woman.get("assignedServantName") ?? null,
        streetId: woman.get("streetId") ?? null,
        streetName: woman.get("streetName") ?? null,
        phone: woman.get("phone") ?? null,
        address: woman.get("address") ?? null,
        isDemo: woman.get("isDemo") === true,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      newSuggestion = { id: sRef.id, type: decision.create };
    }

    // Recompute totals from source of truth (cheap: bounded by limit) plus delta.
    const d = deltas(bStatus, aStatus);
    const latest = marks[0];
    tx.update(womanRef, {
      consecutiveAbsences: streak.count,
      lastAttendanceDate: latest?.meetingId ?? null,
      totalPresent: FieldValue.increment(d.present),
      totalAbsent: FieldValue.increment(d.absent),
    });

    return newSuggestion
      ? {
          ...newSuggestion,
          womanName: woman.get("fullName") as string,
          servantId: woman.get("assignedServantId") as string | null,
          count: streak.count,
        }
      : null;
  });

  // 4. Notify outside the transaction.
  if (created) {
    const isHome = created.type === "home_visit";
    const title = isHome ? "🏠 افتقاد منزلي مطلوب" : "📞 افتقاد تليفوني مطلوب";
    const message = `السيدة ${created.womanName} — ${suggestionReason(created.type, created.count)}`;
    const recipients = new Set<string>();
    if (created.servantId) recipients.add(created.servantId);
    if (isHome || !created.servantId) {
      const fathers = await db.collection(C.users).where("role", "==", "father").where("active", "==", true).get();
      fathers.docs.forEach((f) => recipients.add(f.id));
    }
    await Promise.all(
      [...recipients].map((uid) =>
        notify({
          id: `suggestion_${created.id}_${uid}`,
          recipientId: uid,
          title,
          message,
          type: "follow_up",
          relatedEntityId: womanId,
          relatedEntityType: "woman",
        }),
      ),
    );
    logger.info("Suggestion created", { suggestionId: created.id, type: created.type });
  }
});
