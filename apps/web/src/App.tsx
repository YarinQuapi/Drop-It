import { useEffect, useRef, useState, type ComponentProps, type FormEvent, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { Link, NavLink, Navigate, Route, Routes, useLocation, useNavigate, useParams, useSearchParams } from "react-router-dom";
import {
  api,
  peek,
  ApiError,
  type AppleHealthState,
  type DayEntry,
  type DayResponse,
  type DayStatus,
  type FastingSession,
  type FastingState,
  type FastNotification,
  type Food,
  type FoodSuggestion,
  type ReminderOffset,
  MEALS,
  type MealCategory,
  type Me,
  OPERATIONS,
  type Operation,
  type PermissionsResponse,
  type Profile,
  setStoredToken,
  type WeekResponse,
  type WeightPoint,
} from "./api";
import { fetchAppleConfig, signInWithApple, type AppleConfig } from "./apple";
import { addDays, formatDayLabel, formatJerusalem, formatJerusalemDay, formatJerusalemTime, formatWeekday, formatWeekRange, hourLabel, jerusalemParts, todayJerusalemDay } from "./clock";
import { THEME_MODES, useI18n, useTheme, type Copy, type Lang, type ThemeMode } from "./i18n";
import {
  ageFromDob,
  suggestedCalorieGoal,
  type ActivityLevel,
  type Sex,
  type WeeklyPace,
} from "./calorieGoal";
import { DateField, MenuField } from "./pickers";

export function App() {
  const { setLang } = useI18n();
  const [me, setMe] = useState<Me | null | undefined>(undefined);

  useEffect(() => {
    api<Me>("/api/auth/me")
      .then((next) => {
        setMe(next);
        setLang(next.user.language);
      })
      .catch(() => setMe(null));
  }, [setLang]);

  if (me === undefined) return <main className="shell"><p className="muted loading">…</p></main>;

  return (
    <Routes>
      <Route path="/login" element={me ? <Navigate to={me.hasProfile ? "/" : "/setup/fasting"} /> : <AuthPage key="login" mode="login" onAuth={setMe} />} />
      <Route path="/signup" element={me ? <Navigate to={me.hasProfile ? "/" : "/setup/fasting"} /> : <AuthPage key="signup" mode="signup" onAuth={setMe} />} />
      <Route path="/setup/fasting" element={me ? <FastingSetup onDone={() => setMe({ ...me })} /> : <Navigate to="/login" />} />
      <Route path="/setup/profile" element={me ? <ProfileSetup onDone={(next) => setMe(next)} /> : <Navigate to="/login" />} />
      <Route path="/*" element={me ? <Shell me={me} setMe={setMe} /> : <Navigate to="/login" />} />
    </Routes>
  );
}

function Shell({ me, setMe }: { me: Me; setMe: (me: Me | null) => void }) {
  const { t } = useI18n();
  const location = useLocation();
  const [reminderVersion, setReminderVersion] = useState(0);
  const [notice, setNotice] = useState("");
  function bumpReminders() {
    setReminderVersion((value) => value + 1);
  }
  useEffect(() => {
    if (!notice) return;
    const id = window.setTimeout(() => setNotice(""), 8000);
    return () => window.clearTimeout(id);
  }, [notice]);
  useEffect(() => {
    function onVisible() {
      if (document.visibilityState === "visible") bumpReminders();
    }
    document.addEventListener("visibilitychange", onVisible);
    return () => document.removeEventListener("visibilitychange", onVisible);
  }, []);
  useEffect(() => {
    if (!me.hasProfile) return;
    let cancelled = false;
    const timers: number[] = [];
    api<FastingState>("/api/fasting")
      .then((fasting) => {
        if (cancelled) return;
        for (const item of fasting.notifications ?? []) {
          const wait = new Date(item.at).getTime() - Date.now();
          if (wait <= 0) continue;
          timers.push(
            window.setTimeout(() => {
              notify(reminderText(t, item), setNotice);
              bumpReminders();
            }, wait),
          );
        }
      })
      .catch(() => {});
    return () => {
      cancelled = true;
      timers.forEach((id) => window.clearTimeout(id));
    };
  }, [me.hasProfile, reminderVersion, t]);
  if (!me.hasProfile && !location.pathname.startsWith("/setup")) {
    return <Navigate to="/setup/fasting" />;
  }
  const canVerifyFoods = me.user.isAdmin || me.permissions.includes("foods:verify");
  // New page starts at the top (otherwise the old scroll position carries over).
  useEffect(() => {
    window.scrollTo(0, 0);
  }, [location.pathname]);
  async function logout() {
    await api("/api/auth/logout", { method: "POST" }).catch(() => {});
    setStoredToken(null);
    setMe(null);
  }
  return (
    <>
      <header className="topbar">
        <div className="topbar-inner">
          <strong>{t.appName}</strong>
          <TabNav className="tabs-top" />
        </div>
      </header>
      <div className="shell">
      <div key={location.pathname} className="page">
        {notice && <p className="rise">{notice}</p>}
        <Routes location={location}>
          <Route path="/" element={<Today canVerifyFoods={canVerifyFoods} onFastingChange={bumpReminders} />} />
          <Route path="/week" element={<WeekPage />} />
          <Route path="/weight" element={<WeightPage />} />
          <Route path="/fasting" element={<FastingPage onFastingChange={bumpReminders} />} />
          <Route path="/settings/:section?" element={<SettingsPage me={me} setMe={setMe} onFastingChange={bumpReminders} onLogout={logout} />} />
          <Route path="/permissions" element={me.user.isAdmin ? <PermissionsPage /> : <Navigate to="/" />} />
          <Route path="/catalog" element={<CatalogPage canVerifyFoods={canVerifyFoods} />} />
          <Route path="/foods/new" element={<FoodForm />} />
          <Route path="/foods/:id" element={<FoodForm />} />
        </Routes>
      </div>
      </div>
      <TabNav className="tabbar" />
    </>
  );
}

type CatalogScope = "published" | "mine";
type CatalogStatus = "all" | "verified" | "unverified";
type CatalogResponse = { foods: Food[]; hasMore: boolean };

/** Every published food, or your own; admins (foods:verify) can verify entries here. */
function CatalogPage({ canVerifyFoods }: { canVerifyFoods: boolean }) {
  const { t } = useI18n();
  const [scope, setScope] = useState<CatalogScope>("published");
  const [status, setStatus] = useState<CatalogStatus>("all");
  const [search, setSearch] = useState("");
  const [query, setQuery] = useState("");
  const [foods, setFoods] = useState<Food[] | null>(null);
  const [hasMore, setHasMore] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [error, setError] = useState("");
  const request = useRef(0);

  // Debounce typing so every keystroke isn't a request.
  useEffect(() => {
    const id = window.setTimeout(() => setQuery(search.trim()), 250);
    return () => window.clearTimeout(id);
  }, [search]);

  function url(offset: number) {
    const params = new URLSearchParams({ scope, status, offset: String(offset) });
    if (query) params.set("q", query);
    return `/api/foods/catalog?${params}`;
  }

  useEffect(() => {
    const id = ++request.current;
    setError("");
    setExpanded(null);
    api<CatalogResponse>(url(0))
      .then((res) => {
        if (id !== request.current) return; // a newer filter already answered
        setFoods(res.foods);
        setHasMore(res.hasMore);
      })
      .catch((err) => {
        if (id === request.current) setError(message(t, err));
      });
  }, [scope, status, query]);

  async function loadMore() {
    if (!foods) return;
    const id = request.current;
    setLoadingMore(true);
    try {
      const res = await api<CatalogResponse>(url(foods.length));
      if (id !== request.current) return;
      setFoods([...foods, ...res.foods]);
      setHasMore(res.hasMore);
    } catch (err) {
      setError(message(t, err));
    } finally {
      setLoadingMore(false);
    }
  }

  async function verify(food: Food) {
    try {
      const res = await api<{ food: Food }>(`/api/foods/${food.id}/verify`, { method: "POST" });
      // Only one verified food per barcode: the server un-verifies the others.
      setFoods((current) =>
        (current ?? []).map((item) =>
          item.id === food.id ? res.food : food.barcode && item.barcode === food.barcode ? { ...item, verified: false } : item,
        ),
      );
    } catch (err) {
      setError(message(t, err));
    }
  }

  return (
    <>
      <h1>{t.foodCatalog}</h1>
      <div className="segmented" role="group" aria-label={t.foodCatalog}>
        <button type="button" aria-pressed={scope === "published"} onClick={() => setScope("published")}>{t.catalogPublished}</button>
        <button type="button" aria-pressed={scope === "mine"} onClick={() => setScope("mine")}>{t.catalogMine}</button>
      </div>
      <div className="catalog-tools">
        <input type="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder={t.catalogSearch} aria-label={t.catalogSearch} />
        <div className="segmented" role="group" aria-label={t.catalogFilter}>
          <button type="button" aria-pressed={status === "all"} onClick={() => setStatus("all")}>{t.catalogAll}</button>
          <button type="button" aria-pressed={status === "verified"} onClick={() => setStatus("verified")}>{t.verified}</button>
          <button type="button" aria-pressed={status === "unverified"} onClick={() => setStatus("unverified")}>{t.catalogUnverified}</button>
        </div>
        {scope === "mine" && <Link className="button" to="/foods/new">{t.createFood}</Link>}
      </div>
      {error && <p className="error">{error}</p>}
      {!foods && !error && <p className="muted loading">…</p>}
      {foods && foods.length === 0 && <p className="muted">{scope === "mine" && !query && status === "all" ? t.catalogEmptyMine : t.catalogEmpty}</p>}
      {foods && foods.length > 0 && (
        <div className="card list-card catalog-list">
          {foods.map((food) => {
            const open = expanded === food.id;
            return (
              <div key={food.id} className="catalog-item">
                <button type="button" className="food-row" aria-expanded={open} onClick={() => setExpanded(open ? null : food.id)}>
                  <span className="food-row-name">
                    <strong>{food.name}</strong>
                    <span className="muted">{food.calories} {t.kcal} / 100 {unitLabel(t, food)}</span>
                  </span>
                  <span className="catalog-badges">
                    {food.verified && <span className="chip chip-verified">{t.verified}</span>}
                    {food.owned && !food.published && <span className="chip">{t.catalogPrivate}</span>}
                  </span>
                </button>
                {open && (
                  <div className="catalog-detail rise">
                    <dl className="catalog-macros">
                      <div><dt>{t.protein}</dt><dd>{food.protein}</dd></div>
                      <div><dt>{t.carbohydrates}</dt><dd>{food.carbohydrates}</dd></div>
                      <div><dt>{t.fat}</dt><dd>{food.fat}</dd></div>
                      <div><dt>{t.fiber}</dt><dd>{food.fiber}</dd></div>
                      <div><dt>{t.sugars}</dt><dd>{food.sugars}</dd></div>
                      <div><dt>{t.sodium}</dt><dd>{food.sodium}</dd></div>
                    </dl>
                    {food.barcode && <p className="muted">{t.barcode}: {food.barcode}</p>}
                    <div className="fast-actions">
                      {canVerifyFoods && food.published && !food.verified && (
                        <button type="button" onClick={() => verify(food)}>{t.verify}</button>
                      )}
                      {food.owned && <Link className="secondary" to={`/foods/${food.id}`}>{t.edit}</Link>}
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}
      {hasMore && <button type="button" className="secondary" disabled={loadingMore} onClick={loadMore}>{t.catalogLoadMore}</button>}
    </>
  );
}

/** Top-level destinations (HIG tab bar): bottom on phones, in the top bar on wide screens. */
function TabNav({ className }: { className: string }) {
  const { t } = useI18n();
  const tabs: { to: string; label: string; icon: ReactNode; end?: boolean }[] = [
    { to: "/", label: t.today, end: true, icon: <><circle cx="12" cy="12" r="8" opacity="0.35" /><path d="M12 4a8 8 0 0 1 7.6 10.5" /></> },
    { to: "/week", label: t.week, icon: <path d="M5 20V12M10 20V6M15 20v-9M20 20V9" /> },
    { to: "/fasting", label: t.fastingTab, icon: <><circle cx="12" cy="13" r="7.5" /><path d="M12 9.5V13l2.5 1.5M10 3h4" /></> },
    { to: "/catalog", label: t.catalogTab, icon: <><path d="M4 7.5 12 4l8 3.5v9L12 20l-8-3.5z" /><path d="M4 7.5 12 11l8-3.5M12 11v9" /></> },
    { to: "/weight", label: t.weight, icon: <><rect x="4" y="4" width="16" height="16" rx="4" /><path d="M9 10a3 3 0 0 1 6 0M12 10l1.5-1.5" /></> },
    { to: "/settings", label: t.settings, icon: <><circle cx="12" cy="12" r="3" /><path d="M12 3v2.5M12 18.5V21M3 12h2.5M18.5 12H21M5.6 5.6l1.8 1.8M16.6 16.6l1.8 1.8M5.6 18.4l1.8-1.8M16.6 7.4l1.8-1.8" /></> },
  ];
  return (
    <nav className={className} aria-label={t.menu}>
      {tabs.map((tab) => (
        <NavLink key={tab.to} to={tab.to} end={tab.end}>
          <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            {tab.icon}
          </svg>
          <span>{tab.label}</span>
        </NavLink>
      ))}
    </nav>
  );
}

function checkSignupPassword(password: string, confirmPassword: string) {
  const length = password.length >= 8 && password.length <= 200;
  const english = password.length > 0 && /^[\x21-\x7E]+$/.test(password);
  const uppercase = /[A-Z]/.test(password);
  const number = /[0-9]/.test(password);
  const symbol = /[\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E]/.test(password);
  const match = password.length > 0 && password === confirmPassword;
  return {
    length,
    english,
    uppercase,
    number,
    symbol,
    match,
    valid: length && english && uppercase && number && symbol && match,
  };
}

function AuthPage({ mode, onAuth }: { mode: "login" | "signup"; onAuth: (me: Me) => void }) {
  const { t, lang, setLang } = useI18n();
  const navigate = useNavigate();
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [error, setError] = useState("");
  const [apple, setApple] = useState<AppleConfig | null>(null);
  const [appleBusy, setAppleBusy] = useState(false);
  const checks = checkSignupPassword(password, confirmPassword);

  useEffect(() => {
    let active = true;
    void fetchAppleConfig().then((config) => {
      if (active) setApple(config);
    });
    return () => {
      active = false;
    };
  }, []);

  async function continueWithApple() {
    if (!apple) return;
    setError("");
    setAppleBusy(true);
    try {
      const me = await signInWithApple(apple, lang);
      onAuth(me);
      navigate(me.hasProfile ? "/" : "/setup/fasting");
    } catch (err) {
      setError(message(t, err));
    } finally {
      setAppleBusy(false);
    }
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    const form = new FormData(event.currentTarget);
    if (mode === "signup" && !checks.valid) {
      setError(!checks.match && checks.length && checks.english && checks.uppercase && checks.number && checks.symbol ? t.password_mismatch : t.weak_password);
      return;
    }
    try {
      await api(mode === "login" ? "/api/auth/login" : "/api/auth/signup", {
        method: "POST",
        body: JSON.stringify(
          mode === "login"
            ? {
                email: form.get("email"),
                password,
              }
            : {
                email: form.get("email"),
                password,
                confirmPassword,
                language: lang,
              },
        ),
      });
      const me = await api<Me>("/api/auth/me");
      onAuth(me);
      navigate(mode === "signup" || !me.hasProfile ? "/setup/fasting" : "/");
    } catch (err) {
      setError(message(t, err));
    }
  }
  return (
    <main className="shell page auth-page">
      <div className="auth-brand">
        <AppMark />
        <strong>{t.appName}</strong>
        <span className="muted">{t.tagline}</span>
      </div>
      <Form className="card auth-card" onSubmit={submit}>
        <h1>{mode === "login" ? t.login : t.signup}</h1>
        {apple?.enabled && (
          <>
            <button type="button" className="apple-button" onClick={continueWithApple} disabled={appleBusy}>
              <svg className="apple-logo" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false">
                <path
                  fill="currentColor"
                  d="M16.37 12.63c-.02-2.2 1.8-3.26 1.88-3.31-1.02-1.5-2.61-1.7-3.18-1.73-1.35-.14-2.64.8-3.33.8-.69 0-1.75-.78-2.88-.76-1.48.02-2.85.86-3.61 2.19-1.54 2.67-.39 6.63 1.1 8.8.73 1.06 1.6 2.25 2.74 2.21 1.1-.04 1.52-.71 2.85-.71 1.33 0 1.7.71 2.87.69 1.19-.02 1.94-1.08 2.66-2.15.84-1.23 1.19-2.42 1.2-2.48-.03-.01-2.3-.88-2.32-3.5zM14.2 6.17c.6-.74 1.01-1.76.9-2.78-.87.04-1.94.58-2.56 1.31-.55.64-1.04 1.69-.91 2.69.97.07 1.97-.49 2.57-1.22z"
                />
              </svg>
              <span>{t.continueWithApple}</span>
            </button>
            <div className="auth-divider" role="separator"><span>{t.orDivider}</span></div>
          </>
        )}
        <label><span>{t.email}</span><input name="email" type="email" required /></label>
        <label>
          <span>{t.password}</span>
          <input
            name="password"
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            minLength={mode === "signup" ? 8 : 1}
            required
          />
        </label>
        {mode === "signup" && (
          <>
            <label>
              <span>{t.confirmPassword}</span>
              <input
                name="confirmPassword"
                type="password"
                value={confirmPassword}
                onChange={(event) => setConfirmPassword(event.target.value)}
                minLength={8}
                required
              />
            </label>
            <div className="password-rules" role="status" aria-live="polite">
              <strong className="label">{t.passwordRulesTitle}</strong>
              <ul className="checklist">
                <li className={checks.length ? "ok" : ""}>{checks.length ? "✓" : "○"} {t.ruleLength}</li>
                <li className={checks.english ? "ok" : ""}>{checks.english ? "✓" : "○"} {t.ruleEnglish}</li>
                <li className={checks.uppercase ? "ok" : ""}>{checks.uppercase ? "✓" : "○"} {t.ruleUppercase}</li>
                <li className={checks.number ? "ok" : ""}>{checks.number ? "✓" : "○"} {t.ruleNumber}</li>
                <li className={checks.symbol ? "ok" : ""}>{checks.symbol ? "✓" : "○"} {t.ruleSymbol}</li>
                <li className={checks.match ? "ok" : ""}>{checks.match ? "✓" : "○"} {t.ruleMatch}</li>
              </ul>
            </div>
          </>
        )}
        {error && <p className="error">{error}</p>}
        <button type="submit">{mode === "login" ? t.login : t.signup}</button>
        <p>{mode === "login" ? <Link to="/signup">{t.needAccount}</Link> : <Link to="/login">{t.haveAccount}</Link>}</p>
      </Form>
      <div className="segmented auth-lang" role="group" aria-label={t.language}>
        {(["en", "he"] as const).map((option) => (
          <button key={option} type="button" lang={option} aria-pressed={lang === option} onClick={() => setLang(option)}>
            {option === "en" ? "English" : "עברית"}
          </button>
        ))}
      </div>
    </main>
  );
}

/** App mark: the "step down" logo, vector so it stays crisp at any size. */
function AppMark() {
  return (
    <svg className="app-mark" viewBox="0 0 100 100" width="56" height="56" aria-hidden="true">
      <rect width="100" height="100" rx="22" fill="#7CC6FF" />
      <rect x="13" y="24" width="14" height="52" rx="7" fill="#10131A" />
      <rect x="33" y="40" width="14" height="36" rx="7" fill="#10131A" />
      <rect x="53" y="55" width="14" height="21" rx="7" fill="#10131A" />
      <circle cx="80" cy="69" r="7" fill="#10131A" />
    </svg>
  );
}

function FastingSetup({ onDone }: { onDone: () => void }) {
  const { t } = useI18n();
  const navigate = useNavigate();
  const [wants, setWants] = useState<boolean | null>(null);
  const [lengthHours, setLengthHours] = useState(16);
  const [startHour, setStartHour] = useState(20);
  const [error, setError] = useState("");
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    try {
      await api("/api/fasting", {
        method: "PUT",
        body: JSON.stringify({
          enabled: wants === true,
          lengthHours,
          startHour,
        }),
      });
      onDone();
      navigate("/setup/profile");
    } catch (err) {
      setError(message(t, err));
    }
  }
  return (
    <main className="shell page">
      <Form className="card" onSubmit={save}>
        <p className="step-label">{t.stepOf.replace("{n}", "1")}</p>
        <h1>{t.fastingQuestion}</h1>
        <p className="muted">{t.fastingQuestionHint}</p>
        <div className="segmented segmented-lg" role="radiogroup" aria-label={t.fastingQuestion}>
          <button type="button" role="radio" aria-checked={wants === true} aria-pressed={wants === true} onClick={() => setWants(true)}>{t.yes}</button>
          <button type="button" role="radio" aria-checked={wants === false} aria-pressed={wants === false} onClick={() => setWants(false)}>{t.no}</button>
        </div>
        <div className={wants ? "reveal open" : "reveal"} inert={!wants}>
          <div className="reveal-inner">
            <MenuField
              label={t.fastingLength}
              value={String(lengthHours)}
              onChange={(next) => setLengthHours(Number(next))}
              options={[
                { value: "12", label: `12 ${t.hours}` },
                { value: "14", label: `14 ${t.hours}` },
                { value: "16", label: `16 ${t.hours}` },
              ]}
            />
            <HourField name="startHour" label={t.startHour} value={startHour} onChange={setStartHour} />
            <p className="muted">{t.endHour}: {hourLabel((startHour + lengthHours) % 24)}</p>
          </div>
        </div>
        {error && <p className="error">{error}</p>}
        <button type="submit" disabled={wants == null}>{t.continue}</button>
      </Form>
    </main>
  );
}

function ProfileSetup({ onDone }: { onDone: (me: Me) => void }) {
  const { t } = useI18n();
  const navigate = useNavigate();
  const [error, setError] = useState("");
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const dateOfBirth = String(form.get("dateOfBirth") ?? "");
    if (!form.get("sex")) {
      setError(t.chooseSex);
      return;
    }
    if (!dateOfBirth) {
      setError(t.chooseDate);
      return;
    }
    try {
      const dailyGoalRaw = String(form.get("dailyGoalKcal") ?? "").trim().replace(",", ".");
      const dailyGoalKcal = Math.round(Number(dailyGoalRaw));
      await api("/api/profile", {
        method: "PUT",
        body: JSON.stringify({
          sex: form.get("sex"),
          dateOfBirth,
          heightCm: Number(form.get("heightCm")),
          weightKg: Number(form.get("weightKg")),
          activity: form.get("activity"),
          weeklyPace: form.get("weeklyPace"),
          customGoalKcal: Number.isFinite(dailyGoalKcal) ? dailyGoalKcal : null,
        }),
      });
      const me = await api<Me>("/api/auth/me");
      onDone(me);
      navigate("/");
    } catch (err) {
      setError(message(t, err));
    }
  }
  return (
    <main className="shell page">
      <Form className="card" onSubmit={save}>
        <p className="step-label">{t.stepOf.replace("{n}", "2")}</p>
        <h1>{t.profileTitle}</h1>
        <ProfileFields />
        {error && <p className="error">{error}</p>}
        <button type="submit">{t.save}</button>
      </Form>
    </main>
  );
}

const MEAL_COLOR: Record<MealCategory, string> = {
  breakfast: "var(--accent-primary)",
  lunch: "var(--accent-energy)",
  dinner: "var(--accent-success)",
  snacks: "var(--label-secondary)",
};

function Today({ canVerifyFoods, onFastingChange }: { canVerifyFoods: boolean; onFastingChange: () => void }) {
  const { t } = useI18n();
  const [loadedDay, setDay] = useState<DayResponse | null>(() => peek<DayResponse>("/api/days/today"));
  // Removed entry waiting out its Undo window; deleted on the server afterwards.
  const [pendingRemoval, setPendingRemoval] = useState<DayEntry | null>(null);
  const removalTimer = useRef<number | null>(null);
  const [fasting, setFasting] = useState<FastingState | null>(() => peek<FastingState>("/api/fasting"));
  const [now, setNow] = useState(Date.now());
  const [loggingMeal, setLoggingMeal] = useState<MealCategory | null>(null);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Food[] | null>(null);
  const [recent, setRecent] = useState<RecentFood[]>([]);
  const [lookup, setLookup] = useState<{ status: string; food: Food | null; foods: Food[]; suggestion?: FoodSuggestion | null } | null>(null);
  const [picked, setPicked] = useState<Food | null>(null);
  const [amount, setAmount] = useState("100");
  const [error, setError] = useState("");
  const [params, setParams] = useSearchParams();
  const searchInput = useRef<HTMLInputElement>(null);
  const scrollToPicked = useRef(false);
  const trimmedQuery = query.trim();
  const barcodeQuery = /^\d{6,}$/.test(trimmedQuery);

  async function reload() {
    const nextDay = await api<DayResponse>("/api/days/today");
    setDay(nextDay);
    try {
      setFasting(await api<FastingState>("/api/fasting"));
    } catch (err) {
      setError(message(t, err));
    }
  }

  useEffect(() => {
    reload().catch((err) => setError(message(t, err)));
  }, [t]);

  useEffect(() => {
    if (!fasting?.running) return;
    const tick = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(tick);
  }, [fasting?.running]);

  async function toggleFast() {
    if (!fasting?.enabled) return;
    try {
      const next = await api<FastingState>(fasting.running ? "/api/fasting/stop" : "/api/fasting/start", { method: "POST" });
      setFasting(next);
      setError("");
      onFastingChange();
    } catch (err) {
      setError(message(t, err));
    }
  }

  function loadRecent() {
    api<{ foods: RecentFood[] }>("/api/foods/recent").then((result) => setRecent(result.foods)).catch(() => {});
  }

  // Coming back from "New food" / "Edit": reopen that meal with the food picked.
  useEffect(() => {
    const meal = params.get("meal");
    const foodId = params.get("food");
    if (!meal || !foodId || !(MEALS as readonly string[]).includes(meal)) return;
    setParams({}, { replace: true });
    api<{ food: Food }>(`/api/foods/${encodeURIComponent(foodId)}`)
      .then((result) => {
        scrollToPicked.current = true;
        setLoggingMeal(meal as MealCategory);
        setPicked(result.food);
        setAmount("100");
        loadRecent();
      })
      .catch((err) => setError(message(t, err)));
  }, [params, setParams, t]);

  useEffect(() => {
    if (!loggingMeal || trimmedQuery.length < 2) {
      setResults(null);
      return;
    }
    let active = true;
    const id = window.setTimeout(() => {
      api<{ foods: Food[] }>(`/api/foods/search?q=${encodeURIComponent(trimmedQuery)}`)
        .then((result) => active && setResults(result.foods))
        .catch((err) => active && setError(message(t, err)));
    }, 250);
    return () => {
      active = false;
      window.clearTimeout(id);
    };
  }, [loggingMeal, trimmedQuery, t]);

  function openLog(meal: MealCategory) {
    const opening = loggingMeal !== meal;
    setLoggingMeal(opening ? meal : null);
    setQuery("");
    setResults(null);
    setLookup(null);
    setPicked(null);
    setAmount("100");
    setError("");
    if (opening) {
      loadRecent();
      window.setTimeout(() => searchInput.current?.focus({ preventScroll: true }), 50);
    }
  }

  function pick(food: Food, lastAmount?: number) {
    setPicked(food);
    setAmount(String(lastAmount ?? 100));
    setError("");
  }

  async function findFood(event: FormEvent) {
    event.preventDefault();
    setError("");
    if (!barcodeQuery) {
      if (results?.length === 1) pick(results[0]);
      return;
    }
    try {
      const result = await api<{ status: string; food: Food | null; foods: Food[]; suggestion?: FoodSuggestion | null }>(`/api/foods/barcode/${encodeURIComponent(trimmedQuery)}`);
      setLookup(result);
      if (result.food) pick(result.food);
    } catch (err) {
      setError(message(t, err));
    }
  }

  async function addFood(event: FormEvent) {
    event.preventDefault();
    if (!picked || !loggingMeal) return;
    try {
      await api(`/api/days/today/entries`, {
        method: "POST",
        body: JSON.stringify({ foodId: picked.id, amount: Number(amount.replace(",", ".")), meal: loggingMeal }),
      });
      setLoggingMeal(null);
      setLookup(null);
      setPicked(null);
      setQuery("");
      await reload();
    } catch (err) {
      setError(message(t, err));
    }
  }

  function suggestionLink(meal: MealCategory, suggestion: FoodSuggestion) {
    const search = new URLSearchParams({ meal, source: "online" });
    for (const [key, value] of Object.entries(suggestion)) search.set(key, String(value));
    return `/foods/new?${search}`;
  }

  function newFoodLink(meal: MealCategory) {
    const search = new URLSearchParams({ meal });
    if (barcodeQuery) search.set("barcode", trimmedQuery);
    else if (trimmedQuery) search.set("name", trimmedQuery);
    return `/foods/new?${search}`;
  }

  async function commitRemoval(entry: DayEntry) {
    if (removalTimer.current != null) window.clearTimeout(removalTimer.current);
    removalTimer.current = null;
    try {
      await api(`/api/days/today/entries/${entry.id}`, { method: "DELETE" });
      await reload();
    } catch (err) {
      setError(message(t, err));
    } finally {
      setPendingRemoval((current) => (current?.id === entry.id ? null : current));
    }
  }

  function remove(entry: DayEntry) {
    // Only one Undo at a time: an earlier removal is committed now.
    if (pendingRemoval) void commitRemoval(pendingRemoval);
    setPendingRemoval(entry);
    removalTimer.current = window.setTimeout(() => void commitRemoval(entry), 6000);
  }

  function undoRemoval() {
    if (removalTimer.current != null) window.clearTimeout(removalTimer.current);
    removalTimer.current = null;
    setPendingRemoval(null);
  }

  // Leaving the page commits a pending removal instead of dropping it.
  const pendingRef = useRef<DayEntry | null>(null);
  pendingRef.current = pendingRemoval;
  useEffect(() => () => {
    const entry = pendingRef.current;
    if (removalTimer.current != null) window.clearTimeout(removalTimer.current);
    if (entry) void api(`/api/days/today/entries/${entry.id}`, { method: "DELETE" }).catch(() => {});
  }, []);

  const day: DayResponse | null = loadedDay && pendingRemoval
    ? {
        ...loadedDay,
        entries: loadedDay.entries.filter((entry) => entry.id !== pendingRemoval.id),
        totals: { ...loadedDay.totals, calories: Math.max(0, loadedDay.totals.calories - pendingRemoval.calories) },
      }
    : loadedDay;

  const remaining = day ? day.goalKcal - day.totals.calories : 0;
  const over = day ? day.totals.calories > day.goalKcal : false;
  const slices = MEALS.map((meal) => ({
    meal,
    color: MEAL_COLOR[meal],
    calories: day?.entries.filter((entry) => entry.meal === meal).reduce((sum, entry) => sum + entry.calories, 0) ?? 0,
  }));

  return (
    <>
      {day && (
        <section className="card today-summary">
          <h1>{t.today}</h1>
          <div className="today-hero">
            <div className="ring-wrap">
              <div className="ring-shift">
                <CalorieRing slices={slices} goal={day.goalKcal} over={over} />
              </div>
              <div className="ring-center" role="img" aria-label={`${formatKcal(Math.abs(remaining))} ${t.kcal} ${over ? t.missed : t.remaining}`}>
                <b className={over ? "over" : undefined} aria-hidden="true"><AnimatedNumber value={remaining} from={day.goalKcal} /></b>
                <span aria-hidden="true">{t.remaining}</span>
              </div>
            </div>
            <div className="hero-side">
              <div className="pair"><span>{t.goal}</span><b>{formatKcal(day.goalKcal)} {t.kcal}</b></div>
              <div className="pair"><span>{t.eaten}</span><b>{formatKcal(day.totals.calories)} {t.kcal}</b></div>
              <p className="muted">{dayStatusLabel(t, day.status)}</p>
            </div>
          </div>
          {day.healthSynced && (
            <div className="today-health">
              <ProgressRow label={t.healthSteps} value={day.steps} goal={day.stepGoal} unit="" />
              <ProgressRow label={t.healthExercise} value={day.exerciseMinutes} goal={day.exerciseGoalMinutes} unit={t.healthMinutes} />
            </div>
          )}
          {slices.some((slice) => slice.calories > 0) && (
            <div className="meal-legend">
              {slices.filter((slice) => slice.calories > 0).map((slice) => (
                <span key={slice.meal}><i className="meal-swatch" style={{ background: slice.color }} />{mealLabel(t, slice.meal)}</span>
              ))}
            </div>
          )}
        </section>
      )}
      {fasting && <TodayFast fasting={fasting} now={now} onToggle={toggleFast} />}
      {error && !loggingMeal && <p className="error">{error}</p>}
      {MEALS.map((meal) => {
        const mealEntries = day?.entries.filter((entry) => entry.meal === meal) ?? [];
        const mealKcal = mealEntries.reduce((sum, entry) => sum + entry.calories, 0);
        const logging = loggingMeal === meal;
        return (
          <section className="card meal-card" key={meal}>
            <div className="meal-head">
              <h2>{mealLabel(t, meal)}</h2>
              <span className={mealKcal > 0 ? "meal-total" : "meal-total zero"}>{formatKcal(mealKcal)} {t.kcal}</span>
            </div>
            {mealEntries.length === 0 && <p className="muted meal-empty">{t.emptyMeal}</p>}
            {mealEntries.map((entry) => (
              <div className="entry" key={entry.id}>
                <div>
                  <strong>{entry.name}</strong>
                  <div className="muted">{entry.amount} {entry.basis === "solid" ? t.grams : t.milliliters}</div>
                </div>
                <div>
                  <span className="kcal">{formatKcal(entry.calories)}</span>
                  <button className="quiet" type="button" onClick={() => remove(entry)}>{t.delete}</button>
                </div>
              </div>
            ))}
            <button type="button" className={logging ? "secondary meal-log" : "meal-log"} onClick={() => openLog(meal)}>
              {logging ? t.cancel : t.log}
            </button>
            <div className={logging && !picked ? "reveal open" : "reveal"} inert={!logging || Boolean(picked)}>
              <div className="reveal-inner">
                <Form onSubmit={findFood} className="food-add" role="search">
                  <input
                    ref={logging ? searchInput : undefined}
                    type="search"
                    value={query}
                    onChange={(event) => {
                      setQuery(event.target.value);
                      setLookup(null);
                    }}
                    placeholder={t.searchFoods}
                    aria-label={t.searchFoods}
                    enterKeyHint="search"
                  />
                  {barcodeQuery && <button type="submit">{t.lookUp}</button>}
                </Form>
                {trimmedQuery.length < 2 && recent.length > 0 && (
                  <div className="food-list">
                    <h3 className="label">{t.recentFoods}</h3>
                    {recent.map((food) => (
                      <FoodRow key={food.id} food={food} detail={`${food.lastAmount} ${unitLabel(t, food)}`} onPick={() => pick(food, food.lastAmount)} />
                    ))}
                  </div>
                )}
                {results && results.length > 0 && !lookup && (
                  <div className="food-list">
                    {results.map((food) => (
                      <FoodRow key={food.id} food={food} onPick={() => pick(food)} />
                    ))}
                  </div>
                )}
                {results && results.length === 0 && !lookup && (
                  <p className="muted">{t.noMatches} <Link to={newFoodLink(meal)}>{t.createFood}</Link></p>
                )}
                {lookup?.status === "none" && (
                  <p>{t.noFood} <Link to={newFoodLink(meal)}>{t.createFood}</Link></p>
                )}
                {lookup?.status === "external" && lookup.suggestion && (
                  <p>
                    {t.foundOnline}: <strong>{lookup.suggestion.name}</strong>{" "}
                    <Link to={suggestionLink(meal, lookup.suggestion)}>{t.reviewAndSave}</Link>
                  </p>
                )}
                {lookup?.status === "list" && (
                  <div className="food-list">
                    <h3 className="label">{t.chooseFood}</h3>
                    {lookup.foods.map((food) => (
                      <FoodRow key={food.id} food={food} onPick={() => pick(food)} />
                    ))}
                  </div>
                )}
              </div>
            </div>
            {logging && picked && (
              <Form
                className="rise"
                onSubmit={addFood}
                ref={(node) => {
                  if (node && scrollToPicked.current) {
                    scrollToPicked.current = false;
                    node.scrollIntoView({ block: "center", behavior: prefersReducedMotion() ? "auto" : "smooth" });
                  }
                }}
              >
                <p><strong>{picked.name}</strong>{picked.owned ? ` · ${t.personal}` : ""}{picked.verified ? ` · ${t.verified}` : ""}</p>
                <p className="muted">{picked.calories} {t.kcal} / 100 {unitLabel(t, picked)}</p>
                <label><span>{t.amount} ({unitLabel(t, picked)})</span>
                  <div className="amount-field">
                    <input value={amount} onChange={(event) => setAmount(event.target.value)} inputMode="decimal" required autoFocus onFocus={(event) => event.currentTarget.select()} />
                    <output className="kcal" aria-live="polite">= {portionKcal(picked, amount)} {t.kcal}</output>
                  </div>
                </label>
                <div className="fast-actions">
                  <button type="submit">{t.add}</button>
                  <button type="button" className="secondary" onClick={() => setPicked(null)}>{t.back}</button>
                  <Link className="secondary" to={`/foods/${picked.id}?meal=${meal}`}>{t.edit}</Link>
                  {canVerifyFoods && picked.published && !picked.verified && (
                    <button type="button" className="secondary" onClick={async () => {
                      const result = await api<{ food: Food }>(`/api/foods/${picked.id}/verify`, { method: "POST" });
                      setPicked(result.food);
                    }}>{t.verify}</button>
                  )}
                </div>
              </Form>
            )}
            {logging && error && <p className="error">{error}</p>}
          </section>
        );
      })}
      {pendingRemoval && createPortal(
        // Portal: the animated .page has a transform, which would trap position: fixed.
        <div className="toast rise" role="status">
          <span>{t.removedEntry.replace("{name}", pendingRemoval.name)}</span>
          <button type="button" className="toast-action" onClick={undoRemoval}>{t.undo}</button>
        </div>,
        document.body,
      )}
    </>
  );
}

type RecentFood = Food & { lastAmount: number };

function unitLabel(t: Copy, food: Pick<Food, "basis">) {
  return food.basis === "solid" ? t.grams : t.milliliters;
}

function portionKcal(food: Pick<Food, "calories">, amount: string) {
  const value = Number(amount.trim().replace(",", "."));
  if (!Number.isFinite(value) || value <= 0) return 0;
  return Math.round((food.calories * value) / 100);
}

function FoodRow({ food, detail, onPick }: { food: Food; detail?: string; onPick: () => void }) {
  const { t } = useI18n();
  return (
    <button type="button" className="food-row" onClick={onPick}>
      <span className="food-row-name">
        <strong>{food.name}</strong>
        <span className="muted">
          {detail ?? `${food.calories} ${t.kcal} / 100 ${unitLabel(t, food)}`}
          {food.verified ? ` · ${t.verified}` : ""}
        </span>
      </span>
      <span className="food-row-add" aria-hidden="true">+</span>
    </button>
  );
}

function dayStatusLabel(t: Copy, status: DayStatus) {
  switch (status) {
    case "met": return t.success;
    case "over": return t.missed;
    case "on_track": return t.onTrack;
    default: return t.estimate;
  }
}

function themeLabel(t: Copy, mode: ThemeMode) {
  switch (mode) {
    case "system": return t.themeSystem;
    case "light": return t.themeLight;
    case "dark": return t.themeDark;
  }
}

function mealLabel(t: Copy, meal: MealCategory) {
  switch (meal) {
    case "breakfast": return t.breakfast;
    case "lunch": return t.lunch;
    case "dinner": return t.dinner;
    case "snacks": return t.snacks;
  }
}

function FastingPage({ onFastingChange }: { onFastingChange: () => void }) {
  const { t } = useI18n();
  const [fasting, setFasting] = useState<FastingState | null>(() => peek<FastingState>("/api/fasting"));
  const [error, setError] = useState("");
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    api<FastingState>("/api/fasting").then(setFasting).catch((err) => setError(message(t, err)));
  }, [t]);

  useEffect(() => {
    const tick = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(tick);
  }, []);

  async function toggle() {
    if (!fasting) return;
    try {
      const next = await api<FastingState>(fasting.running ? "/api/fasting/stop" : "/api/fasting/start", { method: "POST" });
      setFasting(next);
      setError("");
      onFastingChange();
    } catch (err) {
      setError(message(t, err));
    }
  }

  const left = fasting?.running && fasting.endsAt ? Math.max(0, new Date(fasting.endsAt).getTime() - now) : 0;
  const totalMs = ((fasting?.lengthHoursRunning ?? fasting?.lengthHours) || 0) * 60 * 60 * 1000;
  const fastRatio = totalMs > 0 ? (totalMs - left) / totalMs : 0;
  const sessions = fasting?.sessions ?? [];

  return (
    <>
      <section className={fasting?.running ? "card fast-card running" : "card fast-card"}>
        <h1>{t.fasting}</h1>
        {fasting?.enabled ? (
          <div className="fast-hero">
            {fasting.running && fasting.endsAt && (
              <>
                <div className="fast-ring-hero">
                  <FastRing ratio={fastRatio} color="var(--fast-on)" />
                  <p className="fast-count rise">{formatDuration(left)}</p>
                </div>
                <p className="muted">{t.approximateEnd}: {formatJerusalemTime(fasting.endsAt)}</p>
              </>
            )}
            {!fasting.running && (
              <p className="muted">{t.scheduled}: <span className="scheduled">{hourLabel(fasting.startHour)} – {hourLabel(fasting.endHour)}</span> · <span className="scheduled">{fasting.lengthHours} {t.hours}</span></p>
            )}
            <button className="fast-go" type="button" onClick={toggle}>{fasting.running ? t.stopFast : t.startFast}</button>
          </div>
        ) : fasting && <p className="muted">{t.fasting_disabled} <Link to="/settings/fasting">{t.settings}</Link></p>}
        {error && <p className="error">{error}</p>}
      </section>
      <section className="card">
        <h2>{t.fastLog}</h2>
        {sessions.length === 0 ? <p className="muted">{t.noFasts}</p> : (
          <div className="table-wrap">
            <table className="fast-log">
              <thead>
                <tr>
                  <th>{t.date}</th>
                  <th>{t.length}</th>
                  <th>{t.start}</th>
                  <th>{t.end}</th>
                </tr>
              </thead>
              <tbody>
                {sessions.map((session) => (
                  <tr key={session.id}>
                    <td>{formatJerusalemDay(session.startedAt)}</td>
                    <td>{fastLengthLabel(session)}</td>
                    <td>{formatJerusalemTime(session.startedAt)}</td>
                    <td>{fastEndLabel(session, t.approx)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </>
  );
}

function fastLengthLabel(session: FastingSession): string {
  if (session.durationMinutes == null) return `${session.lengthHours}h`;
  const hours = Math.floor(session.durationMinutes / 60);
  const minutes = session.durationMinutes % 60;
  return `${hours}h ${String(minutes).padStart(2, "0")}m`;
}

function fastEndLabel(session: FastingSession, approximate: string): string {
  const iso = session.running ? session.endsAt : session.endedAt;
  if (!iso) return "—";
  const time = formatJerusalemTime(iso);
  const start = jerusalemParts(new Date(session.startedAt));
  const end = jerusalemParts(new Date(iso));
  const sameDay = start.year === end.year && start.month === end.month && start.day === end.day;
  const label = sameDay ? time : `${time} · ${formatJerusalemDay(iso)}`;
  return session.running ? `${label} ${approximate}` : label;
}

function CalorieRing({ slices, goal, over }: { slices: { color: string; calories: number }[]; goal: number; over: boolean }) {
  const radius = 52;
  const circumference = 2 * Math.PI * radius;
  const eaten = slices.reduce((sum, slice) => sum + slice.calories, 0);
  const basis = over && eaten > 0 ? eaten : goal;
  const parts = basis > 0 ? slices.filter((slice) => slice.calories > 0) : [];
  const reduce = prefersReducedMotion();
  const [progress, setProgress] = useState(reduce ? 1 : 0);
  useEffect(() => {
    if (reduce) {
      setProgress(1);
      return;
    }
    setProgress(0);
    const frame = requestAnimationFrame(() => setProgress(1));
    return () => cancelAnimationFrame(frame);
  }, [eaten, goal, over, reduce]);
  const gap = parts.length > 1 ? 8 : 0;
  let cursor = 0;
  const arcs = parts.map((slice) => {
    const full = (slice.calories / basis) * circumference * progress;
    const separated = full > gap + 2;
    const length = separated ? full - gap : full;
    const start = cursor + (separated ? gap / 2 : 0);
    cursor += full;
    return { color: slice.color, length, start };
  });
  return (
    <svg className="ring" viewBox="0 0 120 120" aria-hidden="true">
      <circle className="ring-track" cx="60" cy="60" r={radius} />
      {arcs.map((arc) => (
        <circle
          key={arc.color}
          className="ring-slice"
          cx="60"
          cy="60"
          r={radius}
          strokeDasharray={`${arc.length} ${circumference}`}
          style={{ stroke: arc.color, strokeDashoffset: -arc.start }}
        />
      ))}
    </svg>
  );
}

function FastRing({ ratio, color = "var(--accent-energy)" }: { ratio: number; color?: string }) {
  const radius = 52;
  const circumference = 2 * Math.PI * radius;
  const clamped = Math.min(Math.max(ratio, 0), 1);
  return (
    <svg className="ring" viewBox="0 0 120 120" aria-hidden="true">
      <circle className="ring-track" cx="60" cy="60" r={radius} />
      {/* No arc at 0%: a round line cap would draw a stray dot. */}
      {clamped > 0 && (
        <circle
          className="ring-slice"
          cx="60"
          cy="60"
          r={radius}
          strokeDasharray={`${circumference * clamped} ${circumference}`}
          style={{ stroke: color, strokeDashoffset: 0 }}
        />
      )}
    </svg>
  );
}

function TodayFast({ fasting, now, onToggle }: { fasting: FastingState; now: number; onToggle: () => void }) {
  const { t } = useI18n();
  const running = Boolean(fasting.running && fasting.endsAt);
  const totalMs = ((fasting.lengthHoursRunning ?? fasting.lengthHours) || 0) * 60 * 60 * 1000;
  const left = running ? Math.max(0, new Date(fasting.endsAt!).getTime() - now) : 0;
  const ratio = running && totalMs > 0 ? Math.min(1, Math.max(0, (totalMs - left) / totalMs)) : 0;
  return (
    <section className="card today-fast">
      <div className="today-fast-main">
        <div className="fast-mini">
          <FastRing ratio={ratio} />
        </div>
        <div className="today-fast-copy">
          <h2>{t.fasting}</h2>
          {running && fasting.endsAt ? (
            <>
              <p className="today-fast-time">{formatDuration(left)}</p>
              <p className="muted">{t.approximateEnd}: {formatJerusalemTime(fasting.endsAt)}</p>
            </>
          ) : fasting.enabled ? (
            <p className="muted">{t.scheduled}: <span className="scheduled">{hourLabel(fasting.startHour)} – {hourLabel(fasting.endHour)}</span> · <span className="scheduled">{fasting.lengthHours} {t.hours}</span></p>
          ) : (
            <p className="muted">{t.fasting_disabled} <Link to="/settings/fasting">{t.settings}</Link></p>
          )}
        </div>
      </div>
      <div className="today-fast-actions">
        {fasting.enabled && (
          <button className={fasting.running ? "secondary" : "energy"} type="button" onClick={onToggle}>{fasting.running ? t.stopFast : t.startFast}</button>
        )}
        <Link className="secondary" to="/fasting">{t.moreDetails}</Link>
      </div>
    </section>
  );
}

function ProgressRow({ label, value, goal, unit }: { label: string; value: number; goal: number; unit: string }) {
  const ratio = goal > 0 ? Math.min(value / goal, 1) : 0;
  return (
    <div className="progress-row">
      <div className="progress-head">
        <span>{label}</span>
        <b>{value.toLocaleString()} / {goal.toLocaleString()}{unit ? ` ${unit}` : ""}</b>
      </div>
      <div className={ratio >= 1 ? "progress-bar done" : "progress-bar"} role="progressbar" aria-label={label} aria-valuemin={0} aria-valuemax={goal} aria-valuenow={value}>
        <i style={{ width: `${ratio * 100}%` }} />
      </div>
    </div>
  );
}

function WeekPage() {
  const { t } = useI18n();
  const [params, setParams] = useSearchParams();
  const on = params.get("on") ?? "";
  const weekPath = `/api/weeks${on ? `?on=${on}` : ""}`;
  const [week, setWeek] = useState<WeekResponse | null>(() => peek<WeekResponse>(weekPath));
  const [error, setError] = useState("");
  useEffect(() => {
    const cached = peek<WeekResponse>(weekPath);
    if (cached) setWeek(cached);
    api<WeekResponse>(weekPath).then(setWeek).catch((err) => setError(message(t, err)));
  }, [weekPath, t]);
  if (!week) return error ? <p className="error">{error}</p> : <p className="muted loading">…</p>;
  const today = todayJerusalemDay();
  const isCurrentWeek = addDays(week.sunday, 7) > today;
  const countedDays = week.days.filter((day) => !day.future && day.calories > 0);
  const byDay = new Map(week.days.map((day) => [day.day, day]));
  const dailyGoal = Math.round(week.goalKcal / 7);
  const chartDays = Array.from({ length: 7 }, (_, index) => {
    const date = addDays(week.sunday, index);
    const row = byDay.get(date);
    return { date, calories: Math.round(row?.calories ?? 0), goal: row?.goalKcal ?? dailyGoal, status: row?.status ?? (date > today ? "future" : "empty") };
  });
  const scale = Math.max(dailyGoal * 1.25, ...chartDays.map((day) => day.calories), 1);
  return (
    <section className="card rise" key={week.sunday}>
      <div className="week-head">
        <div>
          <h1>{t.week}</h1>
          <p className="muted week-range">{formatWeekRange(week.sunday)}</p>
        </div>
        <div className="week-nav">
          <button type="button" className="secondary icon-button" aria-label={t.previousWeek} onClick={() => setParams({ on: addDays(week.sunday, -7) })}>
            <Chevron back />
          </button>
          <button type="button" className="secondary icon-button" aria-label={t.nextWeek} disabled={isCurrentWeek} onClick={() => setParams({ on: addDays(week.sunday, 7) })}>
            <Chevron />
          </button>
        </div>
      </div>
      <div className="week-chart" role="img" aria-label={chartDays.map((day) => `${formatWeekday(day.date)} ${day.calories} ${t.kcal}`).join(", ")}>
        <i className="week-goal" style={{ bottom: `${(dailyGoal / scale) * 100}%` }} aria-hidden="true" />
        {chartDays.map((day) => (
          <div className={`week-bar ${day.status}${day.date === today ? " today" : ""}`} key={day.date}>
            <div className="week-bar-track">
              <i style={{ height: `${(day.calories / scale) * 100}%` }} />
            </div>
            <span>{formatWeekday(day.date)}</span>
          </div>
        ))}
      </div>
      <div className="stats">
        <div className="stat"><span>{t.calorieIntake}</span><b>{formatKcal(week.calorieIntake)}<small> / {formatKcal(week.goalKcal)}</small></b></div>
        <div className="stat"><span>{t.successCount}</span><b>{week.successCount}</b></div>
        <div className="stat"><span>{t.weightChange}</span><b>{week.weightChangeKg == null ? "—" : `${week.weightChangeKg > 0 ? "+" : ""}${week.weightChangeKg} ${t.kg}`}</b></div>
      </div>
      {week.weightChangeKg == null && <p className="muted">{t.noWeightChange}</p>}
      {countedDays.map((day) => (
        <div className="week-day" key={day.day}>
          <span>{formatDayLabel(day.day)}</span>
          <span>{formatKcal(day.calories)} / {formatKcal(day.goalKcal)}</span>
          <span className={`status-${day.status}`}>{dayStatusLabel(t, day.status)}</span>
          {day.steps != null && (
            <span className="week-day-health">
              {t.healthSteps} {day.steps.toLocaleString()} · {t.healthExercise} {day.exerciseMinutes ?? 0} {t.healthMinutes}
            </span>
          )}
        </div>
      ))}
    </section>
  );
}

/** Whole kcal with thousands separators (calories are stored with decimals). */
function formatKcal(value: number): string {
  return Math.round(value).toLocaleString(document.documentElement.lang === "he" ? "he-IL" : "en-US");
}

function WeightPage() {
  const { t } = useI18n();
  const [weights, setWeights] = useState<WeightPoint[]>(() => peek<{ weights: WeightPoint[] }>("/api/weights")?.weights ?? []);
  const [error, setError] = useState("");
  async function load() {
    const data = await api<{ weights: WeightPoint[] }>("/api/weights");
    setWeights(data.weights);
  }
  useEffect(() => { load().catch((err) => setError(message(t, err))); }, [t]);
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = event.currentTarget;
    const data = new FormData(form);
    const loggedAt = String(data.get("loggedAt") || "");
    try {
      await api("/api/weights", {
        method: "POST",
        body: JSON.stringify({
          weightKg: readNutrient(data.get("weightKg")),
          loggedAt: loggedAt ? new Date(loggedAt).toISOString() : undefined,
        }),
      });
      form.reset();
      setError("");
      await load();
    } catch (err) {
      setError(message(t, err));
    }
  }
  return (
    <>
      <Form className="card" onSubmit={save}>
        <h1>{t.weight}</h1>
        <label><span>{t.weightKg}</span><input name="weightKg" inputMode="decimal" pattern="\d+([.,]\d+)?" required /></label>
        <label><span>{t.loggedAt}</span><input name="loggedAt" type="datetime-local" /></label>
        {error && <p className="error">{error}</p>}
        <button type="submit">{t.logWeight}</button>
      </Form>
      <section className="card">
        {weights.length === 0 ? <p className="muted">{t.graphEmpty}</p> : <WeightGraph weights={weights} />}
        {weights.map((point) => (
          <div className="entry" key={point.id}>
            <span>
              {formatJerusalem(point.loggedAt)}
              <span className="source-chip">{point.source === "health" ? t.healthSource : t.manualSource}</span>
            </span>
            <strong>{point.weightKg}</strong>
          </div>
        ))}
      </section>
    </>
  );
}

function WeightGraph({ weights }: { weights: WeightPoint[] }) {
  const times = weights.map((point) => new Date(point.loggedAt).getTime());
  const values = weights.map((point) => point.weightKg);
  const minT = Math.min(...times);
  const maxT = Math.max(...times);
  const minV = Math.min(...values);
  const maxV = Math.max(...values);
  const width = 640;
  const height = 220;
  const plotted = weights.map((point) => {
    const x = maxT === minT ? width / 2 : ((new Date(point.loggedAt).getTime() - minT) / (maxT - minT)) * (width - 24) + 12;
    const y = maxV === minV ? height / 2 : height - 16 - ((point.weightKg - minV) / (maxV - minV)) * (height - 32);
    return { id: point.id, x, y, source: point.source };
  });
  const points = plotted.map((point) => `${point.x},${point.y}`).join(" ");
  return (
    <svg viewBox={`0 0 ${width} ${height}`} width="100%" role="img">
      <polyline className="graph-line" pathLength={1} fill="none" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" points={points} />
      {plotted.map((point) => (
        <circle className={point.source === "health" ? "graph-dot health" : "graph-dot"} key={point.id} cx={point.x} cy={point.y} r="4" />
      ))}
    </svg>
  );
}

function SettingsPage({ me, setMe, onFastingChange, onLogout }: { me: Me; setMe: (me: Me) => void; onFastingChange: () => void; onLogout: () => void }) {
  const { t, setLang } = useI18n();
  const { section } = useParams();
  const navigate = useNavigate();
  const { mode: themeMode, setMode: setThemeMode } = useTheme();
  const cachedProfile = peek<{ profile: Profile }>("/api/profile");
  const cachedFasting = peek<FastingState>("/api/fasting");
  const [profile, setProfile] = useState<Profile | null>(cachedProfile?.profile ?? null);
  const [fasting, setFasting] = useState<FastingState | null>(cachedFasting);
  const [fastingEnabledDraft, setFastingEnabledDraft] = useState(cachedFasting?.enabled ?? false);
  const [reminderOffsets, setReminderOffsets] = useState<ReminderOffset[]>(cachedFasting?.reminderOffsets ?? [0]);
  const [autoPublish, setAutoPublish] = useState(me.user.autoPublishFoods);
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [passwordStatus, setPasswordStatus] = useState("");
  const [passwordError, setPasswordError] = useState("");
  const [health, setHealth] = useState<AppleHealthState | null>(() => peek<AppleHealthState>("/api/apple-health"));
  const [error, setError] = useState("");
  const pwChecks = checkSignupPassword(newPassword, confirmPassword);
  const canReadHealth = me.permissions.includes("appleHealth:read");
  useEffect(() => {
    Promise.all([
      api<{ profile: Profile; suggestedGoalKcal: number | null }>("/api/profile"),
      api<FastingState>("/api/fasting"),
    ]).then(([profileResponse, fastingResponse]) => {
      setProfile(profileResponse.profile);
      setFasting(fastingResponse);
      setFastingEnabledDraft(fastingResponse.enabled);
      setReminderOffsets(fastingResponse.reminderOffsets ?? [0]);
    }).catch((err) => setError(message(t, err)));
  }, [t]);
  useEffect(() => {
    if (!canReadHealth) return;
    api<AppleHealthState>("/api/apple-health").then(setHealth).catch(() => setHealth(null));
  }, [canReadHealth]);
  async function saveHealth(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    try {
      const next = await api<AppleHealthState>("/api/apple-health/settings", {
        method: "PUT",
        body: JSON.stringify({
          exerciseGoalMinutes: Number(form.get("exerciseGoalMinutes")),
          stepGoal: Number(form.get("stepGoal")),
        }),
      });
      setHealth(next);
      setError("");
      navigate("/settings");
    } catch (err) {
      setError(message(t, err));
    }
  }
  async function saveProfile(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const dateOfBirth = String(form.get("dateOfBirth") ?? "");
    if (!dateOfBirth) {
      setError(t.chooseDate);
      return;
    }
    try {
      const dailyGoalRaw = String(form.get("dailyGoalKcal") ?? "").trim().replace(",", ".");
      const dailyGoalKcal = Math.round(Number(dailyGoalRaw));
      const next = await api<{ profile: Profile }>("/api/profile", {
        method: "PUT",
        body: JSON.stringify({
          sex: form.get("sex"),
          dateOfBirth,
          heightCm: Number(form.get("heightCm")),
          weightKg: Number(form.get("weightKg")),
          activity: form.get("activity"),
          weeklyPace: form.get("weeklyPace"),
          customGoalKcal: Number.isFinite(dailyGoalKcal) ? dailyGoalKcal : null,
        }),
      });
      setProfile(next.profile);
      setError("");
      navigate("/settings");
    } catch (err) {
      setError(message(t, err));
    }
  }
  function toggleReminderOffset(offset: ReminderOffset, on: boolean) {
    setReminderOffsets((current) => {
      const next = new Set(current);
      if (on) next.add(offset);
      else next.delete(offset);
      return ([0, 30, 60] as const).filter((value) => next.has(value));
    });
  }

  async function saveFasting(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    try {
      const next = await api<FastingState>("/api/fasting", {
        method: "PUT",
        body: JSON.stringify({
          enabled: fastingEnabledDraft,
          lengthHours: Number(form.get("lengthHours")),
          startHour: Number(form.get("startHour")),
          reminderOffsets,
        }),
      });
      setFasting(next);
      setFastingEnabledDraft(next.enabled);
      setReminderOffsets(next.reminderOffsets ?? []);
      setMe({ ...me, fastingEnabled: next.enabled });
      onFastingChange();
      navigate("/settings");
    } catch (err) {
      setError(message(t, err));
    }
  }
  async function saveLanguage(language: Lang) {
    await api("/api/profile/settings", { method: "PUT", body: JSON.stringify({ language, autoPublishFoods: autoPublish }) });
    setLang(language);
    setMe({ ...me, user: { ...me.user, language, autoPublishFoods: autoPublish } });
  }
  async function savePassword(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPasswordError("");
    setPasswordStatus("");
    if (!pwChecks.valid) {
      setPasswordError(!pwChecks.match ? t.password_mismatch : t.weak_password);
      return;
    }
    try {
      await api("/api/auth/password", {
        method: "PUT",
        body: JSON.stringify({ currentPassword, newPassword, confirmPassword }),
      });
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
      setPasswordStatus(t.passwordChanged);
    } catch (err) {
      setPasswordError(message(t, err));
    }
  }
  const back = (
    <Link className="back-link" to="/settings">
      <Chevron back /> {t.settings}
    </Link>
  );
  if (section === "account") {
    return (
      <>
        {back}
        <h1 className="page-title">{t.account}</h1>
      {me.hasPassword && (
      <Form className="card" onSubmit={savePassword}>
        <h2>{t.changePassword}</h2>
        <label>
          <span>{t.currentPassword}</span>
          <input
            type="password"
            value={currentPassword}
            onChange={(event) => setCurrentPassword(event.target.value)}
            required
          />
        </label>
        <label>
          <span>{t.newPassword}</span>
          <input
            type="password"
            value={newPassword}
            onChange={(event) => setNewPassword(event.target.value)}
            minLength={8}
            required
          />
        </label>
        <label>
          <span>{t.confirmPassword}</span>
          <input
            type="password"
            value={confirmPassword}
            onChange={(event) => setConfirmPassword(event.target.value)}
            minLength={8}
            required
          />
        </label>
        <div className="password-rules" role="status" aria-live="polite">
          <strong className="label">{t.passwordRulesTitle}</strong>
          <ul className="checklist">
            <li className={pwChecks.length ? "ok" : ""}>{pwChecks.length ? "✓" : "○"} {t.ruleLength}</li>
            <li className={pwChecks.english ? "ok" : ""}>{pwChecks.english ? "✓" : "○"} {t.ruleEnglish}</li>
            <li className={pwChecks.uppercase ? "ok" : ""}>{pwChecks.uppercase ? "✓" : "○"} {t.ruleUppercase}</li>
            <li className={pwChecks.number ? "ok" : ""}>{pwChecks.number ? "✓" : "○"} {t.ruleNumber}</li>
            <li className={pwChecks.symbol ? "ok" : ""}>{pwChecks.symbol ? "✓" : "○"} {t.ruleSymbol}</li>
            <li className={pwChecks.match ? "ok" : ""}>{pwChecks.match ? "✓" : "○"} {t.ruleMatch}</li>
          </ul>
        </div>
        {passwordError && <p className="error">{passwordError}</p>}
        {passwordStatus && <p className="rise success-text">{passwordStatus}</p>}
        <button type="submit" disabled={!currentPassword || !pwChecks.valid}>{t.save}</button>
      </Form>
      )}
        <section className="card list-card">
          {me.user.isAdmin && <Link className="list-row" to="/permissions">{t.permissions}<Chevron /></Link>}
          <button type="button" className="list-row danger" onClick={onLogout}>{t.logout}</button>
        </section>
      </>
    );
  }
  if (section === "profile") {
    return (
      <>
        {back}
      {profile && (
        <Form
          className="card"
          onSubmit={saveProfile}
          key={[
            profile.dateOfBirth,
            profile.sex,
            profile.activity,
            profile.weeklyPace,
            profile.heightCm,
            profile.weightKg,
            profile.customGoalKcal,
          ].join("|")}
        >
          <h1>{t.profileTitle}</h1>
          <ProfileFields profile={profile} />
          {health?.connected && <p className="muted">{t.healthActivityNote}</p>}
          <button type="submit">{t.save}</button>
        </Form>
      )}
        {error && <p className="error">{error}</p>}
      </>
    );
  }
  if (section === "fasting") {
    return (
      <>
        {back}
      {fasting && (
        <Form className="card" onSubmit={saveFasting} key={`${fasting.lengthHours}-${fasting.startHour}-${fasting.reminderOffsets.join(",")}`}>
          <h1>{t.fasting}</h1>
          <label>
            <input
              name="enabled"
              type="checkbox"
              checked={fastingEnabledDraft}
              onChange={(event) => setFastingEnabledDraft(event.target.checked)}
            />
            {t.fastingOn}
          </label>
          <MenuField
            name="lengthHours"
            label={t.fastingLength}
            defaultValue={String(fasting.lengthHours)}
            options={[
              { value: "12", label: `12 ${t.hours}` },
              { value: "14", label: `14 ${t.hours}` },
              { value: "16", label: `16 ${t.hours}` },
            ]}
          />
          <HourField name="startHour" label={t.startHour} defaultValue={fasting.startHour} />
          <p className="muted">{t.endHour}: {hourLabel(fasting.endHour)}</p>
          {fastingEnabledDraft && (
            <fieldset className="reminder-group">
              <legend>{t.fastReminder}</legend>
              <label><input type="checkbox" checked={reminderOffsets.includes(0)} onChange={(event) => toggleReminderOffset(0, event.target.checked)} />{t.reminderAtStart}</label>
              <label><input type="checkbox" checked={reminderOffsets.includes(30)} onChange={(event) => toggleReminderOffset(30, event.target.checked)} />{t.reminder30Before}</label>
              <label><input type="checkbox" checked={reminderOffsets.includes(60)} onChange={(event) => toggleReminderOffset(60, event.target.checked)} />{t.reminder1HourBefore}</label>
              <p className="muted">{t.reminderLateNote}</p>
            </fieldset>
          )}
          <button type="submit">{t.save}</button>
        </Form>
      )}
        {error && <p className="error">{error}</p>}
      </>
    );
  }
  if (section === "health" && canReadHealth) {
    return (
      <>
        {back}
      {health && (
        <Form className="card health-card" onSubmit={saveHealth} key={`${health.stepGoal}-${health.exerciseGoalMinutes}-${health.connected}`}>
          <h1>{t.appleHealth}</h1>
          <div className="health-status"><span>{health.connected ? t.healthConnected : t.healthNotConnected}</span></div>
          <div className="health-status">
            <span>{t.healthLastSync}</span>
            <b>{health.lastSyncedAt ? formatJerusalem(health.lastSyncedAt) : t.healthNever}</b>
          </div>
          {!health.connected && <p className="muted">{t.healthWebOnly}</p>}
          {(health.connected || health.lastSyncedAt) && (
            <>
              <label><span>{t.healthStepGoal}</span>
                <input name="stepGoal" type="number" inputMode="numeric" min={100} max={200000} step={100} defaultValue={health.stepGoal} required />
              </label>
              <label><span>{t.healthExerciseGoal}</span>
                <input name="exerciseGoalMinutes" type="number" inputMode="numeric" min={1} max={1440} defaultValue={health.exerciseGoalMinutes} required />
              </label>
              <button type="submit" disabled={!me.permissions.includes("appleHealth:sync")}>{t.save}</button>
            </>
          )}
        </Form>
      )}
        {error && <p className="error">{error}</p>}
      </>
    );
  }
  return (
    <>
      <h1 className="page-title">{t.settings}</h1>
      <section className="card">
        <MenuField
          label={t.language}
          value={me.user.language}
          onChange={(next) => saveLanguage(next as Lang)}
          options={[
            { value: "en", label: t.english },
            { value: "he", label: t.hebrew },
          ]}
        />
        <div className="label">{t.appearance}</div>
        <div className="segmented" role="group" aria-label={t.appearance}>
          {THEME_MODES.map((option) => (
            <button key={option} type="button" aria-pressed={themeMode === option} onClick={() => setThemeMode(option)}>
              {themeLabel(t, option)}
            </button>
          ))}
        </div>
        <label>
          <input type="checkbox" checked={autoPublish} onChange={async (event) => {
            const next = event.target.checked;
            setAutoPublish(next);
            await api("/api/profile/settings", { method: "PUT", body: JSON.stringify({ autoPublishFoods: next, language: me.user.language }) });
            setMe({ ...me, user: { ...me.user, autoPublishFoods: next } });
          }} />
          {t.autoPublish}
        </label>
      </section>
      <section className="card list-card">
        <Link className="list-row" to="/settings/profile">{t.profileTitle}<Chevron /></Link>
        <Link className="list-row" to="/settings/fasting">
          {t.fasting}
          <span className="list-value">{fasting ? (fasting.enabled ? `${fasting.lengthHours} ${t.hours}` : t.off) : ""}</span>
          <Chevron />
        </Link>
        {canReadHealth && (
          <Link className="list-row" to="/settings/health">
            {t.appleHealth}
            <span className="list-value">{health ? (health.connected ? t.healthConnected : t.healthNotConnected) : ""}</span>
            <Chevron />
          </Link>
        )}
        <Link className="list-row" to="/settings/account">{t.account}<Chevron /></Link>
      </section>
      {error && <p className="error">{error}</p>}
    </>
  );
}

/** Points to the trailing side; flipped for RTL in CSS. */
function Chevron({ back = false }: { back?: boolean }) {
  return (
    <svg className={back ? "disclosure back" : "disclosure"} viewBox="0 0 12 20" width="8" height="14" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
      <path d={back ? "M10 2 2 10l8 8" : "m2 2 8 8-8 8"} />
    </svg>
  );
}

function PermissionsPage() {
  const { t } = useI18n();
  const [permissions, setPermissions] = useState<Record<Operation, boolean> | null>(() => peek<PermissionsResponse>("/api/rbac/permissions")?.permissions ?? null);
  const [error, setError] = useState("");

  useEffect(() => {
    api<PermissionsResponse>("/api/rbac/permissions")
      .then((res) => setPermissions(res.permissions))
      .catch((err) => setError(message(t, err)));
  }, [t]);

  async function toggleOperation(op: Operation, allowed: boolean) {
    if (!permissions) return;
    const optimistic = { ...permissions, [op]: allowed };
    setPermissions(optimistic);
    setError("");
    try {
      const updated = await api<PermissionsResponse>("/api/rbac/permissions", {
        method: "PUT",
        body: JSON.stringify({ permissions: { [op]: allowed } }),
      });
      setPermissions(updated.permissions);
    } catch (err) {
      setPermissions(permissions);
      setError(message(t, err));
    }
  }

  return (
    <section className="card">
      <h1>{t.permissions}</h1>
      <p className="muted">{t.permissionsDesc}</p>
      {!permissions && !error && <p className="muted loading">…</p>}
      {permissions && (
        <div>
          {OPERATIONS.map((op) => {
            const labelKey = `op_${op}` as keyof Copy;
            return (
              <div className="entry" key={op}>
                <div>
                  <strong>{t[labelKey] ?? op}</strong>
                  <div className="muted">{op}</div>
                </div>
                <input
                  type="checkbox"
                  checked={permissions[op] ?? false}
                  onChange={(event) => toggleOperation(op, event.target.checked)}
                />
              </div>
            );
          })}
        </div>
      )}
      {error && <p className="error">{error}</p>}
    </section>
  );
}

function FoodForm() {
  const { t } = useI18n();
  const { id } = useParams();
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const [food, setFood] = useState<Food | null>(() => (id ? peek<{ food: Food }>(`/api/foods/${id}`)?.food ?? null : null));
  const [error, setError] = useState("");
  const barcode = params.get("barcode") ?? food?.barcode ?? "";
  const returnMeal = params.get("meal");
  const mealToReturn = returnMeal && (MEALS as readonly string[]).includes(returnMeal) ? returnMeal : null;
  useEffect(() => {
    if (!id) return;
    api<{ food: Food }>(`/api/foods/${id}`).then((result) => setFood(result.food)).catch((err) => setError(message(t, err)));
  }, [id, t]);
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    try {
      const body = {
        barcode: String(form.get("barcode") ?? barcode).trim() || null,
        name: form.get("name"),
        basis: form.get("basis"),
        calories: readNutrient(form.get("calories")),
        protein: readNutrient(form.get("protein"), true),
        carbohydrates: readNutrient(form.get("carbohydrates"), true),
        fat: readNutrient(form.get("fat"), true),
        fiber: readNutrient(form.get("fiber"), true),
        sugars: readNutrient(form.get("sugars"), true),
        sodium: readNutrient(form.get("sodium"), true),
      };
      let saved: Food;
      if (id) {
        const { name, basis, calories, protein, carbohydrates, fat, fiber, sugars, sodium } = body;
        saved = (await api<{ food: Food }>(`/api/foods/${id}`, { method: "PUT", body: JSON.stringify({ name, basis, calories, protein, carbohydrates, fat, fiber, sugars, sodium }) })).food;
      } else {
        saved = (await api<{ food: Food }>("/api/foods", { method: "POST", body: JSON.stringify(body) })).food;
      }
      navigate(mealToReturn ? `/?meal=${mealToReturn}&food=${encodeURIComponent(saved.id)}` : "/");
    } catch (err) {
      setError(message(t, err));
    }
  }
  return (
    <Form className="card" onSubmit={save} key={food?.id ?? "new"}>
      <h1>{t.createFood}</h1>
      {!id && params.get("source") === "online" && <p className="muted">{t.onlineValues}</p>}
      {!id && <label><span>{t.barcode}</span><input name="barcode" defaultValue={barcode} placeholder={t.optional} inputMode="numeric" /></label>}
      <label><span>{t.name}</span><input name="name" defaultValue={food?.name ?? (id ? undefined : params.get("name") ?? undefined)} required /></label>
      <MenuField
        name="basis"
        label={t.measuredAs}
        defaultValue={food?.basis ?? (params.get("basis") === "liquid" ? "liquid" : "solid")}
        options={[
          { value: "solid", label: t.solid },
          { value: "liquid", label: t.liquid },
        ]}
      />
      <label><span>{t.calories}</span><input name="calories" defaultValue={food?.calories ?? (id ? undefined : params.get("calories") ?? undefined)} placeholder="0" inputMode="decimal" pattern="\d+([.,]\d+)?" required /></label>
      <div className="nutrient-grid">
        {(["protein", "carbohydrates", "fat", "fiber", "sugars", "sodium"] as const).map((field) => (
          <label key={field}><span>{t[field]}</span><input name={field} defaultValue={food?.[field] ?? (id ? undefined : params.get(field) ?? undefined)} placeholder={t.optional} inputMode="decimal" pattern="\d+([.,]\d+)?" /></label>
        ))}
      </div>
      {error && <p className="error">{error}</p>}
      <button type="submit">{t.save}</button>
      {id && food?.owned && (
        <button type="button" className="secondary" onClick={async () => {
          await api(`/api/foods/${id}/${food.published ? "unpublish" : "publish"}`, { method: "POST" });
          setFood({ ...food, published: !food.published });
        }}>{food.published ? t.unpublish : t.publish}</button>
      )}
    </Form>
  );
}

function ProfileFields({ profile }: { profile?: Profile }) {
  const { t } = useI18n();
  // No silent default: during onboarding the user picks explicitly.
  const [sex, setSex] = useState<Sex | "">(profile?.sex ?? "");
  const [dateOfBirth, setDateOfBirth] = useState(profile?.dateOfBirth ?? "");
  const [heightCm, setHeightCm] = useState(profile?.heightCm != null ? String(profile.heightCm) : "");
  const [weightKg, setWeightKg] = useState(profile?.weightKg != null ? String(profile.weightKg) : "");
  const [activity, setActivity] = useState<ActivityLevel>(profile?.activity ?? "sedentary");
  const [pace, setPace] = useState<WeeklyPace>(profile?.weeklyPace ?? "kg050");
  const heightNum = Number(String(heightCm).replace(",", "."));
  const weightNum = Number(String(weightKg).replace(",", "."));
  const canSuggest =
    sex !== "" &&
    dateOfBirth.length === 10 && Number.isFinite(heightNum) && heightNum > 0 && Number.isFinite(weightNum) && weightNum > 0;
  const suggested = canSuggest
    ? suggestedCalorieGoal({
        sex: sex as Sex,
        weightKg: weightNum,
        heightCm: heightNum,
        age: ageFromDob(dateOfBirth),
        activity,
        pace,
      })
    : null;
  const initialGoal = profile?.customGoalKcal ?? suggested;
  const [dailyGoal, setDailyGoal] = useState(initialGoal != null ? String(initialGoal) : "");
  const [touchedGoal, setTouchedGoal] = useState(profile?.customGoalKcal != null);

  useEffect(() => {
    if (touchedGoal || suggested == null) return;
    setDailyGoal(String(suggested));
  }, [suggested, touchedGoal]);

  return (
    <>
      <div className="field">
        <div className="label" id="sex-label">{t.sex}</div>
        <div className="segmented" role="radiogroup" aria-labelledby="sex-label">
          {(["female", "male"] as const).map((option) => (
            <button key={option} type="button" role="radio" aria-checked={sex === option} aria-pressed={sex === option} onClick={() => setSex(option)}>
              {option === "female" ? t.female : t.male}
            </button>
          ))}
        </div>
        <input type="hidden" name="sex" value={sex} />
      </div>
      <DateField
        name="dateOfBirth"
        label={t.dateOfBirth}
        defaultValue={profile?.dateOfBirth}
        onChange={setDateOfBirth}
      />
      <label>
        <span>{t.height}</span>
        <input
          name="heightCm"
          inputMode="decimal"
          value={heightCm}
          onChange={(event) => setHeightCm(event.target.value)}
          required
        />
      </label>
      <label>
        <span>{t.weightKg}</span>
        <input
          name="weightKg"
          inputMode="decimal"
          value={weightKg}
          onChange={(event) => setWeightKg(event.target.value)}
          required
        />
      </label>
      <MenuField
        name="activity"
        label={t.activity}
        value={activity}
        onChange={(next) => setActivity(next as ActivityLevel)}
        options={[
          { value: "sedentary", label: t.sedentary },
          { value: "light", label: t.light },
          { value: "moderate", label: t.moderate },
          { value: "very", label: t.very },
          { value: "extra", label: t.extra },
        ]}
      />
      <MenuField
        name="weeklyPace"
        label={t.pace}
        value={pace}
        onChange={(next) => setPace(next as WeeklyPace)}
        options={[
          { value: "kg025", label: t.pace025 },
          { value: "kg050", label: t.pace050 },
          { value: "kg100", label: t.pace100 },
        ]}
      />
      <label>
        <span>{t.dailyGoal}</span>
        <input
          name="dailyGoalKcal"
          inputMode="numeric"
          placeholder={t.goalAutoHint}
          value={dailyGoal}
          onChange={(event) => {
            setTouchedGoal(true);
            setDailyGoal(event.target.value);
          }}
          required
        />
      </label>
      {/* Only offered once the goal differs from the suggestion. */}
      {suggested != null && touchedGoal && (
        <button
          type="button"
          className="secondary"
          onClick={() => {
            setTouchedGoal(false);
            setDailyGoal(String(suggested));
          }}
        >
          {t.useSuggested}
          {touchedGoal ? ` (${suggested})` : ""}
        </button>
      )}
      <p className="muted">{t.goalFloorNote}</p>
    </>
  );
}

function HourField({ name, label, defaultValue, value, onChange }: { name: string; label: string; defaultValue?: number; value?: number; onChange?: (hour: number) => void }) {
  return (
    <MenuField
      name={name}
      label={label}
      options={Array.from({ length: 24 }, (_, hour) => ({ value: String(hour), label: hourLabel(hour) }))}
      value={value == null ? undefined : String(value)}
      defaultValue={value == null ? String(defaultValue ?? 0) : undefined}
      onChange={onChange ? (next) => onChange(Number(next)) : undefined}
    />
  );
}

function readNutrient(value: FormDataEntryValue | null, optional = false): number {
  const raw = String(value ?? "").trim().replace(",", ".");
  if (optional && raw === "") return 0;
  if (!/^\d+(\.\d+)?$/.test(raw)) throw new ApiError("invalid_body");
  return Number(raw);
}

function AnimatedNumber({ value, from }: { value: number; from: number }) {
  const shown = useEase(value, from);
  return <>{formatKcal(shown)}</>;
}

function useEase(target: number, initial: number) {
  const reduce = prefersReducedMotion();
  const [value, setValue] = useState(reduce ? target : initial);
  const current = useRef(reduce ? target : initial);
  useEffect(() => {
    if (reduce) {
      current.current = target;
      setValue(target);
      return;
    }
    const from = current.current;
    if (from === target) return;
    const start = performance.now();
    let frame = 0;
    const step = (now: number) => {
      const t = Math.min(1, (now - start) / 720);
      const eased = 1 - (1 - t) ** 3;
      const next = from + (target - from) * eased;
      current.current = next;
      setValue(next);
      if (t < 1) frame = requestAnimationFrame(step);
    };
    frame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame);
  }, [target, reduce]);
  return value;
}

function prefersReducedMotion() {
  return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

function reminderText(t: Copy, item: FastNotification): string {
  if (item.kind === "late") return t.reminderLate;
  if (item.kind === "done") return t.reminderDone;
  if (item.leadMinutes != null && item.leadMinutes >= 60) return t.reminderLead60;
  if (item.leadMinutes != null && item.leadMinutes >= 30) return t.reminderLead30;
  return t.reminderStart;
}

function notify(text: string, setNotice: (value: string) => void) {
  setNotice(text);
  if (typeof Notification !== "undefined" && Notification.permission === "granted") {
    new Notification(text);
  }
}

function formatDuration(ms: number): string {
  const total = Math.floor(ms / 1000);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = total % 60;
  return [hours, minutes, seconds].map((part) => String(part).padStart(2, "0")).join(":");
}

/**
 * <form> that shows a busy state while its async submit handler runs:
 * the submit button gets a spinner and repeat submits are ignored.
 */
function Form({ onSubmit, children, ...props }: Omit<ComponentProps<"form">, "onSubmit"> & { onSubmit: (event: FormEvent<HTMLFormElement>) => unknown }) {
  const [busy, setBusy] = useState(false);
  const busyRef = useRef(false);
  async function handle(event: FormEvent<HTMLFormElement>) {
    if (busyRef.current) {
      event.preventDefault();
      return;
    }
    busyRef.current = true;
    setBusy(true);
    try {
      await onSubmit(event);
    } finally {
      busyRef.current = false;
      setBusy(false);
    }
  }
  return (
    <form {...props} onSubmit={handle} aria-busy={busy || undefined}>
      {children}
    </form>
  );
}

function message(t: Copy, err: unknown): string {
  const code = err instanceof ApiError ? err.code : "server_error";
  return t[code as keyof Copy] ?? t.server_error;
}
