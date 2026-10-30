import { Router } from "express";
import { currentUser, requireUser } from "../auth.js";
import { prisma } from "../db.js";
import { asyncRoute } from "../http.js";
import { num } from "../present.js";
import { requirePermission } from "../rbac.js";
import { weightSchema } from "../schemas.js";

export const weightsRouter = Router();
weightsRouter.use(requireUser);

weightsRouter.get(
  "/",
  requirePermission("weights:read"),
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    const rows = await prisma.weightEntry.findMany({
      where: { userId: user.id },
      orderBy: { loggedAt: "asc" },
    });
    res.json({
      weights: rows.map((entry) => ({
        id: entry.id,
        weightKg: num(entry.weightKg),
        loggedAt: entry.loggedAt.toISOString(),
      })),
    });
  }),
);

weightsRouter.post(
  "/",
  requirePermission("weights:create"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const body = weightSchema.parse(req.body);
    const entry = await prisma.weightEntry.create({
      data: {
        userId: user.id,
        weightKg: body.weightKg,
        loggedAt: body.loggedAt ? new Date(body.loggedAt) : new Date(),
      },
    });
    res.status(201).json({
      weight: {
        id: entry.id,
        weightKg: num(entry.weightKg),
        loggedAt: entry.loggedAt.toISOString(),
      },
    });
  }),
);
