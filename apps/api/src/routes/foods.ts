import { Router } from "express";
import { currentUser, requireUser } from "../auth.js";
import { prisma } from "../db.js";
import { resolveBarcode } from "../domain.js";
import { asyncRoute, HttpError } from "../http.js";
import { lookupOpenFoodFacts } from "../open-food-facts.js";
import { CATALOG_PAGE_SIZE, catalogWhere, pickRecentFoods, pickSearchResults } from "../food-search.js";
import { num, presentFood } from "../present.js";
import { requirePermission } from "../rbac.js";
import { catalogQuerySchema, foodSchema, foodUpdateSchema } from "../schemas.js";

export const foodsRouter = Router();
foodsRouter.use(requireUser);

foodsRouter.get(
  "/search",
  requirePermission("foods:read"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const query = String(req.query.q ?? "").trim().slice(0, 64);
    if (query.length < 2) {
      res.json({ foods: [] });
      return;
    }
    const rows = await prisma.food.findMany({
      where: {
        AND: [
          { OR: [{ ownerId: user.id }, { published: true }] },
          { OR: [{ name: { contains: query } }, { barcode: { startsWith: query } }] },
        ],
      },
      orderBy: { name: "asc" },
      take: 60,
    });
    res.json({ foods: pickSearchResults(rows, user.id, 20).map((food) => presentFood(food, user.id)) });
  }),
);

// Must stay above "/:id" or "catalog" would be read as a food id.
foodsRouter.get(
  "/catalog",
  requirePermission("foods:read"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const query = catalogQuerySchema.parse(req.query);
    const rows = await prisma.food.findMany({
      where: catalogWhere(user.id, query),
      orderBy: [{ name: "asc" }, { id: "asc" }],
      skip: query.offset,
      take: CATALOG_PAGE_SIZE + 1,
    });
    res.json({
      foods: rows.slice(0, CATALOG_PAGE_SIZE).map((food) => presentFood(food, user.id)),
      hasMore: rows.length > CATALOG_PAGE_SIZE,
    });
  }),
);

foodsRouter.get(
  "/recent",
  requirePermission("foods:read"),
  asyncRoute(async (_req, res) => {
    const user = currentUser(res);
    const entries = await prisma.diaryEntry.findMany({
      where: { userId: user.id, foodId: { not: null } },
      orderBy: { createdAt: "desc" },
      select: { foodId: true, amount: true },
      take: 200,
    });
    const recent = pickRecentFoods(entries.map((entry) => ({ foodId: entry.foodId, amount: num(entry.amount) })), 10);
    const foods = await prisma.food.findMany({
      where: {
        id: { in: recent.map((item) => item.foodId) },
        OR: [{ ownerId: user.id }, { published: true }],
      },
    });
    const byId = new Map(foods.map((food) => [food.id, food]));
    res.json({
      foods: recent.flatMap((item) => {
        const food = byId.get(item.foodId);
        return food ? [{ ...presentFood(food, user.id), lastAmount: item.lastAmount }] : [];
      }),
    });
  }),
);

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
    // Not in our catalog: offer Open Food Facts values to prefill a new food. Nothing is saved here.
    const suggestion = decision.status === "none" ? await lookupOpenFoodFacts(barcode) : null;
    res.json({
      status: suggestion ? "external" : decision.status,
      food: decision.food ? presentFood(decision.food, user.id) : null,
      foods: decision.foods.map((food) => presentFood(food, user.id)),
      suggestion,
    });
  }),
);

foodsRouter.post(
  "/",
  requirePermission("foods:create"),
  asyncRoute(async (req, res) => {
    const user = currentUser(res);
    const body = foodSchema.parse(req.body);
    if (body.barcode) {
      const existing = await prisma.food.findFirst({ where: { ownerId: user.id, barcode: body.barcode } });
      if (existing) throw new HttpError(409, "already_exists");
    }
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
    // Editing someone else's published food makes a personal copy.
    // With a barcode there is at most one copy per owner; without one, always a new copy.
    const copy = food.barcode
      ? await prisma.food.upsert({
          where: { ownerId_barcode: { ownerId: user.id, barcode: food.barcode } },
          create: { barcode: food.barcode, ownerId: user.id, published: false, ...body },
          update: { ...body, verifiedAt: null, verifiedById: null },
        })
      : await prisma.food.create({
          data: { barcode: null, ownerId: user.id, published: false, ...body },
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
      // Only one verified food per barcode. Foods without a barcode are verified independently.
      if (food.barcode) {
        await tx.food.updateMany({
          where: { barcode: food.barcode, verifiedAt: { not: null } },
          data: { verifiedAt: null, verifiedById: null },
        });
      }
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
