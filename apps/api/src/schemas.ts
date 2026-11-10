import { z } from "zod";
import { validatePassword } from "./domain.js";
import { canonicalDay } from "./time.js";

export const languageSchema = z.enum(["en", "he"]);
export const sexSchema = z.enum(["male", "female"]);
export const activitySchema = z.enum(["sedentary", "light", "moderate", "very", "extra"]);
export const paceSchema = z.enum(["kg025", "kg050", "kg100"]);
export const basisSchema = z.enum(["solid", "liquid"]);
export const mealSchema = z.enum(["breakfast", "lunch", "dinner", "snacks"]);
export const daySchema = z.string().transform((value, ctx) => {
  const day = canonicalDay(value);
  if (!day) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "invalid_body" });
    return z.NEVER;
  }
  return day;
});

const nutrient = z.number().finite().min(0).max(100000);

export const nutrientsSchema = z.object({
  calories: nutrient,
  protein: nutrient,
  carbohydrates: nutrient,
  fat: nutrient,
  fiber: nutrient,
  sugars: nutrient,
  sodium: nutrient,
});

export const signupSchema = z
  .object({
    email: z.string().trim().email().max(200),
    password: z.string(),
    confirmPassword: z.string(),
    language: languageSchema.optional(),
  })
  .superRefine((data, ctx) => {
    const result = validatePassword(data.password, data.confirmPassword);
    if (result === "weak_password") {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "weak_password", path: ["password"] });
    } else if (result === "password_mismatch") {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "password_mismatch", path: ["confirmPassword"] });
    }
  });

export const loginSchema = z.object({
  email: z.string().trim().email(),
  password: z.string().min(1),
});

export const appleSignInSchema = z.object({
  identityToken: z.string().min(1).max(8000),
  nonce: z.string().min(8).max(200),
  language: languageSchema.optional(),
});

export const changePasswordSchema = z
  .object({
    currentPassword: z.string().min(1),
    newPassword: z.string(),
    confirmPassword: z.string(),
  })
  .superRefine((data, ctx) => {
    const result = validatePassword(data.newPassword, data.confirmPassword);
    if (result === "weak_password") {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "weak_password", path: ["newPassword"] });
    } else if (result === "password_mismatch") {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "password_mismatch", path: ["confirmPassword"] });
    }
  });

export const profileSchema = z.object({
  sex: sexSchema,
  dateOfBirth: daySchema,
  heightCm: z.number().gt(0).max(300),
  weightKg: z.number().gt(0).max(500),
  activity: activitySchema,
  weeklyPace: paceSchema,
  customGoalKcal: z.number().int().min(800).max(10000).nullable().optional(),
});

export const settingsSchema = z.object({
  language: languageSchema.optional(),
  autoPublishFoods: z.boolean().optional(),
});

export const foodSchema = z.object({
  // Optional: loose foods have no barcode. Blank counts as none.
  barcode: z
    .string()
    .trim()
    .max(64)
    .nullish()
    .transform((value) => (value ? value : null)),
  name: z.string().trim().min(1).max(120),
  basis: basisSchema,
}).merge(nutrientsSchema);

export const foodUpdateSchema = z.object({
  name: z.string().trim().min(1).max(120),
  basis: basisSchema,
}).merge(nutrientsSchema);

export const entrySchema = z.object({
  foodId: z.string().min(1),
  amount: z.number().gt(0).max(10000),
  meal: mealSchema,
});

export const weightSchema = z.object({
  weightKg: z.number().gt(0).max(500),
  loggedAt: z.string().datetime().optional(),
});

export const healthSettingsSchema = z.object({
  exerciseGoalMinutes: z.number().int().min(1).max(1440),
  stepGoal: z.number().int().min(100).max(200000),
});

export const healthSyncSchema = z.object({
  weights: z
    .array(
      z.object({
        externalId: z.string().min(1).max(64),
        weightKg: z.number().gt(0).max(500),
        loggedAt: z.string().datetime({ offset: true }),
      }),
    )
    .max(1000)
    .default([]),
  deletedWeightIds: z.array(z.string().min(1).max(64)).max(1000).default([]),
  days: z
    .array(
      z.object({
        day: daySchema,
        steps: z.number().min(0).max(1000000),
        exerciseMinutes: z.number().min(0).max(1440),
        activeKcal: z.number().min(0).max(20000),
      }),
    )
    .max(60)
    .default([]),
});

export const fastingSchema = z.object({
  enabled: z.boolean(),
  lengthHours: z.union([z.literal(12), z.literal(14), z.literal(16)]),
  startHour: z.number().int().min(0).max(23),
  reminderOffsets: z
    .array(z.union([z.literal(0), z.literal(30), z.literal(60)]))
    .max(3)
    .default([0]),
});

export const catalogQuerySchema = z.object({
  scope: z.enum(["published", "mine"]).default("published"),
  status: z.enum(["all", "verified", "unverified"]).default("all"),
  q: z.string().trim().max(64).default(""),
  offset: z.coerce.number().int().min(0).max(100000).default(0),
});
