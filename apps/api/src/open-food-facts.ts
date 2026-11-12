/** Barcode lookup in Open Food Facts, used when a barcode is not in our own catalog. */

export type FoodSuggestion = {
  barcode: string;
  name: string;
  basis: "solid" | "liquid";
  calories: number;
  protein: number;
  carbohydrates: number;
  fat: number;
  fiber: number;
  sugars: number;
  sodium: number;
};

const FIELDS = "product_name,product_name_he,product_name_en,quantity,nutriments";
const TIMEOUT_MS = 4000;

function round(value: number): number {
  return Math.round(value * 100) / 100;
}

function amount(nutriments: Record<string, unknown>, key: string): number | null {
  const value = nutriments[key];
  const parsed = typeof value === "string" ? Number(value) : value;
  return typeof parsed === "number" && Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

/**
 * Turns an Open Food Facts product into a suggestion for a new food (values per 100 g / 100 ml).
 * Returns null when the product has no name or no calories: nothing useful to prefill.
 * Sodium is stored in mg; Open Food Facts reports grams, or salt (sodium = salt / 2.5).
 */
export function parseOpenFoodFactsProduct(barcode: string, product: unknown): FoodSuggestion | null {
  if (!product || typeof product !== "object") return null;
  const p = product as Record<string, unknown>;
  const nutriments = (p.nutriments && typeof p.nutriments === "object" ? p.nutriments : {}) as Record<string, unknown>;
  const text = (key: string) => (typeof p[key] === "string" ? (p[key] as string).trim() : "");
  const name = (text("product_name") || text("product_name_he") || text("product_name_en")).slice(0, 120);
  let calories = amount(nutriments, "energy-kcal_100g");
  if (calories == null) {
    const kj = amount(nutriments, "energy_100g");
    calories = kj == null ? null : kj / 4.184;
  }
  if (!name || calories == null || calories > 10000) return null;
  const sodiumGrams = amount(nutriments, "sodium_100g") ?? (() => {
    const salt = amount(nutriments, "salt_100g");
    return salt == null ? null : salt / 2.5;
  })();
  const quantity = text("quantity").toLowerCase();
  return {
    barcode,
    name,
    basis: /\d\s*(ml|cl|l)\b|מ"ל|מל/.test(quantity) ? "liquid" : "solid",
    calories: round(calories),
    protein: round(amount(nutriments, "proteins_100g") ?? 0),
    carbohydrates: round(amount(nutriments, "carbohydrates_100g") ?? 0),
    fat: round(amount(nutriments, "fat_100g") ?? 0),
    fiber: round(amount(nutriments, "fiber_100g") ?? 0),
    sugars: round(amount(nutriments, "sugars_100g") ?? 0),
    sodium: round((sodiumGrams ?? 0) * 1000),
  };
}

/** Best effort: any network or format problem means "not found", never an error for the user. */
export async function lookupOpenFoodFacts(
  barcode: string,
  fetchImpl: typeof fetch = fetch,
): Promise<FoodSuggestion | null> {
  if (!/^\d{6,14}$/.test(barcode)) return null;
  try {
    const response = await fetchImpl(
      `https://world.openfoodfacts.org/api/v2/product/${barcode}.json?fields=${FIELDS}`,
      { headers: { "User-Agent": "DropIt/1.0" }, signal: AbortSignal.timeout(TIMEOUT_MS) },
    );
    if (!response.ok) return null;
    const body = (await response.json()) as { status?: number; product?: unknown };
    return body.status === 1 ? parseOpenFoodFactsProduct(barcode, body.product) : null;
  } catch {
    return null;
  }
}
