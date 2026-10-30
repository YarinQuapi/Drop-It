import assert from "node:assert/strict";
import test from "node:test";
import { approximateEndHour, calorieGoal, checkPassword, daySucceeded, fastDurationMinutes, fastEndsAt, resolveBarcode, scaleNutrients, validatePassword, weightChangeKg, weightForGoal } from "./domain.js";
import { DEFAULT_USER_PERMISSIONS, OPERATIONS, resolvePermissions } from "./rbac.js";
import { changePasswordSchema, signupSchema } from "./schemas.js";
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

test("approximate fast end is the start hour plus the fasting length", () => {
  assert.equal(approximateEndHour(20, 16), 12);
  assert.equal(approximateEndHour(8, 14), 22);
  assert.equal(approximateEndHour(22, 12), 10);
});

test("a fast ends at its start plus the chosen length", () => {
  const startedAt = new Date("2026-10-09T17:14:00.000Z");
  assert.equal(fastEndsAt(startedAt, 16).toISOString(), "2026-10-10T09:14:00.000Z");
  assert.equal(fastDurationMinutes(startedAt, new Date("2026-10-10T08:19:00.000Z")), 15 * 60 + 5);
});

test("today is a calendar day", () => {
  assert.match(todayJerusalem(new Date("2026-10-04T21:00:00.000Z")), /^\d{4}-\d{2}-\d{2}$/);
});

test("password validation requires 8+ English chars, uppercase, number, symbol, and matching confirmation", () => {
  assert.equal(validatePassword("Valid1!a", "Valid1!a"), "ok");
  assert.equal(validatePassword("Short1!", "Short1!"), "weak_password");
  assert.equal(validatePassword("nouppercase1!", "nouppercase1!"), "weak_password");
  assert.equal(validatePassword("NoNumber!a", "NoNumber!a"), "weak_password");
  assert.equal(validatePassword("NoSymbol1a", "NoSymbol1a"), "weak_password");
  assert.equal(validatePassword("Has Space1!", "Has Space1!"), "weak_password");
  assert.equal(validatePassword("עבריתValid1!", "עבריתValid1!"), "weak_password");
  assert.equal(validatePassword("Valid1!a", "Different1!a"), "password_mismatch");

  const checks = checkPassword("Valid1!a", "Valid1!a");
  assert.equal(checks.valid, true);

  assert.equal(
    signupSchema.safeParse({
      email: "user@example.com",
      password: "Valid1!a",
      confirmPassword: "Valid1!a",
    }).success,
    true,
  );
  const mismatch = signupSchema.safeParse({
    email: "user@example.com",
    password: "Valid1!a",
    confirmPassword: "Valid1!b",
  });
  assert.equal(mismatch.success, false);
  if (!mismatch.success) {
    assert.equal(mismatch.error.issues[0]?.message, "password_mismatch");
  }

  assert.equal(
    changePasswordSchema.safeParse({
      currentPassword: "OldPassword1!",
      newPassword: "NewPassword1!",
      confirmPassword: "NewPassword1!",
    }).success,
    true,
  );
  assert.equal(
    changePasswordSchema.safeParse({
      currentPassword: "OldPassword1!",
      newPassword: "weak",
      confirmPassword: "weak",
    }).success,
    false,
  );
});

test("RBAC permission resolution grants all to admins and applies overrides to regular users", () => {
  assert.equal(OPERATIONS.length, 17);
  const adminPerms = resolvePermissions(true, [{ operation: "foods:create", allowed: false }]);
  for (const op of OPERATIONS) {
    assert.equal(adminPerms[op], true);
  }
  const defaultUserPerms = resolvePermissions(false, []);
  assert.deepEqual(defaultUserPerms, DEFAULT_USER_PERMISSIONS);
  assert.equal(defaultUserPerms["foods:verify"], false);
  assert.equal(defaultUserPerms["foods:create"], true);

  const overriddenUserPerms = resolvePermissions(false, [
    { operation: "foods:create", allowed: false },
    { operation: "foods:verify", allowed: true },
  ]);
  assert.equal(overriddenUserPerms["foods:create"], false);
  assert.equal(overriddenUserPerms["foods:verify"], true);
});


