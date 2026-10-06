import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { getMessaging } from "firebase-admin/messaging";
import { setGlobalOptions } from "firebase-functions/v2";

if (getApps().length === 0) initializeApp();

// Must match the Firestore location (nam5) for 2nd-gen Firestore triggers.
export const REGION = "us-central1";
export { TIME_ZONE } from "./dates.js";

setGlobalOptions({ region: REGION, maxInstances: 10 });

export const db = getFirestore();
export const auth = getAuth();
export const messaging = getMessaging();
export { FieldValue, Timestamp };

export const C = {
  users: "users",
  women: "women",
  streets: "streets",
  meetings: "meetings",
  attendance: "attendance",
  followUps: "follow_ups",
  suggestions: "follow_up_suggestions",
  conferences: "conferences",
  conferenceAttendance: "conference_attendance",
  notifications: "notifications",
  dailyVerses: "daily_verses",
  versePool: "verse_pool",
  settings: "settings",
  auditLogs: "audit_logs",
} as const;
