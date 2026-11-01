const TOKEN_KEY = "dropit_token";

export class ApiError extends Error {
  constructor(
    public code: string,
    public status?: number,
  ) {
    super(code);
  }
}

export function getStoredToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}

export function setStoredToken(token: string | null): void {
  try {
    if (token) {
      localStorage.setItem(TOKEN_KEY, token);
    } else {
      localStorage.removeItem(TOKEN_KEY);
    }
  } catch {}
}

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  if (init.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  const token = getStoredToken();
  if (token && !headers.has("Authorization")) {
    headers.set("Authorization", `Bearer ${token}`);
  }
  const response = await fetch(path, { ...init, headers, credentials: "include" });
  const data = (await response.json().catch(() => ({}))) as { error?: string; token?: string };
  if (!response.ok) {
    if (response.status === 401) setStoredToken(null);
    throw new ApiError(data.error ?? "server_error", response.status);
  }
  if (typeof data.token === "string" && data.token.length > 0) {
    setStoredToken(data.token);
  }
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

export type Operation =
  | "profile:read"
  | "profile:update"
  | "settings:update"
  | "days:read"
  | "entries:create"
  | "entries:delete"
  | "foods:read"
  | "foods:create"
  | "foods:update"
  | "foods:publish"
  | "foods:verify"
  | "weeks:read"
  | "weights:read"
  | "weights:create"
  | "fasting:read"
  | "fasting:update"
  | "fasting:timer"
  | "appleHealth:read"
  | "appleHealth:sync";

export const OPERATIONS: Operation[] = [
  "profile:read",
  "profile:update",
  "settings:update",
  "days:read",
  "entries:create",
  "entries:delete",
  "foods:read",
  "foods:create",
  "foods:update",
  "foods:publish",
  "foods:verify",
  "weeks:read",
  "weights:read",
  "weights:create",
  "fasting:read",
  "fasting:update",
  "fasting:timer",
  "appleHealth:read",
  "appleHealth:sync",
];

export type Me = {
  user: { id: string; email: string; language: "en" | "he"; isAdmin: boolean; autoPublishFoods: boolean };
  hasProfile: boolean;
  hasPassword: boolean;
  fastingEnabled: boolean;
  permissions: Operation[];
};

export type PermissionsResponse = {
  operations: Operation[];
  permissions: Record<Operation, boolean>;
};

export type Profile = {
  sex: "male" | "female";
  dateOfBirth: string;
  heightCm: number;
  weightKg: number;
  activity: "sedentary" | "light" | "moderate" | "very" | "extra";
  weeklyPace: "kg025" | "kg050" | "kg100";
  customGoalKcal: number | null;
};

export type MealCategory = "breakfast" | "lunch" | "dinner" | "snacks";

export const MEALS: MealCategory[] = ["breakfast", "lunch", "dinner", "snacks"];

export type DayEntry = Nutrients & {
  id: string;
  foodId: string | null;
  name: string;
  basis: "solid" | "liquid";
  meal: MealCategory;
  amount: number;
};

export type DayResponse = {
  day: string;
  /** Effective food budget: the base plus Apple active kcal when healthAdjusted. */
  goalKcal: number;
  baseGoalKcal: number;
  activeKcal: number;
  healthAdjusted: boolean;
  healthSynced: boolean;
  steps: number;
  stepGoal: number;
  exerciseMinutes: number;
  exerciseGoalMinutes: number;
  entries: DayEntry[];
  totals: Nutrients;
  success: boolean;
  future: boolean;
};

export type WeekResponse = {
  sunday: string;
  goalKcal: number;
  activeKcal: number;
  healthSynced: boolean;
  stepGoal: number;
  exerciseGoalMinutes: number;
  calorieIntake: number;
  successCount: number;
  weightChangeKg: number | null;
  days: {
    day: string;
    goalKcal: number;
    calories: number;
    success: boolean;
    future: boolean;
    steps?: number | null;
    exerciseMinutes?: number | null;
    activeKcal?: number;
  }[];
};

export type WeightPoint = { id: string; weightKg: number; loggedAt: string; source: "manual" | "health" };

export type AppleHealthState = {
  connected: boolean;
  connectedOn: string | null;
  lastSyncedAt: string | null;
  exerciseGoalMinutes: number;
  stepGoal: number;
};

export type FastingSession = {
  id: string;
  startedAt: string;
  endedAt: string | null;
  endsAt: string;
  lengthHours: number;
  running: boolean;
  durationMinutes: number | null;
};

export type FastNotificationKind = "lead" | "late" | "done";

export type FastNotification = {
  id: string;
  at: string;
  kind: FastNotificationKind;
  leadMinutes: number | null;
};

export type ReminderOffset = 0 | 30 | 60;

export type FastingState = {
  enabled: boolean;
  lengthHours: number;
  startHour: number;
  endHour: number;
  reminderOffsets: ReminderOffset[];
  notifications: FastNotification[];
  running: boolean;
  startedAt: string | null;
  endsAt: string | null;
  lengthHoursRunning: number | null;
  sessions: FastingSession[];
};
