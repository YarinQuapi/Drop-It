import { Router } from "express";
import { currentUser, requireUser } from "../auth.js";
import { prisma } from "../db.js";
import { asyncRoute, HttpError } from "../http.js";
import { fastingSchema } from "../schemas.js";

export const fastingRouter = Router();
fastingRouter.use(requireUser);

fastingRouter.get(
  "/",
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    const [settings, timer] = await Promise.all([
      prisma.fastingSettings.findUnique({ where: { userId: user.id } }),
      prisma.fastingTimer.findUnique({ where: { userId: user.id } }),
    ]);
    res.json(present(settings, timer));
  }),
);

fastingRouter.put(
  "/",
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const body = fastingSchema.parse(req.body);
    const settings = await prisma.fastingSettings.upsert({
      where: { userId: user.id },
      create: { userId: user.id, ...body },
      update: body,
    });
    let timer = await prisma.fastingTimer.findUnique({ where: { userId: user.id } });
    if (!body.enabled && timer?.startedAt && !timer.stoppedAt) {
      timer = await prisma.fastingTimer.update({
        where: { userId: user.id },
        data: { stoppedAt: new Date() },
      });
    }
    res.json(present(settings, timer));
  }),
);

fastingRouter.post(
  "/start",
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    const settings = await prisma.fastingSettings.findUnique({ where: { userId: user.id } });
    if (!settings?.enabled) throw new HttpError(400, "fasting_disabled");
    const existing = await prisma.fastingTimer.findUnique({ where: { userId: user.id } });
    if (existing?.startedAt && !existing.stoppedAt) throw new HttpError(409, "timer_running");
    const timer = await prisma.fastingTimer.upsert({
      where: { userId: user.id },
      create: {
        userId: user.id,
        startedAt: new Date(),
        lengthHours: settings.lengthHours,
        stoppedAt: null,
      },
      update: {
        startedAt: new Date(),
        lengthHours: settings.lengthHours,
        stoppedAt: null,
      },
    });
    res.json(present(settings, timer));
  }),
);

fastingRouter.post(
  "/stop",
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    const settings = await prisma.fastingSettings.findUnique({ where: { userId: user.id } });
    const existing = await prisma.fastingTimer.findUnique({ where: { userId: user.id } });
    if (!existing?.startedAt || existing.stoppedAt) {
      res.json(present(settings, existing));
      return;
    }
    const timer = await prisma.fastingTimer.update({
      where: { userId: user.id },
      data: { stoppedAt: new Date() },
    });
    res.json(present(settings, timer));
  }),
);

function present(
  settings: { enabled: boolean; lengthHours: number; startHour: number; endHour: number } | null,
  timer: { startedAt: Date | null; lengthHours: number | null; stoppedAt: Date | null } | null,
) {
  const running = Boolean(timer?.startedAt && !timer.stoppedAt && timer.lengthHours);
  const endsAt =
    running && timer?.startedAt && timer.lengthHours
      ? new Date(timer.startedAt.getTime() + timer.lengthHours * 60 * 60 * 1000)
      : null;
  return {
    enabled: settings?.enabled ?? false,
    lengthHours: settings?.lengthHours ?? 16,
    startHour: settings?.startHour ?? 20,
    endHour: settings?.endHour ?? 12,
    running,
    startedAt: running ? timer?.startedAt?.toISOString() ?? null : null,
    endsAt: endsAt?.toISOString() ?? null,
    lengthHoursRunning: running ? timer?.lengthHours ?? null : null,
  };
}
