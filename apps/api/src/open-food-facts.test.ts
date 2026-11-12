import assert from "node:assert/strict";
import test from "node:test";
import { lookupOpenFoodFacts, parseOpenFoodFactsProduct } from "./open-food-facts.js";

test("parses per-100g values and converts salt/sodium to mg", () => {
  const result = parseOpenFoodFactsProduct("7290000000001", {
    product_name: " Cottage ",
    quantity: "250 g",
    nutriments: { "energy-kcal_100g": 98, proteins_100g: 11.5, carbohydrates_100g: 3.4, fat_100g: 4, salt_100g: 1.25 },
  });
  assert.deepEqual(result, {
    barcode: "7290000000001",
    name: "Cottage",
    basis: "solid",
    calories: 98,
    protein: 11.5,
    carbohydrates: 3.4,
    fat: 4,
    fiber: 0,
    sugars: 0,
    sodium: 500,
  });
});

test("falls back to kJ and detects liquids", () => {
  const result = parseOpenFoodFactsProduct("7290000000002", {
    product_name_he: "חלב",
    quantity: "1 l",
    nutriments: { energy_100g: 251.2, sodium_100g: 0.05 },
  });
  assert.equal(result?.calories, 60.04);
  assert.equal(result?.basis, "liquid");
  assert.equal(result?.sodium, 50);
});

test("returns null without a name or calories", () => {
  assert.equal(parseOpenFoodFactsProduct("1", { product_name: "", nutriments: { "energy-kcal_100g": 5 } }), null);
  assert.equal(parseOpenFoodFactsProduct("1", { product_name: "X", nutriments: {} }), null);
  assert.equal(parseOpenFoodFactsProduct("1", null), null);
});

test("lookup is best effort", async () => {
  const ok = (async () => new Response(JSON.stringify({ status: 1, product: { product_name: "A", nutriments: { "energy-kcal_100g": 10 } } }))) as typeof fetch;
  assert.equal((await lookupOpenFoodFacts("7290000000003", ok))?.name, "A");
  const boom = (async () => { throw new Error("offline"); }) as typeof fetch;
  assert.equal(await lookupOpenFoodFacts("7290000000003", boom), null);
  assert.equal(await lookupOpenFoodFacts("abc", ok), null);
});
