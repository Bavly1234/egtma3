import { test } from "node:test";
import assert from "node:assert/strict";
import { planBirthdayNotifications } from "../birthdays/birthdayPlan.js";
import { jobsFor } from "../scheduler/jobs.js";
import { LocalNow } from "../shared/dates.js";

test("birthday: servant + fathers notified once each", () => {
  const plan = planBirthdayNotifications([{ id: "w1", name: "مريم", servantId: "s1" }], ["f1"], true, 2026);
  assert.deepEqual(plan.map((p) => p.recipientId).sort(), ["f1", "s1"]);
  assert.equal(new Set(plan.map((p) => p.id)).size, plan.length);
});

test("birthday: father not notified when disabled, unless unassigned", () => {
  assert.deepEqual(planBirthdayNotifications([{ id: "w1", name: "x", servantId: "s1" }], ["f1"], false, 2026).map((p) => p.recipientId), ["s1"]);
  assert.deepEqual(planBirthdayNotifications([{ id: "w2", name: "x", servantId: null }], ["f1"], false, 2026).map((p) => p.recipientId), ["f1"]);
});

const at = (weekday: number, hour: number): LocalNow => ({ year: 2026, month: 10, day: 6, hour, weekday, dayId: "2026-10-06" });

test("scheduler: Tuesday meeting reminder at configured hour", () => {
  assert.ok(jobsFor(at(2, 18), {}).includes("meeting"));
  assert.ok(!jobsFor(at(2, 18), { meetingReminderHour: 19 }).includes("meeting"));
  assert.ok(!jobsFor(at(4, 18), {}).includes("meeting"));
});

test("scheduler: Wednesday attendance reminder and daily jobs", () => {
  assert.ok(jobsFor(at(3, 21), {}).includes("attendance"));
  assert.deepEqual(jobsFor(at(5, 6), {}), ["verse"]);
  assert.ok(jobsFor(at(1, 8), {}).includes("birthdays"));
});
