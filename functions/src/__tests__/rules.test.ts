import { test } from "node:test";
import assert from "node:assert/strict";
import {
  birthdayNotificationId,
  computeStreak,
  decide,
  ExistingSuggestion,
  isBirthdayOn,
  Mark,
} from "../shared/rules.js";
import { addDays, localNow } from "../shared/dates.js";
import { verseIndexFor } from "../verse/verseIndex.js";

const m = (id: string, s: "present" | "absent"): Mark => ({ meetingId: id, status: s });
const W = ["2026-09-02", "2026-09-09", "2026-09-16", "2026-09-23", "2026-09-30"];

test("Rule A: 2 consecutive absences => phone suggestion", () => {
  const streak = computeStreak([m(W[0], "present"), m(W[1], "absent"), m(W[2], "absent")]);
  assert.equal(streak.count, 2);
  assert.equal(streak.startMeetingId, W[1]);
  assert.deepEqual(decide(streak, []), { create: "phone", cancelIds: [] });
});

test("Rule B: 4+ consecutive absences => home visit, escalating phone", () => {
  const streak = computeStreak([m(W[0], "present"), m(W[1], "absent"), m(W[2], "absent"), m(W[3], "absent"), m(W[4], "absent")]);
  assert.equal(streak.count, 4);
  const existing: ExistingSuggestion[] = [{ id: "p1", type: "phone", status: "pending", streakStartMeetingId: W[1] }];
  assert.deepEqual(decide(streak, existing), { create: "home_visit", cancelIds: ["p1"] });
});

test("Rule C: attending resets the streak (old absences ignored)", () => {
  const streak = computeStreak([m(W[0], "absent"), m(W[1], "absent"), m(W[2], "absent"), m(W[3], "present"), m(W[4], "absent")]);
  assert.equal(streak.count, 1);
  assert.equal(decide(streak, []).create, null);
});

test("Rule C: order of input does not matter", () => {
  const streak = computeStreak([m(W[2], "absent"), m(W[0], "present"), m(W[1], "absent")]);
  assert.equal(streak.count, 2);
});

test("Rule D: no duplicate active suggestion", () => {
  const streak = computeStreak([m(W[0], "present"), m(W[1], "absent"), m(W[2], "absent"), m(W[3], "absent")]);
  const existing: ExistingSuggestion[] = [{ id: "p1", type: "phone", status: "in_progress", streakStartMeetingId: W[1] }];
  assert.equal(decide(streak, existing).create, null);
});

test("Rule E: completed suggestion is kept and not re-created for the same streak", () => {
  const streak = computeStreak([m(W[0], "present"), m(W[1], "absent"), m(W[2], "absent"), m(W[3], "absent")]);
  const existing: ExistingSuggestion[] = [{ id: "p1", type: "phone", status: "completed", streakStartMeetingId: W[1] }];
  const d = decide(streak, existing);
  assert.equal(d.create, null);
  assert.deepEqual(d.cancelIds, []); // completed history untouched
});

test("Rule E: a new streak after attending creates a new suggestion", () => {
  const streak = computeStreak([m(W[0], "absent"), m(W[1], "absent"), m(W[2], "present"), m(W[3], "absent"), m(W[4], "absent")]);
  const existing: ExistingSuggestion[] = [{ id: "p1", type: "phone", status: "completed", streakStartMeetingId: W[0] }];
  assert.equal(decide(streak, existing).create, "phone");
});

test("attending cancels only not-started suggestions", () => {
  const existing: ExistingSuggestion[] = [
    { id: "a", type: "phone", status: "pending", streakStartMeetingId: W[0] },
    { id: "b", type: "home_visit", status: "in_progress", streakStartMeetingId: W[0] },
    { id: "c", type: "phone", status: "completed", streakStartMeetingId: W[0] },
  ];
  assert.deepEqual(decide({ count: 0, startMeetingId: null }, existing), { create: null, cancelIds: ["a"] });
});

test("phone not created while a home visit is active", () => {
  const existing: ExistingSuggestion[] = [{ id: "h", type: "home_visit", status: "pending", streakStartMeetingId: W[0] }];
  assert.equal(decide({ count: 2, startMeetingId: W[3] }, existing).create, null);
});

test("Rule G: birthday id is unique per woman/recipient/year; Feb 29 handled", () => {
  assert.equal(birthdayNotificationId("w", "u", 2026), "birthday_w_u_2026");
  assert.notEqual(birthdayNotificationId("w", "u", 2026), birthdayNotificationId("w", "u", 2027));
  assert.ok(isBirthdayOn(2, 29, 2026, 2, 28));
  assert.ok(!isBirthdayOn(2, 29, 2028, 2, 28));
  assert.ok(isBirthdayOn(2, 29, 2028, 2, 29));
});

test("dates: Cairo local time and day arithmetic", () => {
  const n = localNow(new Date("2026-10-07T08:00:00Z"));
  assert.equal(n.dayId, "2026-10-07");
  assert.equal(n.weekday, 3); // Wednesday
  assert.equal(addDays("2026-12-31", 1), "2027-01-01");
});

test("verse index cycles deterministically", () => {
  assert.equal(verseIndexFor("2026-10-06", 7), verseIndexFor("2026-10-06", 7));
  assert.notEqual(verseIndexFor("2026-10-06", 7), verseIndexFor("2026-10-07", 7));
});
