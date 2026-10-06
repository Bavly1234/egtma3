import { HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { C, db } from "./admin.js";

/** Throws unless the caller is an active father. Never trust the client. */
export async function requireFather(req: CallableRequest<unknown>): Promise<string> {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "يجب تسجيل الدخول أولاً.");
  const u = await db.collection(C.users).doc(uid).get();
  if (!u.exists || u.get("role") !== "father" || u.get("active") !== true) {
    throw new HttpsError("permission-denied", "ليس لديك صلاحية لهذا الإجراء.");
  }
  return uid;
}

export function str(v: unknown, field: string, { min = 1, max = 200 } = {}): string {
  if (typeof v !== "string") throw new HttpsError("invalid-argument", `${field} مطلوب`);
  const s = v.trim();
  if (s.length < min || s.length > max) throw new HttpsError("invalid-argument", `${field} غير صحيح`);
  return s;
}
