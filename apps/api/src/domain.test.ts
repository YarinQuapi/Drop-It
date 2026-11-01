import assert from "node:assert/strict";
import test from "node:test";
import {
  approximateEndHour,
  calorieGoal,
  checkPassword,
  daySucceeded,
  effectiveGoalKcal,
  fastDurationMinutes,
  fastEndsAt,
  parseReminderOffsets,
  planFastNotifications,
  resolveBarcode,
  scaleNutrients,
  serializeReminderOffsets,
  summarizeWeekDays,
  usesHealthBase,
  validatePassword,
  weightChangeKg,
  weightForGoal,
} from "./domain.js";
import { DEFAULT_USER_PERMISSIONS, OPERATIONS, resolvePermissions } from "./rbac.js";
import { changePasswordSchema, fastingSchema, foodSchema, healthSettingsSchema, healthSyncSchema, profileSchema, signupSchema } from "./schemas.js";
import { addDays, ageOn, canonicalDay, firstOfMonth, jerusalemMidnight, jerusalemParts, jerusalemWallTime, sundayOf, todayJerusalem } from "./time.js";

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

test("food nutrients keep fractional grams", () => {
  const food = foodSchema.parse({
    barcode: "7290000000000",
    name: "Yogurt",
    basis: "solid",
    calories: 61,
    protein: 6.7,
    carbohydrates: 4.5,
    fat: 1.25,
    fiber: 0,
    sugars: 4.5,
    sodium: 36.2,
  });
  assert.equal(food.protein, 6.7);
  assert.equal(food.fat, 1.25);
  assert.equal(food.sodium, 36.2);
});

test("dates accept slash or dot separators and reject impossible days", () => {
  assert.equal(canonicalDay("1990-10-06"), "1990-10-06");
  assert.equal(canonicalDay("1990/10/6"), "1990-10-06");
  assert.equal(canonicalDay("1990.2.6"), "1990-02-06");
  assert.equal(canonicalDay("1990-02-31"), null);
  assert.equal(canonicalDay("06/10/1990"), null);

  const profile = profileSchema.parse({
    sex: "female",
    dateOfBirth: "1990/10/06",
    heightCm: 165.5,
    weightKg: 60.25,
    activity: "light",
    weeklyPace: "kg050",
  });
  assert.equal(profile.dateOfBirth, "1990-10-06");
  assert.equal(
    profileSchema.safeParse({
      sex: "female",
      dateOfBirth: "1990-02-31",
      heightCm: 165,
      weightKg: 60,
      activity: "light",
      weeklyPace: "kg050",
    }).success,
    false,
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

test("weekly summary counts unlogged days toward overall goalKcal but excludes them from listed days", () => {
  const summary = summarizeWeekDays([
    { day: "2026-10-25", goalKcal: 1800, calories: 1650, entryCount: 3, success: true, future: false },
    { day: "2026-10-26", goalKcal: 1800, calories: 0, entryCount: 0, success: false, future: false },
    { day: "2026-10-27", goalKcal: 1800, calories: 1900, entryCount: 4, success: false, future: false },
    { day: "2026-10-28", goalKcal: 1800, calories: 0, entryCount: 0, success: false, future: true },
  ]);
  assert.equal(summary.goalKcal, 7200);
  assert.equal(summary.calorieIntake, 3550);
  assert.equal(summary.successCount, 1);
  assert.deepEqual(summary.days.map((d) => d.day), ["2026-10-25", "2026-10-27"]);
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

test("reminder offsets serialize as a stable comma list", () => {
  assert.equal(serializeReminderOffsets([60, 0, 30, 30]), "0,30,60");
  assert.deepEqual(parseReminderOffsets("60,0"), [0, 60]);
  assert.deepEqual(parseReminderOffsets(""), []);
  assert.deepEqual(parseReminderOffsets("0"), [0]);
});

test("fasting schema defaults reminder offsets to at start", () => {
  const parsed = fastingSchema.parse({ enabled: true, lengthHours: 16, startHour: 20 });
  assert.deepEqual(parsed.reminderOffsets, [0]);
});

test("fast notifications never use the clock end hour and only emit done while running", () => {
  const now = jerusalemWallTime("2026-11-01", 12, 0);
  const planned = planFastNotifications({
    enabled: true,
    startHour: 20,
    reminderOffsets: [0],
    running: false,
    endsAt: null,
    sessionStarts: [],
    now,
    days: 1,
    wallTime: jerusalemWallTime,
    today: () => "2026-11-01",
    addDays,
  });
  assert.equal(planned.some((item) => item.kind === "done"), false);
  assert.deepEqual(
    planned.map((item) => item.kind).sort(),
    ["late", "lead"],
  );
  assert.equal(planned.find((item) => item.kind === "lead")?.at, jerusalemWallTime("2026-11-01", 20, 0).toISOString());
  assert.equal(planned.find((item) => item.kind === "late")?.at, jerusalemWallTime("2026-11-01", 20, 15).toISOString());
});

test("fast lead reminders follow the selected offsets", () => {
  const now = jerusalemWallTime("2026-11-01", 10, 0);
  const planned = planFastNotifications({
    enabled: true,
    startHour: 20,
    reminderOffsets: [60, 30, 0],
    running: false,
    endsAt: null,
    sessionStarts: [],
    now,
    days: 1,
    wallTime: jerusalemWallTime,
    today: () => "2026-11-01",
    addDays,
  });
  const leads = planned.filter((item) => item.kind === "lead");
  assert.deepEqual(
    leads.map((item) => item.leadMinutes),
    [60, 30, 0],
  );
  assert.equal(leads[0].at, jerusalemWallTime("2026-11-01", 19, 0).toISOString());
  assert.equal(leads[1].at, jerusalemWallTime("2026-11-01", 19, 30).toISOString());
  assert.equal(leads[2].at, jerusalemWallTime("2026-11-01", 20, 0).toISOString());
});

test("late nudge is skipped after the user starts the fast window", () => {
  const startedAt = jerusalemWallTime("2026-11-01", 19, 45);
  const endsAt = fastEndsAt(startedAt, 16);
  const now = jerusalemWallTime("2026-11-01", 20, 5);
  const planned = planFastNotifications({
    enabled: true,
    startHour: 20,
    reminderOffsets: [0],
    running: true,
    endsAt,
    sessionStarts: [startedAt],
    now,
    days: 1,
    wallTime: jerusalemWallTime,
    today: () => "2026-11-01",
    addDays,
  });
  assert.equal(planned.some((item) => item.kind === "late"), false);
  assert.equal(planned.some((item) => item.kind === "lead"), false);
  assert.equal(planned.some((item) => item.kind === "done"), true);
  assert.equal(planned.find((item) => item.kind === "done")?.at, endsAt.toISOString());
});

test("disabled fasting still schedules done for a running timer", () => {
  const startedAt = jerusalemWallTime("2026-11-01", 18, 0);
  const endsAt = fastEndsAt(startedAt, 16);
  const now = jerusalemWallTime("2026-11-01", 19, 0);
  const planned = planFastNotifications({
    enabled: false,
    startHour: 20,
    reminderOffsets: [0, 30],
    running: true,
    endsAt,
    sessionStarts: [startedAt],
    now,
    days: 2,
    wallTime: jerusalemWallTime,
    today: () => "2026-11-01",
    addDays,
  });
  assert.deepEqual(planned, [{ id: "done", at: endsAt.toISOString(), kind: "done", leadMinutes: null }]);
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
  assert.equal(OPERATIONS.length, 19);
  assert.equal(DEFAULT_USER_PERMISSIONS["appleHealth:read"], true);
  assert.equal(DEFAULT_USER_PERMISSIONS["appleHealth:sync"], true);
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



test("Apple Health replaces the activity multiplier from the connection day through today", () => {
  const connected = { connected: true, connectedOn: "2026-10-28", today: "2026-10-30" };
  assert.equal(usesHealthBase({ ...connected, day: "2026-10-27" }), false);
  assert.equal(usesHealthBase({ ...connected, day: "2026-10-28" }), true);
  assert.equal(usesHealthBase({ ...connected, day: "2026-10-30" }), true);
  assert.equal(usesHealthBase({ ...connected, day: "2026-10-31" }), false);
  assert.equal(usesHealthBase({ ...connected, connected: false, day: "2026-10-30" }), false);
  assert.equal(usesHealthBase({ ...connected, connectedOn: null, day: "2026-10-30" }), false);
});

test("health-adjusted goal is the sedentary base plus active kcal, never the activity level twice", () => {
  const person = { sex: "male", weightKg: 80, heightCm: 180, age: 30, pace: "kg050" } as const;
  const sedentary = calorieGoal({ ...person, activity: "sedentary" });
  const moderate = calorieGoal({ ...person, activity: "moderate" });
  assert.equal(sedentary, 1586);
  assert.equal(effectiveGoalKcal(sedentary, 420, true), 2006);
  assert.ok(effectiveGoalKcal(sedentary, 420, true) < moderate + 420);
  assert.equal(effectiveGoalKcal(sedentary, 420, false), 1586);
  assert.equal(effectiveGoalKcal(sedentary, -50, true), 1586);
  assert.equal(effectiveGoalKcal(sedentary, 99.6, true), 1686);
});

test("the 800 kcal floor applies to the sedentary base before active kcal is added", () => {
  const base = calorieGoal({ sex: "female", weightKg: 40, heightCm: 150, age: 60, activity: "sedentary", pace: "kg100" });
  assert.equal(base, 800);
  assert.equal(effectiveGoalKcal(base, 300, true), 1100);
});

test("a health-adjusted day succeeds against the effective goal", () => {
  const goalKcal = effectiveGoalKcal(1600, 400, true);
  assert.equal(daySucceeded({ entryCount: 2, calories: 1950, goalKcal, future: false }), true);
  assert.equal(daySucceeded({ entryCount: 2, calories: 2001, goalKcal, future: false }), false);
  assert.equal(daySucceeded({ entryCount: 0, calories: 0, goalKcal, future: false }), false);
});

test("weekly totals sum effective goals and carry steps and exercise on listed days", () => {
  const summary = summarizeWeekDays([
    { day: "2026-10-25", goalKcal: 2000, calories: 1900, entryCount: 3, success: true, future: false, steps: 9000, exerciseMinutes: 35, activeKcal: 400 },
    { day: "2026-10-26", goalKcal: 1700, calories: 0, entryCount: 0, success: false, future: false, steps: null, exerciseMinutes: null, activeKcal: 0 },
    { day: "2026-10-27", goalKcal: 1600, calories: 1700, entryCount: 2, success: false, future: false },
  ]);
  assert.equal(summary.goalKcal, 5300);
  assert.equal(summary.activeKcal, 400);
  assert.equal(summary.successCount, 1);
  assert.deepEqual(summary.days.map((d) => [d.day, d.steps ?? null]), [["2026-10-25", 9000], ["2026-10-27", null]]);
});

test("Apple Health sync payloads are validated and default to empty lists", () => {
  const empty = healthSyncSchema.parse({});
  assert.deepEqual(empty, { weights: [], deletedWeightIds: [], days: [] });
  const ok = healthSyncSchema.safeParse({
    weights: [{ externalId: "9B2C1E0A-5A6B-4C55-9E0A-111111111111", weightKg: 81.25, loggedAt: "2026-10-30T07:15:00.000Z" }],
    deletedWeightIds: ["9B2C1E0A-5A6B-4C55-9E0A-222222222222"],
    days: [{ day: "2026-10-30", steps: 8123, exerciseMinutes: 32, activeKcal: 410 }],
  });
  assert.equal(ok.success, true);
  assert.equal(healthSyncSchema.safeParse({ weights: [{ externalId: "x", weightKg: 0, loggedAt: "2026-10-30T07:15:00.000Z" }] }).success, false);
  assert.equal(healthSyncSchema.safeParse({ weights: [{ externalId: "x", weightKg: 80, loggedAt: "yesterday" }] }).success, false);
  assert.equal(healthSyncSchema.safeParse({ days: [{ day: "2026-10-30", steps: -1, exerciseMinutes: 0, activeKcal: 0 }] }).success, false);
  assert.equal(healthSettingsSchema.safeParse({ exerciseGoalMinutes: 30, stepGoal: 10000 }).success, true);
  assert.equal(healthSettingsSchema.safeParse({ exerciseGoalMinutes: 0, stepGoal: 10000 }).success, false);
});
