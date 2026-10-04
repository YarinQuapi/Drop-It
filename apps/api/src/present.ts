import type { Food, FoodBasis } from "../generated/prisma/client.js";

export function num(value: { toNumber(): number } | number): number {
  return typeof value === "number" ? value : value.toNumber();
}

export function presentFood(food: Food, viewerId: string) {
  return {
    id: food.id,
    barcode: food.barcode,
    name: food.name,
    basis: food.basis as FoodBasis,
    calories: num(food.calories),
    protein: num(food.protein),
    carbohydrates: num(food.carbohydrates),
    fat: num(food.fat),
    fiber: num(food.fiber),
    sugars: num(food.sugars),
    sodium: num(food.sodium),
    published: food.published,
    verified: food.verifiedAt != null,
    owned: food.ownerId === viewerId,
  };
}
