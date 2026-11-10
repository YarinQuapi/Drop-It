type SearchableFood = {
  id: string;
  barcode: string | null;
  name: string;
  ownerId: string;
  verifiedAt: Date | null;
};

function rank(food: SearchableFood, viewerId: string): number {
  if (food.ownerId === viewerId) return 0;
  if (food.verifiedAt != null) return 1;
  return 2;
}

/**
 * One result per barcode: the viewer's own food wins, then a verified one,
 * then any published copy. Foods without a barcode are never merged.
 * Own foods are listed first, then by name.
 */
export function pickSearchResults<T extends SearchableFood>(foods: T[], viewerId: string, limit: number): T[] {
  const best = new Map<string, T>();
  for (const food of foods) {
    const key = food.barcode ?? `id:${food.id}`;
    const current = best.get(key);
    if (!current || rank(food, viewerId) < rank(current, viewerId)) best.set(key, food);
  }
  return [...best.values()]
    .sort((a, b) => rank(a, viewerId) - rank(b, viewerId) || a.name.localeCompare(b.name))
    .slice(0, limit);
}

/** Most recently logged distinct foods, newest first, with the amount used last time. */
export function pickRecentFoods(
  entries: { foodId: string | null; amount: number }[],
  limit: number,
): { foodId: string; lastAmount: number }[] {
  const seen = new Set<string>();
  const result: { foodId: string; lastAmount: number }[] = [];
  for (const entry of entries) {
    if (!entry.foodId || seen.has(entry.foodId)) continue;
    seen.add(entry.foodId);
    result.push({ foodId: entry.foodId, lastAmount: entry.amount });
    if (result.length >= limit) break;
  }
  return result;
}

export const CATALOG_PAGE_SIZE = 30;

export type CatalogScope = "published" | "mine";
export type CatalogStatus = "all" | "verified" | "unverified";

/**
 * Filter for the food catalog: every published food, or only the viewer's own
 * foods (published or not). Optionally narrowed to verified/unverified and to
 * a name or barcode search.
 */
export function catalogWhere(
  viewerId: string,
  { scope, status, q }: { scope: CatalogScope; status: CatalogStatus; q: string },
) {
  const and: object[] = [scope === "mine" ? { ownerId: viewerId } : { published: true }];
  if (status === "verified") and.push({ verifiedAt: { not: null } });
  if (status === "unverified") and.push({ verifiedAt: null });
  if (q) and.push({ OR: [{ name: { contains: q } }, { barcode: { startsWith: q } }] });
  return { AND: and };
}
