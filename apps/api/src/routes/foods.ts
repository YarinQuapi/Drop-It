import { Router } from "express";
import { currentUser, requireUser } from "../auth.js";
import { prisma } from "../db.js";
import { resolveBarcode } from "../domain.js";
import { asyncRoute, HttpError } from "../http.js";
import { presentFood } from "../present.js";
import { requirePermission } from "../rbac.js";
import { foodSchema, foodUpdateSchema } from "../schemas.js";

export const foodsRouter = Router();
foodsRouter.use(requireUser);

foodsRouter.get(
  "/:id",
  requirePermission("foods:read"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const food = await prisma.food.findUnique({ where: { id: req.params.id } });
    if (!food || (food.ownerId !== user.id && !food.published)) throw new HttpError(404, "not_found");
    res.json({ food: presentFood(food, user.id) });
  }),
);

foodsRouter.get(
  "/barcode/:code",
  requirePermission("foods:read"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const barcode = decodeURIComponent(req.params.code).trim();
    if (!barcode) throw new HttpError(400, "invalid_body");
    const rows = await prisma.food.findMany({
      where: {
        barcode,
        OR: [{ ownerId: user.id }, { published: true }],
      },
      orderBy: { name: "asc" },
    });
    const own = rows.find((food) => food.ownerId === user.id) ?? null;
    const published = rows.filter((food) => food.published && food.ownerId !== user.id);
    const verified = published.find((food) => food.verifiedAt != null) ?? null;
    const decision = resolveBarcode({ own, verified, published });
    res.json({
      status: decision.status,
      food: decision.food ? presentFood(decision.food, user.id) : null,
      foods: decision.foods.map((food) => presentFood(food, user.id)),
    });
  }),
);

foodsRouter.post(
  "/",
  requirePermission("foods:create"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const body = foodSchema.parse(req.body);
    const existing = await prisma.food.findUnique({
      where: { ownerId_barcode: { ownerId: user.id, barcode: body.barcode } },
    });
    if (existing) throw new HttpError(409, "already_exists");
    const food = await prisma.food.create({
      data: {
        ...body,
        ownerId: user.id,
        published: user.autoPublishFoods,
      },
    });
    res.status(201).json({ food: presentFood(food, user.id) });
  }),
);

foodsRouter.put(
  "/:id",
  requirePermission("foods:update"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const body = foodUpdateSchema.parse(req.body);
    const food = await prisma.food.findUnique({ where: { id: req.params.id } });
    if (!food) throw new HttpError(404, "not_found");
    if (food.ownerId === user.id) {
      const updated = await prisma.food.update({
        where: { id: food.id },
        data: { ...body, verifiedAt: null, verifiedById: null },
      });
      res.json({ food: presentFood(updated, user.id) });
      return;
    }
    if (!food.published) throw new HttpError(403, "forbidden");
    const copy = await prisma.food.upsert({
      where: { ownerId_barcode: { ownerId: user.id, barcode: food.barcode } },
      create: {
        barcode: food.barcode,
        ownerId: user.id,
        published: false,
        ...body,
      },
      update: { ...body, verifiedAt: null, verifiedById: null },
    });
    res.json({ food: presentFood(copy, user.id) });
  }),
);

foodsRouter.post(
  "/:id/publish",
  requirePermission("foods:publish"),
  asyncRoute(async (req, res) => {
    const food = await ownFood(req.params.id, currentUser(res).id);
    const updated = await prisma.food.update({
      where: { id: food.id },
      data: { published: true },
    });
    res.json({ food: presentFood(updated, food.ownerId) });
  }),
);

foodsRouter.post(
  "/:id/unpublish",
  requirePermission("foods:publish"),
  asyncRoute(async (req, res) => {
    const food = await ownFood(req.params.id, currentUser(res).id);
    const updated = await prisma.food.update({
      where: { id: food.id },
      data: { published: false, verifiedAt: null, verifiedById: null },
    });
    res.json({ food: presentFood(updated, food.ownerId) });
  }),
);

foodsRouter.post(
  "/:id/verify",
  requirePermission("foods:verify"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const food = await prisma.food.findUnique({ where: { id: req.params.id } });
    if (!food || !food.published) throw new HttpError(404, "not_found");
    const updated = await prisma.$transaction(async (tx) => {
      await tx.food.updateMany({
        where: { barcode: food.barcode, verifiedAt: { not: null } },
        data: { verifiedAt: null, verifiedById: null },
      });
      return tx.food.update({
        where: { id: food.id },
        data: { verifiedAt: new Date(), verifiedById: user.id },
      });
    });
    res.json({ food: presentFood(updated, user.id) });
  }),
);

async function ownFood(id: string, userId: string) {
  const food = await prisma.food.findUnique({ where: { id } });
  if (!food) throw new HttpError(404, "not_found");
  if (food.ownerId !== userId) throw new HttpError(403, "forbidden");
  return food;
}
