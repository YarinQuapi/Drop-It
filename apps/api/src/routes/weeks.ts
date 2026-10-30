import { Router } from "express";
import { currentUser, requireUser } from "../auth.js";
import { prisma } from "../db.js";
import { daySucceeded, sumNutrients, weightChangeKg } from "../domain.js";
import { computeGoalKcal, ensureGoal } from "../goals.js";
import { asyncRoute, HttpError } from "../http.js";
import { num } from "../present.js";
import { requirePermission } from "../rbac.js";
import { compareDays, dayToUtcDate, daysOfWeek, isDayString, sundayOf, todayJerusalem, utcDateToDay, weekBounds } from "../time.js";

export const weeksRouter = Router();
weeksRouter.use(requireUser);

weeksRouter.get(
  "/",
  requirePermission("weeks:read"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const on = typeof req.query.on === "string" ? req.query.on : todayJerusalem();
    if (!isDayString(on)) throw new HttpError(400, "invalid_body");
    const profile = await prisma.profile.findUnique({ where: { userId: user.id } });
    if (!profile) throw new HttpError(409, "profile_required");
    const today = todayJerusalem();
    const sunday = sundayOf(on);
    const days = daysOfWeek(sunday);
    const bounds = weekBounds(sunday);
    const [entries, weights] = await Promise.all([
      prisma.diaryEntry.findMany({
        where: { userId: user.id, day: { gte: dayToUtcDate(sunday), lte: dayToUtcDate(days[6]) } },
      }),
      prisma.weightEntry.findMany({ where: { userId: user.id } }),
    ]);
    const dayRows = [];
    for (const day of days) {
      const future = compareDays(day, today) > 0;
      const goalKcal = future ? await computeGoalKcal(user.id, day) : await ensureGoal(user.id, day);
      if (goalKcal == null) throw new HttpError(409, "profile_required");
      const dayEntries = entries.filter((entry) => utcDateToDay(entry.day) === day);
      const totals = sumNutrients(
        dayEntries.map((entry) => ({
          calories: num(entry.calories),
          protein: num(entry.protein),
          carbohydrates: num(entry.carbohydrates),
          fat: num(entry.fat),
          fiber: num(entry.fiber),
          sugars: num(entry.sugars),
          sodium: num(entry.sodium),
        })),
      );
      const success = daySucceeded({
        entryCount: dayEntries.length,
        calories: totals.calories,
        goalKcal,
        future,
      });
      dayRows.push({ day, goalKcal, calories: totals.calories, success, future });
    }
    const change = weightChangeKg({
      weights: weights.map((entry) => ({ loggedAt: entry.loggedAt, weightKg: num(entry.weightKg) })),
      start: bounds.start,
      end: bounds.end,
    });
    res.json({
      sunday,
      calorieIntake: sumNutrients(
        dayRows.map((row) => ({
          calories: row.calories,
          protein: 0,
          carbohydrates: 0,
          fat: 0,
          fiber: 0,
          sugars: 0,
          sodium: 0,
        })),
      ).calories,
      successCount: dayRows.filter((row) => row.success).length,
      weightChangeKg: change,
      days: dayRows,
    });
  }),
);
