import { Router } from "express";
import { currentUser, requireUser } from "../auth.js";
import { prisma } from "../db.js";
import { daySucceeded, dayStatus, summarizeWeekDays, sumNutrients, weightChangeKg } from "../domain.js";
import { loadHealthSettings, resolveGoal } from "../goals.js";
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
    const [entries, weights, healthDays, settings] = await Promise.all([
      prisma.diaryEntry.findMany({
        where: { userId: user.id, day: { gte: dayToUtcDate(sunday), lte: dayToUtcDate(days[6]) } },
      }),
      prisma.weightEntry.findMany({ where: { userId: user.id } }),
      prisma.healthDay.findMany({
        where: { userId: user.id, day: { gte: dayToUtcDate(sunday), lte: dayToUtcDate(days[6]) } },
      }),
      loadHealthSettings(user.id),
    ]);
    const dayRows = [];
    for (const day of days) {
      const future = compareDays(day, today) > 0;
      const healthDay = healthDays.find((row) => utcDateToDay(row.day) === day) ?? null;
      const goal = await resolveGoal(user.id, day, { future, settings, healthDay });
      if (!goal) throw new HttpError(409, "profile_required");
      const { goalKcal } = goal;
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
      const statusInput = { entryCount: dayEntries.length, calories: totals.calories, goalKcal, future, today: day === today };
      const success = daySucceeded(statusInput);
      const status = dayStatus(statusInput);
      dayRows.push({
        day,
        goalKcal,
        calories: totals.calories,
        entryCount: dayEntries.length,
        success,
        status,
        future,
        steps: healthDay ? healthDay.steps : null,
        exerciseMinutes: healthDay ? healthDay.exerciseMinutes : null,
        activeKcal: goal.activeKcal,
      });
    }
    const change = weightChangeKg({
      weights: weights.map((entry) => ({ loggedAt: entry.loggedAt, weightKg: num(entry.weightKg) })),
      start: bounds.start,
      end: bounds.end,
    });
    const summary = summarizeWeekDays(dayRows);
    res.json({
      sunday,
      goalKcal: summary.goalKcal,
      activeKcal: summary.activeKcal,
      healthSynced: settings.lastSyncedAt != null,
      stepGoal: settings.stepGoal,
      exerciseGoalMinutes: settings.exerciseGoalMinutes,
      calorieIntake: summary.calorieIntake,
      successCount: summary.successCount,
      weightChangeKg: change,
      days: summary.days,
    });
  }),
);
