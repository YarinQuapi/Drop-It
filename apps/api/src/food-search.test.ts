import assert from "node:assert/strict";
import test from "node:test";
import { pickRecentFoods, pickSearchResults } from "./food-search.js";

const food = (id: string, barcode: string, name: string, ownerId: string, verified = false) => ({
  id,
  barcode,
  name,
  ownerId,
  verifiedAt: verified ? new Date() : null,
});

test("search keeps one food per barcode, preferring own then verified", () => {
  const results = pickSearchResults(
    [
      food("a", "111", "Yogurt", "other"),
      food("b", "111", "Yogurt (verified)", "other2", true),
      food("c", "222", "Bread", "other"),
      food("d", "222", "My bread", "me"),
    ],
    "me",
    10,
  );
  assert.deepEqual(results.map((item) => item.id), ["d", "b"]);
});

test("search never merges foods without a barcode", () => {
  const results = pickSearchResults(
    [
      { id: "a", barcode: null, name: "Banana", ownerId: "me", verifiedAt: null },
      { id: "b", barcode: null, name: "Banana", ownerId: "other", verifiedAt: null },
    ],
    "me",
    10,
  );
  assert.deepEqual(results.map((item) => item.id), ["a", "b"]);
});

test("search respects the limit", () => {
  const results = pickSearchResults(
    [food("a", "1", "A", "x"), food("b", "2", "B", "x"), food("c", "3", "C", "x")],
    "me",
    2,
  );
  assert.deepEqual(results.map((item) => item.id), ["a", "b"]);
});

test("recent foods are distinct, newest first, with the last amount", () => {
  const results = pickRecentFoods(
    [
      { foodId: "a", amount: 150 },
      { foodId: null, amount: 10 },
      { foodId: "b", amount: 30 },
      { foodId: "a", amount: 100 },
      { foodId: "c", amount: 200 },
    ],
    2,
  );
  assert.deepEqual(results, [
    { foodId: "a", lastAmount: 150 },
    { foodId: "b", lastAmount: 30 },
  ]);
});
