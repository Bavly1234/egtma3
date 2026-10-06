import { onDocumentUpdated, onDocumentWritten } from "firebase-functions/v2/firestore";
import { C, db, FieldValue } from "../shared/admin.js";
import { ACTIVE_STATUSES } from "../shared/rules.js";

async function inChunks<T>(items: T[], size: number, fn: (chunk: T[]) => Promise<void>) {
  for (let i = 0; i < items.length; i += size) await fn(items.slice(i, i + size));
}

/**
 * Women changes: street counters, reassignment propagation to active
 * suggestions, and cancelling suggestions of deleted/deactivated women.
 */
export const onWomanWritten = onDocumentWritten("women/{id}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  const id = event.params.id;

  if (before?.streetId !== after?.streetId) {
    const batch = db.batch();
    if (before?.streetId) {
      batch.set(db.collection(C.streets).doc(before.streetId), { womenCount: FieldValue.increment(-1) }, { merge: true });
    }
    if (after?.streetId) {
      batch.set(db.collection(C.streets).doc(after.streetId), { womenCount: FieldValue.increment(1) }, { merge: true });
    }
    await batch.commit();
  }

  const reassigned = before && after && before.assignedServantId !== after.assignedServantId;
  const removed = !after || (before?.active === true && after.active === false);
  if (!reassigned && !removed) return;

  const active = await db
    .collection(C.suggestions)
    .where("womanId", "==", id)
    .where("status", "in", ACTIVE_STATUSES)
    .get();
  const batch = db.batch();
  for (const d of active.docs) {
    batch.update(
      d.ref,
      removed
        ? { status: "cancelled", cancelReason: after ? "deactivated" : "deleted", updatedAt: FieldValue.serverTimestamp() }
        : {
            assignedServantId: after!.assignedServantId ?? null,
            assignedServantName: after!.assignedServantName ?? null,
            updatedAt: FieldValue.serverTimestamp(),
          },
    );
  }
  if (reassigned && after) {
    await db.collection(C.auditLogs).add({
      action: "servant_assigned",
      actorId: "",
      actorName: "النظام",
      entityType: "woman",
      entityId: id,
      summary: `${after.fullName}: ${before?.assignedServantName ?? "—"} → ${after.assignedServantName ?? "—"}`,
      createdAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
});

/** Street rename → update the denormalised streetName on its women. */
export const onStreetUpdated = onDocumentUpdated("streets/{id}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after || before.name === after.name) return;
  const women = await db.collection(C.women).where("streetId", "==", event.params.id).get();
  await inChunks(women.docs, 400, async (chunk) => {
    const b = db.batch();
    chunk.forEach((d) => b.update(d.ref, { streetName: after.name }));
    await b.commit();
  });
});

/** Servant rename → update the denormalised name on her women. */
export const onUserUpdated = onDocumentUpdated("users/{uid}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after || before.name === after.name) return;
  const women = await db.collection(C.women).where("assignedServantId", "==", event.params.uid).get();
  await inChunks(women.docs, 400, async (chunk) => {
    const b = db.batch();
    chunk.forEach((d) => b.update(d.ref, { assignedServantName: after.name }));
    await b.commit();
  });
});
