import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineBoolean } from "firebase-functions/params";
import { auth, C, db, FieldValue, Timestamp } from "../shared/admin.js";
import { requireFather } from "../shared/guards.js";
import { addDays, localNow, WEDNESDAY } from "../shared/dates.js";
import { VERSE_POOL } from "../verse/versePool.js";

/** Demo data is OFF unless explicitly enabled (functions/.env). */
const ALLOW_DEMO = defineBoolean("ALLOW_DEMO_DATA", { default: false });

const STREETS = ["شارع مار جرجس (تجريبي)", "شارع الكنيسة (تجريبي)", "شارع النصر (تجريبي)"];
const FIRST = ["مريم", "سعاد", "منى", "نادية", "ماجدة", "عايدة", "فيفيان", "إيفون", "تريزا", "هدى", "سامية", "نبيلة"];
const LAST = ["أحمد", "جرجس", "فؤاد", "حنا", "بطرس", "عزيز", "شنودة", "ميخائيل"];

const normalize = (s: string) =>
  s.trim().replace(/[أإآ]/g, "ا").replace(/ى/g, "ي").replace(/ة/g, "ه").replace(/\s+/g, " ");
const keywords = (fields: string[]) => {
  const out = new Set<string>();
  for (const f of fields) for (const w of normalize(f).split(" ")) for (let i = 2; i <= Math.min(w.length, 15); i++) out.add(w.slice(0, i));
  return [...out].sort();
};

function lastWednesdays(n: number): string[] {
  const now = localNow();
  const back = (now.weekday - WEDNESDAY + 7) % 7;
  let id = addDays(now.dayId, -back);
  const out: string[] = [];
  for (let i = 0; i < n; i++) {
    out.push(id);
    id = addDays(id, -7);
  }
  return out.reverse(); // oldest first
}

/** Seeds clearly-flagged (isDemo) data. Attendance writes trigger the real rules. */
export const seedDemoData = onCall({ timeoutSeconds: 300 }, async (req) => {
  const fatherId = await requireFather(req);
  if (!ALLOW_DEMO.value()) throw new HttpsError("failed-precondition", "البيانات التجريبية غير مفعّلة على الخادم.");

  // Verse pool (real content, not demo).
  const poolBatch = db.batch();
  VERSE_POOL.forEach((v, i) => poolBatch.set(db.collection(C.versePool).doc(`v${i}`), { ...v, order: i }));
  await poolBatch.commit();

  // Demo servants (Auth accounts with random passwords; use "إعادة تعيين الدخول" to sign in).
  const servants: { id: string; name: string }[] = [];
  for (const [i, name] of ["خادمة تجريبية 1", "خادمة تجريبية 2"].entries()) {
    const email = `demo.servant${i + 1}@egtma3-demo.invalid`;
    let uid: string;
    try {
      uid = (await auth.getUserByEmail(email)).uid;
    } catch {
      uid = (await auth.createUser({ email, displayName: name, password: crypto.randomUUID() })).uid;
    }
    await db.collection(C.users).doc(uid).set({
      name, email, phone: "", role: "servant", active: true, isDemo: true,
      notificationPrefs: {}, fcmTokens: [],
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    servants.push({ id: uid, name });
  }

  const batch = db.batch();
  for (const s of STREETS) {
    batch.set(db.collection(C.streets).doc(`s_${normalize(s).replace(/ /g, "_")}`),
      { name: s, nameNormalized: normalize(s), isDemo: true }, { merge: true });
  }
  const women: { id: string; servantId: string; streetId: string; pattern: number }[] = [];
  for (let i = 0; i < 18; i++) {
    const name = `${FIRST[i % FIRST.length]} ${LAST[(i * 3) % LAST.length]} (تجريبي)`;
    const street = STREETS[i % STREETS.length];
    const streetId = `s_${normalize(street).replace(/ /g, "_")}`;
    const servant = servants[i % servants.length];
    const phone = `0100000${String(1000 + i).slice(-4)}`;
    const now = new Date();
    const dob = new Date(Date.UTC(1950 + (i * 3) % 50, i === 0 ? now.getUTCMonth() : i % 12, i === 0 ? now.getUTCDate() : 1 + (i * 7) % 28));
    const ref = db.collection(C.women).doc();
    batch.set(ref, {
      fullName: name, nameNormalized: normalize(name), searchKeywords: keywords([name, street, phone]),
      streetId, streetName: street, address: `${10 + i} ${street}`, phone,
      dateOfBirth: Timestamp.fromDate(dob), birthMonth: dob.getUTCMonth() + 1, birthDay: dob.getUTCDate(),
      active: true, assignedServantId: servant.id, assignedServantName: servant.name, notes: "",
      consecutiveAbsences: 0, totalPresent: 0, totalAbsent: 0, phoneCalls: 0, homeVisits: 0,
      activeSuggestionType: "none", isDemo: true,
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(), createdBy: fatherId,
    });
    women.push({ id: ref.id, servantId: servant.id, streetId, pattern: i % 6 });
  }
  const confRef = db.collection(C.conferences).doc();
  const today = localNow().dayId;
  const confDays = [addDays(today, 9), addDays(today, 10), addDays(today, 12)];
  const toTs = (id: string) => Timestamp.fromDate(new Date(`${id}T00:00:00`));
  batch.set(confRef, {
    name: "مؤتمر السيدات (تجريبي)", startDate: toTs(confDays[0]), dayIds: confDays,
    days: confDays.map((d, i) => ({ id: `day${i + 1}`, index: i, date: toTs(d) })),
    createdBy: fatherId, isDemo: true, createdAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();

  // Attendance for the last 6 Wednesdays. Patterns produce: regular attendees,
  // 2-absence streaks (phone suggestion) and 4+ streaks (home visit).
  const meetings = lastWednesdays(6);
  const absent = (pattern: number, idx: number) => {
    switch (pattern) {
      case 1: return idx >= 4; // last 2 absent → phone
      case 2: return idx >= 2; // last 4 absent → home visit
      case 3: return idx % 2 === 1;
      default: return false;
    }
  };
  for (const [idx, m] of meetings.entries()) {
    const b = db.batch();
    for (const w of women) {
      b.set(db.collection(C.attendance).doc(`${m}_${w.id}`), {
        meetingId: m, womanId: w.id, servantId: w.servantId, streetId: w.streetId,
        status: absent(w.pattern, idx) ? "absent" : "present",
        markedBy: fatherId, markedAt: FieldValue.serverTimestamp(), isDemo: true,
      });
    }
    await b.commit();
  }
  return `تمت إضافة ${women.length} سيدة و ${servants.length} خادمة و ${meetings.length} اجتماعات ومؤتمر تجريبي.`;
});

/** Removes everything flagged isDemo plus records derived from demo women. */
export const removeDemoData = onCall({ timeoutSeconds: 300 }, async (req) => {
  await requireFather(req);
  let removed = 0;
  const demoWomen = await db.collection(C.women).where("isDemo", "==", true).get();
  const womanIds = demoWomen.docs.map((d) => d.id);

  const deleteQuery = async (q: FirebaseFirestore.Query) => {
    const snap = await q.get();
    for (let i = 0; i < snap.docs.length; i += 400) {
      const b = db.batch();
      snap.docs.slice(i, i + 400).forEach((d) => b.delete(d.ref));
      await b.commit();
    }
    removed += snap.size;
  };
  for (let i = 0; i < womanIds.length; i += 30) {
    const chunk = womanIds.slice(i, i + 30);
    await deleteQuery(db.collection(C.suggestions).where("womanId", "in", chunk));
    await deleteQuery(db.collection(C.followUps).where("womanId", "in", chunk));
    await deleteQuery(db.collection(C.notifications).where("relatedEntityId", "in", chunk));
    await deleteQuery(db.collection(C.conferenceAttendance).where("womanId", "in", chunk));
  }
  for (const col of [C.attendance, C.women, C.conferences, C.streets]) {
    await deleteQuery(db.collection(col).where("isDemo", "==", true));
  }
  const demoUsers = await db.collection(C.users).where("isDemo", "==", true).get();
  for (const u of demoUsers.docs) {
    await auth.deleteUser(u.id).catch(() => undefined);
    await u.ref.delete();
    removed++;
  }
  // Meeting counters may include demo marks; they are rebuilt from attendance on next writes.
  return `تم حذف ${removed} سجل تجريبي.`;
});
