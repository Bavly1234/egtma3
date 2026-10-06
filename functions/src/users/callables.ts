import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineString } from "firebase-functions/params";
import { randomBytes, timingSafeEqual } from "node:crypto";
import { auth, C, db, FieldValue } from "../shared/admin.js";
import { requireFather, str } from "../shared/guards.js";

/** One-time setup code (functions/.env, never committed). */
const BOOTSTRAP_CODE = defineString("BOOTSTRAP_CODE", { default: "" });

const DEFAULT_PREFS = {
  meetingReminder: true,
  attendanceReminder: true,
  followUp: true,
  birthday: true,
  conference: true,
  dailyVerse: true,
};

async function audit(actorId: string, action: string, entityId: string, summary: string) {
  const actor = await db.collection(C.users).doc(actorId).get();
  await db.collection(C.auditLogs).add({
    action,
    actorId,
    actorName: actor.get("name") ?? "",
    entityType: "user",
    entityId,
    summary,
    createdAt: FieldValue.serverTimestamp(),
  });
}

/** Father creates a servant account with a random password; the app then sends a reset email. */
export const createServant = onCall(async (req) => {
  const fatherId = await requireFather(req);
  const data = (req.data ?? {}) as Record<string, unknown>;
  const name = str(data.name, "الاسم", { min: 3 });
  const email = str(data.email, "البريد الإلكتروني", { min: 5 }).toLowerCase();
  const phone = typeof data.phone === "string" ? data.phone.trim().slice(0, 20) : "";
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new HttpsError("invalid-argument", "البريد الإلكتروني غير صحيح");

  let uid: string;
  try {
    const u = await auth.createUser({ email, displayName: name, password: randomBytes(24).toString("base64url") });
    uid = u.uid;
  } catch (e: unknown) {
    if ((e as { code?: string }).code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "هذا البريد مستخدم بالفعل.");
    }
    throw e;
  }
  await db.collection(C.users).doc(uid).set({
    name,
    email,
    phone,
    role: "servant",
    active: true,
    notificationPrefs: DEFAULT_PREFS,
    fcmTokens: [],
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await audit(fatherId, "user_changed", uid, `إضافة خادمة: ${name}`);
  return { uid };
});

export const setUserActive = onCall(async (req) => {
  const fatherId = await requireFather(req);
  const { uid, active } = (req.data ?? {}) as { uid?: string; active?: boolean };
  if (typeof uid !== "string" || typeof active !== "boolean") throw new HttpsError("invalid-argument", "بيانات غير صحيحة");
  if (uid === fatherId) throw new HttpsError("failed-precondition", "لا يمكنك إيقاف حسابك.");
  await auth.updateUser(uid, { disabled: !active });
  if (!active) await auth.revokeRefreshTokens(uid);
  await db.collection(C.users).doc(uid).update({ active, updatedAt: FieldValue.serverTimestamp() });
  await audit(fatherId, "user_changed", uid, active ? "تفعيل حساب" : "إيقاف حساب");
  return { ok: true };
});

export const setUserRole = onCall(async (req) => {
  const fatherId = await requireFather(req);
  const { uid, role } = (req.data ?? {}) as { uid?: string; role?: string };
  if (typeof uid !== "string" || (role !== "father" && role !== "servant")) {
    throw new HttpsError("invalid-argument", "بيانات غير صحيحة");
  }
  if (uid === fatherId && role !== "father") throw new HttpsError("failed-precondition", "لا يمكنك إزالة صلاحيتك.");
  await db.collection(C.users).doc(uid).update({ role, updatedAt: FieldValue.serverTimestamp() });
  await audit(fatherId, "user_changed", uid, `تغيير الصلاحية إلى ${role === "father" ? "الأب الكاهن" : "خادمة"}`);
  return { ok: true };
});

/**
 * Promotes the signed-in caller to the first father. Requires BOOTSTRAP_CODE
 * and only works while no father exists (transactional check).
 */
export const bootstrapFather = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً.");
  const expected = BOOTSTRAP_CODE.value();
  const given = String((req.data as { code?: unknown })?.code ?? "");
  const ok =
    expected.length >= 8 &&
    given.length === expected.length &&
    timingSafeEqual(Buffer.from(given), Buffer.from(expected));
  if (!ok) throw new HttpsError("permission-denied", "رمز الإعداد غير صحيح.");
  const name = str((req.data as { name?: unknown })?.name, "الاسم", { min: 3 });
  const email = req.auth?.token.email ?? "";

  await db.runTransaction(async (tx) => {
    const fathers = await tx.get(db.collection(C.users).where("role", "==", "father").limit(1));
    if (!fathers.empty) throw new HttpsError("failed-precondition", "تم إعداد حساب الأب الكاهن بالفعل.");
    tx.set(db.collection(C.users).doc(uid), {
      name,
      email,
      phone: "",
      role: "father",
      active: true,
      notificationPrefs: DEFAULT_PREFS,
      fcmTokens: [],
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  await audit(uid, "user_changed", uid, "إعداد حساب الأب الكاهن");
  return { ok: true };
});
