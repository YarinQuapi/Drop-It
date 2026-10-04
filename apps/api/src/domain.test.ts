import assert from "node:assert/strict";
import test from "node:test";
import { calorieGoal, daySucceeded, resolveBarcode, scaleNutrients, weightChangeKg, weightForGoal } from "./domain.js";
import { addDays, ageOn, firstOfMonth, jerusalemMidnight, jerusalemParts, sundayOf, todayJerusalem } from "./time.js";

test("mifflin goal uses activity, deficit, floor, then nearest kcal", () => {
  assert.equal(
    calorieGoal({
      sex: "male",
      weightKg: 80,
      heightCm: 180,
      age: 30,
      activity: "sedentary",
      pace: "kg050",
    }),
    1586,
  );

  assert.equal(
    calorieGoal({
      sex: "female",
      weightKg: 70,
      heightCm: 165,
      age: 40,
      activity: "moderate",
      pace: "kg100",
    }),
    1024,
  );

  assert.equal(
    calorieGoal({
      sex: "female",
      weightKg: 40,
      heightCm: 150,
      age: 60,
      activity: "extra",
      pace: "kg100",
    }),
    800,
  );
});

test("age uses the completed year on the Jerusalem calendar day", () => {
  assert.equal(ageOn("1990-10-06", "2026-10-05"), 35);
  assert.equal(ageOn("1990-10-06", "2026-10-06"), 36);
});

test("weeks start on Sunday", () => {
  assert.equal(sundayOf("2026-10-05"), "2026-10-04");
  assert.equal(sundayOf("2026-10-04"), "2026-10-04");
  assert.equal(addDays("2026-10-04", 6), "2026-10-10");
  assert.equal(firstOfMonth("2026-10-05"), "2026-10-01");
});

test("Jerusalem midnight lands on that calendar day", () => {
  const midnight = jerusalemMidnight("2026-10-05");
  const parts = jerusalemParts(midnight);
  assert.equal(parts.year, 2026);
  assert.equal(parts.month, 10);
  assert.equal(parts.day, 5);
  assert.equal(parts.hour, 0);
  assert.equal(parts.minute, 0);
  assert.equal(parts.second, 0);
});

test("monthly weight uses the latest weigh-in before the 1st", () => {
  const jerusalemDay = (date: Date) => date.toISOString().slice(0, 10);
  assert.equal(
    weightForGoal({
      day: "2026-10-15",
      profileWeightKg: 80,
      weighIns: [
        { loggedAt: new Date("2026-09-20T10:00:00.000Z"), weightKg: 82 },
        { loggedAt: new Date("2026-10-02T10:00:00.000Z"), weightKg: 79 },
      ],
      jerusalemDay,
      firstOfMonth,
    }),
    82,
  );
  assert.equal(
    weightForGoal({
      day: "2026-10-15",
      profileWeightKg: 80,
      weighIns: [{ loggedAt: new Date("2026-10-02T10:00:00.000Z"), weightKg: 79 }],
      jerusalemDay,
      firstOfMonth,
    }),
    80,
  );
});

test("nutrients scale from the per-100 amount", () => {
  assert.deepEqual(
    scaleNutrients(
      { calories: 250, protein: 10, carbohydrates: 20, fat: 5, fiber: 2, sugars: 4, sodium: 100 },
      150,
    ),
    { calories: 375, protein: 15, carbohydrates: 30, fat: 7.5, fiber: 3, sugars: 6, sodium: 150 },
  );
});

test("a day succeeds only when food was logged and calories are at or under the goal", () => {
  assert.equal(daySucceeded({ entryCount: 0, calories: 0, goalKcal: 1800, future: false }), false);
  assert.equal(daySucceeded({ entryCount: 1, calories: 1800, goalKcal: 1800, future: false }), true);
  assert.equal(daySucceeded({ entryCount: 1, calories: 1801, goalKcal: 1800, future: false }), false);
  assert.equal(daySucceeded({ entryCount: 1, calories: 100, goalKcal: 1800, future: true }), false);
});

test("barcode lookup prefers the user's own food, then the verified food, then the list", () => {
  assert.equal(resolveBarcode({ own: { id: "me" }, verified: { id: "v" }, published: [{ id: "p" }] }).status, "personal");
  assert.equal(resolveBarcode({ own: null, verified: { id: "v" }, published: [{ id: "p" }] }).status, "verified");
  assert.equal(resolveBarcode({ own: null, verified: null, published: [{ id: "p" }] }).status, "list");
  assert.equal(resolveBarcode({ own: null, verified: null, published: [] }).status, "none");
});

test("weekly weight change uses the latest in the week and the latest before it", () => {
  const start = new Date("2026-10-04T00:00:00.000Z");
  const end = new Date("2026-10-11T00:00:00.000Z");
  assert.equal(
    weightChangeKg({
      start,
      end,
      weights: [
        { loggedAt: new Date("2026-09-30T00:00:00.000Z"), weightKg: 80 },
        { loggedAt: new Date("2026-10-01T00:00:00.000Z"), weightKg: 81 },
        { loggedAt: new Date("2026-10-05T00:00:00.000Z"), weightKg: 79 },
        { loggedAt: new Date("2026-10-06T00:00:00.000Z"), weightKg: 78.5 },
      ],
    }),
    -2.5,
  );
  assert.equal(
    weightChangeKg({
      start,
      end,
      weights: [{ loggedAt: new Date("2026-10-05T00:00:00.000Z"), weightKg: 79 }],
    }),
    null,
  );
});

test("today is a calendar day", () => {
  assert.match(todayJerusalem(new Date("2026-10-04T21:00:00.000Z")), /^\d{4}-\d{2}-\d{2}$/);
});
