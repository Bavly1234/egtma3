/**
 * Egtma3 Cloud Functions (2nd gen, us-central1 — same location as Firestore nam5).
 *
 * Firestore triggers  — attendance analysis, follow-up bookkeeping, push.
 * Scheduler           — one hourly tick drives all reminders/birthdays/verse.
 * Callables           — user management, first-father bootstrap, demo data.
 */
export { onAttendanceWritten } from "./attendance/onAttendanceWritten.js";
export { onFollowUpCreated, onSuggestionWritten } from "./followups/triggers.js";
export { onWomanWritten, onStreetUpdated, onUserUpdated } from "./women/triggers.js";
export { onNotificationCreated } from "./notifications/onNotificationCreated.js";
export { hourlyTick } from "./scheduler/hourlyTick.js";
export { createServant, setUserActive, setUserRole, bootstrapFather } from "./users/callables.js";
export { seedDemoData, removeDemoData } from "./demo/demoData.js";
