import { Router } from "express";
import { currentUser, requireUser } from "../auth.js";
import { prisma } from "../db.js";
import { daySucceeded, scaleNutrients, sumNutrients, type Nutrients } from "../domain.js";
import { closeRunningFast } from "../fasting-log.js";
import { resolveGoal } from "../goals.js";
import { asyncRoute, HttpError } from "../http.js";
import { num } from "../present.js";
import { requirePermission } from "../rbac.js";
import { entrySchema } from "../schemas.js";
import { compareDays, dayToUtcDate, isDayString, todayJerusalem } from "../time.js";

export const daysRouter = Router();
daysRouter.use(requireUser);

daysRouter.get(
  "/:day",
  requirePermission("days:read"),
  asyncRoute(async (req, res) => {
    const day = resolveDay(req.params.day);
    const user = currentUser(res);
    const today = todayJerusalem();
    const future = compareDays(day, today) > 0;
    const goal = await resolveGoal(user.id, day, { future });
    if (!goal) throw new HttpError(409, "profile_required");
    const { goalKcal } = goal;
    const entries = await prisma.diaryEntry.findMany({
      where: { userId: user.id, day: dayToUtcDate(day) },
      orderBy: { createdAt: "asc" },
    });
    const nutrients = sumNutrients(entries.map(entryNutrients));
    res.json({
      day,
      ...goal,
      entries: entries.map(presentEntry),
      totals: nutrients,
      success: daySucceeded({
        entryCount: entries.length,
        calories: nutrients.calories,
        goalKcal,
        future,
      }),
      future,
    });
  }),
);

daysRouter.post(
  "/:day/entries",
  requirePermission("entries:create"),
  asyncRoute(async (req, res) => {
    const day = resolveDay(req.params.day);
    const user = currentUser(res);
    const today = todayJerusalem();
    if (compareDays(day, today) > 0) throw new HttpError(400, "future_day");
    const body = entrySchema.parse(req.body);
    const food = await prisma.food.findUnique({ where: { id: body.foodId } });
    if (!food) throw new HttpError(404, "not_found");
    if (food.ownerId !== user.id && !food.published) throw new HttpError(403, "forbidden");
    const goal = await resolveGoal(user.id, day, { future: false });
    if (!goal) throw new HttpError(409, "profile_required");
    const scaled = scaleNutrients(
      {
        calories: num(food.calories),
        protein: num(food.protein),
        carbohydrates: num(food.carbohydrates),
        fat: num(food.fat),
        fiber: num(food.fiber),
        sugars: num(food.sugars),
        sodium: num(food.sodium),
      },
      body.amount,
    );
    const entry = await prisma.$transaction(async (tx) => {
      const created = await tx.diaryEntry.create({
        data: {
          userId: user.id,
          day: dayToUtcDate(day),
          foodId: food.id,
          name: food.name,
          basis: food.basis,
          amount: body.amount,
          meal: body.meal,
          ...scaled,
        },
      });
      await closeRunningFast(tx, user.id);
      return created;
    });
    res.status(201).json({ entry: presentEntry(entry), goalKcal: goal.goalKcal });
  }),
);

daysRouter.delete(
  "/:day/entries/:id",
  requirePermission("entries:delete"),
  asyncRoute(async (req, res) => {
    const day = resolveDay(req.params.day);
    const user = currentUser(res);
    const entry = await prisma.diaryEntry.findFirst({
      where: { id: req.params.id, userId: user.id, day: dayToUtcDate(day) },
    });
    if (!entry) throw new HttpError(404, "not_found");
    await prisma.diaryEntry.delete({ where: { id: entry.id } });
    res.json({ ok: true });
  }),
);

function resolveDay(param: string): string {
  if (param === "today") return todayJerusalem();
  if (!isDayString(param)) throw new HttpError(400, "invalid_body");
  return param;
}

function entryNutrients(entry: {
  calories: { toNumber(): number };
  protein: { toNumber(): number };
  carbohydrates: { toNumber(): number };
  fat: { toNumber(): number };
  fiber: { toNumber(): number };
  sugars: { toNumber(): number };
  sodium: { toNumber(): number };
}): Nutrients {
  return {
    calories: num(entry.calories),
    protein: num(entry.protein),
    carbohydrates: num(entry.carbohydrates),
    fat: num(entry.fat),
    fiber: num(entry.fiber),
    sugars: num(entry.sugars),
    sodium: num(entry.sodium),
  };
}

function presentEntry(entry: {
  id: string;
  foodId: string | null;
  name: string;
  basis: "solid" | "liquid";
  meal: "breakfast" | "lunch" | "dinner" | "snacks";
  amount: { toNumber(): number };
  calories: { toNumber(): number };
  protein: { toNumber(): number };
  carbohydrates: { toNumber(): number };
  fat: { toNumber(): number };
  fiber: { toNumber(): number };
  sugars: { toNumber(): number };
  sodium: { toNumber(): number };
}) {
  return {
    id: entry.id,
    foodId: entry.foodId,
    name: entry.name,
    basis: entry.basis,
    meal: entry.meal,
    amount: num(entry.amount),
    ...entryNutrients(entry),
  };
}
