export class ApiError extends Error {
  constructor(public code: string) {
    super(code);
  }
}

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  if (init.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  const response = await fetch(path, { ...init, headers, credentials: "include" });
  const data = (await response.json().catch(() => ({}))) as { error?: string };
  if (!response.ok) throw new ApiError(data.error ?? "server_error");
  return data as T;
}

export type Nutrients = {
  calories: number;
  protein: number;
  carbohydrates: number;
  fat: number;
  fiber: number;
  sugars: number;
  sodium: number;
};

export type Food = Nutrients & {
  id: string;
  barcode: string;
  name: string;
  basis: "solid" | "liquid";
  published: boolean;
  verified: boolean;
  owned: boolean;
};

export type Me = {
  user: { id: string; email: string; language: "en" | "he"; isAdmin: boolean; autoPublishFoods: boolean };
  hasProfile: boolean;
  fastingEnabled: boolean;
};

export type Profile = {
  sex: "male" | "female";
  dateOfBirth: string;
  heightCm: number;
  weightKg: number;
  activity: "sedentary" | "light" | "moderate" | "very" | "extra";
  weeklyPace: "kg025" | "kg050" | "kg100";
};

export type DayEntry = Nutrients & {
  id: string;
  foodId: string | null;
  name: string;
  basis: "solid" | "liquid";
  amount: number;
};

export type DayResponse = {
  day: string;
  goalKcal: number;
  entries: DayEntry[];
  totals: Nutrients;
  success: boolean;
  future: boolean;
};

export type WeekResponse = {
  sunday: string;
  calorieIntake: number;
  successCount: number;
  weightChangeKg: number | null;
  days: { day: string; goalKcal: number; calories: number; success: boolean; future: boolean }[];
};

export type WeightPoint = { id: string; weightKg: number; loggedAt: string };

export type FastingState = {
  enabled: boolean;
  lengthHours: number;
  startHour: number;
  endHour: number;
  running: boolean;
  startedAt: string | null;
  endsAt: string | null;
  lengthHoursRunning: number | null;
};
