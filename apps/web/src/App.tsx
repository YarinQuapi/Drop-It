import { useEffect, useRef, useState, type FormEvent } from "react";
import { createPortal } from "react-dom";
import { Link, NavLink, Navigate, Route, Routes, useLocation, useNavigate, useParams, useSearchParams } from "react-router-dom";
import {
  api,
  ApiError,
  type AppleHealthState,
  type DayResponse,
  type FastingSession,
  type FastingState,
  type FastNotification,
  type Food,
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
import { addDays, formatJerusalem, formatJerusalemDay, formatJerusalemTime, hourLabel, jerusalemParts } from "./clock";
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
  const [menuOpen, setMenuOpen] = useState(false);
  const [reminderVersion, setReminderVersion] = useState(0);
  const [notice, setNotice] = useState("");
  function closeMenu() {
    setMenuOpen(false);
  }
  function bumpReminders() {
    setReminderVersion((value) => value + 1);
  }
  useEffect(() => {
    if (!menuOpen) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, [menuOpen]);
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
  const menuLayer = createPortal(
    <>
      <div
        className={menuOpen ? "menu-backdrop visible" : "menu-backdrop"}
        aria-hidden={!menuOpen}
        onClick={closeMenu}
      />
      <aside className={menuOpen ? "menu-drawer open" : "menu-drawer"} inert={!menuOpen} aria-hidden={!menuOpen}>
        <nav className="nav-panel">
          <NavLink to="/" end onClick={closeMenu}>{t.today}</NavLink>
          <NavLink to="/week" onClick={closeMenu}>{t.week}</NavLink>
          <NavLink to="/weight" onClick={closeMenu}>{t.weight}</NavLink>
          <NavLink to="/fasting" onClick={closeMenu}>{t.fasting}</NavLink>
          <NavLink to="/settings" onClick={closeMenu}>{t.settings}</NavLink>
          {me.user.isAdmin && <NavLink to="/permissions" onClick={closeMenu}>{t.permissions}</NavLink>}
          <button type="button" onClick={async () => { await api("/api/auth/logout", { method: "POST" }).catch(() => {}); setStoredToken(null); setMe(null); }}>{t.logout}</button>
        </nav>
      </aside>
    </>,
    document.body,
  );
  return (
    <div className="shell">
      <header className="topbar">
        <strong>{t.appName}</strong>
        <button className="icon" type="button" aria-label={t.menu} aria-expanded={menuOpen} onClick={() => setMenuOpen((open) => !open)}>
          <span /><span /><span />
        </button>
      </header>
      {menuLayer}
      <div key={location.pathname} className="page">
        {notice && <p className="rise">{notice}</p>}
        <Routes location={location}>
          <Route path="/" element={<Today canVerifyFoods={canVerifyFoods} />} />
          <Route path="/week" element={<WeekPage />} />
          <Route path="/weight" element={<WeightPage />} />
          <Route path="/fasting" element={<FastingPage onFastingChange={bumpReminders} />} />
          <Route path="/settings" element={<SettingsPage me={me} setMe={setMe} onFastingChange={bumpReminders} />} />
          <Route path="/permissions" element={me.user.isAdmin ? <PermissionsPage /> : <Navigate to="/" />} />
          <Route path="/foods/new" element={<FoodForm />} />
          <Route path="/foods/:id" element={<FoodForm />} />
        </Routes>
      </div>
    </div>
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
  const { t, lang } = useI18n();
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
    <main className="shell page">
      <form className="card" onSubmit={submit}>
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
        <button type="submit" disabled={mode === "signup" && !checks.valid}>{mode === "login" ? t.login : t.signup}</button>
        <p>{mode === "login" ? <Link to="/signup">{t.needAccount}</Link> : <Link to="/login">{t.haveAccount}</Link>}</p>
      </form>
    </main>
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
      <form className="card" onSubmit={save}>
        <h1>{t.fastingQuestion}</h1>
        <div className="row">
          <button type="button" className={wants === true ? "" : "secondary"} onClick={() => setWants(true)}>{t.yes}</button>
          <button type="button" className={wants === false ? "" : "secondary"} onClick={() => setWants(false)}>{t.no}</button>
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
      </form>
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
      <form className="card" onSubmit={save}>
        <h1>{t.profileTitle}</h1>
        <ProfileFields />
        {error && <p className="error">{error}</p>}
        <button type="submit">{t.save}</button>
      </form>
    </main>
  );
}

function Today({ canVerifyFoods }: { canVerifyFoods: boolean }) {
  const { t } = useI18n();
  const [day, setDay] = useState<DayResponse | null>(null);
  const [loggingMeal, setLoggingMeal] = useState<MealCategory | null>(null);
  const [barcode, setBarcode] = useState("");
  const [lookup, setLookup] = useState<{ status: string; food: Food | null; foods: Food[] } | null>(null);
  const [picked, setPicked] = useState<Food | null>(null);
  const [amount, setAmount] = useState("100");
  const [error, setError] = useState("");

  async function reload() {
    setDay(await api<DayResponse>("/api/days/today"));
  }

  useEffect(() => {
    reload().catch((err) => setError(message(t, err)));
  }, [t]);

  function openLog(meal: MealCategory) {
    setLoggingMeal((current) => (current === meal ? null : meal));
    setBarcode("");
    setLookup(null);
    setPicked(null);
    setAmount("100");
    setError("");
  }

  async function findFood(event: FormEvent) {
    event.preventDefault();
    setError("");
    const result = await api<{ status: string; food: Food | null; foods: Food[] }>(`/api/foods/barcode/${encodeURIComponent(barcode.trim())}`);
    setLookup(result);
    setPicked(result.food);
  }

  async function addFood(event: FormEvent) {
    event.preventDefault();
    if (!picked || !loggingMeal) return;
    try {
      await api(`/api/days/today/entries`, {
        method: "POST",
        body: JSON.stringify({ foodId: picked.id, amount: Number(amount), meal: loggingMeal }),
      });
      setLoggingMeal(null);
      setLookup(null);
      setPicked(null);
      await reload();
    } catch (err) {
      setError(message(t, err));
    }
  }

  async function remove(id: string) {
    await api(`/api/days/today/entries/${id}`, { method: "DELETE" });
    await reload();
  }

  const remaining = day ? day.goalKcal - day.totals.calories : 0;
  const over = day ? day.totals.calories > day.goalKcal : false;

  return (
    <>
      {day && (
        <section className="card today-summary">
          <h1>{t.today}</h1>
          <div className="today-hero">
            <div className="ring-wrap">
              <CalorieRing eaten={day.totals.calories} goal={day.goalKcal} over={over} />
              <div className="ring-center">
                <b><AnimatedNumber value={remaining} from={day.goalKcal} /></b>
                <span>{t.remaining}</span>
              </div>
            </div>
            <div className="hero-side">
              {day.healthAdjusted && (
                <>
                  <div className="pair"><span>{t.healthBaseGoal}</span><b>{day.baseGoalKcal} {t.kcal}</b></div>
                  <div className="pair"><span>{t.healthActiveKcal}</span><b>+{day.activeKcal} {t.kcal}</b></div>
                </>
              )}
              <div className="pair"><span>{t.goal}</span><b>{day.goalKcal} {t.kcal}</b></div>
              <div className="pair"><span>{t.eaten}</span><b>{day.totals.calories} {t.kcal}</b></div>
              <p className="muted">{over ? t.missed : day.success ? t.success : day.healthAdjusted ? t.healthEstimate : t.estimate}</p>
            </div>
          </div>
        </section>
      )}
      {day && day.healthSynced && (
        <section className="card health-card">
          <h2>{t.appleHealth}</h2>
          <ProgressRow label={t.healthSteps} value={day.steps} goal={day.stepGoal} unit="" />
          <ProgressRow label={t.healthExercise} value={day.exerciseMinutes} goal={day.exerciseGoalMinutes} unit={t.healthMinutes} />
        </section>
      )}
      {error && !loggingMeal && <p className="error">{error}</p>}
      {MEALS.map((meal) => {
        const mealEntries = day?.entries.filter((entry) => entry.meal === meal) ?? [];
        const mealKcal = mealEntries.reduce((sum, entry) => sum + entry.calories, 0);
        const logging = loggingMeal === meal;
        return (
          <section className="card meal-card" key={meal}>
            <div className="meal-head">
              <h2>{mealLabel(t, meal)}</h2>
              <span className="meal-total">{mealKcal} {t.kcal}</span>
            </div>
            {mealEntries.length === 0 && <p className="muted meal-empty">{t.emptyMeal}</p>}
            {mealEntries.map((entry) => (
              <div className="entry" key={entry.id}>
                <div>
                  <strong>{entry.name}</strong>
                  <div className="muted">{entry.amount} {entry.basis === "solid" ? t.grams : t.milliliters}</div>
                </div>
                <div>
                  <span className="kcal">{entry.calories}</span>
                  <button className="quiet" type="button" onClick={() => remove(entry.id)}>{t.delete}</button>
                </div>
              </div>
            ))}
            <button type="button" className={logging ? "secondary meal-log" : "meal-log"} onClick={() => openLog(meal)}>
              {t.log}
            </button>
            <div className={logging ? "reveal open" : "reveal"} inert={!logging}>
              <div className="reveal-inner">
                <form onSubmit={findFood} className="food-add">
                  <label><span>{t.barcode}</span><input value={barcode} onChange={(event) => setBarcode(event.target.value)} required /></label>
                  <button type="submit">{t.lookUp}</button>
                </form>
              </div>
            </div>
            {logging && lookup?.status === "none" && (
              <p className="rise">{t.noFood} <Link to={`/foods/new?barcode=${encodeURIComponent(barcode)}`}>{t.createFood}</Link></p>
            )}
            {logging && lookup?.status === "list" && (
              <div className="rise">
                <h3>{t.chooseFood}</h3>
                {lookup.foods.map((food) => (
                  <button key={food.id} type="button" className="secondary choice" onClick={() => setPicked(food)}>{food.name}{food.verified ? ` · ${t.verified}` : ""}</button>
                ))}
              </div>
            )}
            {logging && picked && (
              <form className="rise" onSubmit={addFood}>
                <p><strong>{picked.name}</strong> · {picked.owned ? t.personal : ""} {picked.verified ? t.verified : ""}</p>
                <p className="muted">{picked.calories} {t.kcal} / 100 {picked.basis === "solid" ? t.grams : t.milliliters}</p>
                <label><span>{t.amount} ({picked.basis === "solid" ? t.grams : t.milliliters})</span>
                  <input value={amount} onChange={(event) => setAmount(event.target.value)} inputMode="decimal" required />
                </label>
                <div className="fast-actions">
                  <button type="submit">{t.add}</button>
                  <Link className="secondary" to={`/foods/${picked.id}`}>{t.edit}</Link>
                  {canVerifyFoods && picked.published && !picked.verified && (
                    <button type="button" className="secondary" onClick={async () => {
                      const result = await api<{ food: Food }>(`/api/foods/${picked.id}/verify`, { method: "POST" });
                      setPicked(result.food);
                    }}>{t.verify}</button>
                  )}
                </div>
              </form>
            )}
            {logging && error && <p className="error">{error}</p>}
          </section>
        );
      })}
    </>
  );
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
  const [fasting, setFasting] = useState<FastingState | null>(null);
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
  const sessions = fasting?.sessions ?? [];

  return (
    <>
      <section className={fasting?.running ? "card fast-card running" : "card fast-card"}>
        <h1>{t.fasting}</h1>
        {fasting?.enabled ? (
          <div className="fast-hero">
            {fasting.running && fasting.endsAt && (
              <>
                <p className="fast-count rise">{formatDuration(left)}</p>
                <p className="muted">{t.approximateEnd}: {formatJerusalemTime(fasting.endsAt)}</p>
              </>
            )}
            {!fasting.running && (
              <p className="muted">{t.scheduled}: {hourLabel(fasting.startHour)} – {hourLabel(fasting.endHour)} · {fasting.lengthHours} {t.hours}</p>
            )}
            <button className="fast-go" type="button" onClick={toggle}>{fasting.running ? t.stopFast : t.startFast}</button>
          </div>
        ) : fasting && <p className="muted">{t.fasting_disabled} <Link to="/settings">{t.settings}</Link></p>}
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

function CalorieRing({ eaten, goal, over }: { eaten: number; goal: number; over: boolean }) {
  const radius = 52;
  const circumference = 2 * Math.PI * radius;
  const ratio = goal > 0 ? Math.min(eaten / goal, 1) : 0;
  const reduce = prefersReducedMotion();
  const [progress, setProgress] = useState(reduce ? ratio : 0);
  useEffect(() => {
    if (reduce) {
      setProgress(ratio);
      return;
    }
    const frame = requestAnimationFrame(() => setProgress(ratio));
    return () => cancelAnimationFrame(frame);
  }, [ratio, reduce]);
  return (
    <svg className="ring" viewBox="0 0 120 120" aria-hidden="true">
      <circle className="ring-track" cx="60" cy="60" r={radius} />
      <circle
        className={over ? "ring-fill over" : "ring-fill"}
        cx="60"
        cy="60"
        r={radius}
        strokeDasharray={circumference}
        style={{ strokeDashoffset: circumference * (1 - progress) }}
      />
    </svg>
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
  const [week, setWeek] = useState<WeekResponse | null>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    const query = on ? `?on=${on}` : "";
    api<WeekResponse>(`/api/weeks${query}`).then(setWeek).catch((err) => setError(message(t, err)));
  }, [on, t]);
  if (!week) return error ? <p className="error">{error}</p> : <p className="muted loading">…</p>;
  const countedDays = week.days.filter((day) => !day.future && day.calories > 0);
  return (
    <section className="card rise" key={week.sunday}>
      <h1>{t.week}</h1>
      <div className="row">
        <button className="secondary" onClick={() => setParams({ on: addDays(week.sunday, -7) })}>{t.previousWeek}</button>
        <button className="secondary" onClick={() => setParams({ on: addDays(week.sunday, 7) })}>{t.nextWeek}</button>
      </div>
      <div className="stats">
        <div className="stat"><span>{t.calorieIntake}</span><b>{week.calorieIntake} / {week.goalKcal}</b></div>
        <div className="stat"><span>{t.successCount}</span><b>{week.successCount}</b></div>
        <div className="stat"><span>{t.weightChange}</span><b>{week.weightChangeKg == null ? "—" : week.weightChangeKg}</b></div>
      </div>
      {week.weightChangeKg == null && <p className="muted">{t.noWeightChange}</p>}
      {countedDays.map((day) => (
        <div className="week-day" key={day.day}>
          <span>{day.day}</span>
          <span>{day.calories} / {day.goalKcal}</span>
          <span>{day.success ? t.success : t.missed}</span>
          {day.steps != null && (
            <span className="week-day-health">
              {t.healthSteps} {day.steps.toLocaleString()} · {t.healthExercise} {day.exerciseMinutes ?? 0} {t.healthMinutes}
              {day.activeKcal ? ` · ${t.healthActiveKcal} +${day.activeKcal} ${t.kcal}` : ""}
            </span>
          )}
        </div>
      ))}
    </section>
  );
}

function WeightPage() {
  const { t } = useI18n();
  const [weights, setWeights] = useState<WeightPoint[]>([]);
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
      <form className="card" onSubmit={save}>
        <h1>{t.weight}</h1>
        <label><span>{t.weightKg}</span><input name="weightKg" inputMode="decimal" pattern="\d+([.,]\d+)?" required /></label>
        <label><span>{t.loggedAt}</span><input name="loggedAt" type="datetime-local" /></label>
        {error && <p className="error">{error}</p>}
        <button type="submit">{t.logWeight}</button>
      </form>
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

function SettingsPage({ me, setMe, onFastingChange }: { me: Me; setMe: (me: Me) => void; onFastingChange: () => void }) {
  const { t, setLang } = useI18n();
  const { mode: themeMode, setMode: setThemeMode } = useTheme();
  const [profile, setProfile] = useState<Profile | null>(null);
  const [fasting, setFasting] = useState<FastingState | null>(null);
  const [fastingEnabledDraft, setFastingEnabledDraft] = useState(false);
  const [reminderOffsets, setReminderOffsets] = useState<ReminderOffset[]>([0]);
  const [autoPublish, setAutoPublish] = useState(me.user.autoPublishFoods);
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [passwordStatus, setPasswordStatus] = useState("");
  const [passwordError, setPasswordError] = useState("");
  const [health, setHealth] = useState<AppleHealthState | null>(null);
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
  return (
    <>
      <section className="card">
        <h1>{t.settings}</h1>
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
      {me.hasPassword && (
      <form className="card" onSubmit={savePassword}>
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
      </form>
      )}
      {profile && (
        <form
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
          <h2>{t.profileTitle}</h2>
          <ProfileFields profile={profile} />
          {health?.connected && <p className="muted">{t.healthActivityNote}</p>}
          <button type="submit">{t.save}</button>
        </form>
      )}
      {health && (
        <form className="card health-card" onSubmit={saveHealth} key={`${health.stepGoal}-${health.exerciseGoalMinutes}-${health.connected}`}>
          <h2>{t.appleHealth}</h2>
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
        </form>
      )}
      {fasting && (
        <form className="card" onSubmit={saveFasting} key={`${fasting.lengthHours}-${fasting.startHour}-${fasting.reminderOffsets.join(",")}`}>
          <h2>{t.fasting}</h2>
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
        </form>
      )}
      {error && <p className="error">{error}</p>}
    </>
  );
}

function PermissionsPage() {
  const { t } = useI18n();
  const [permissions, setPermissions] = useState<Record<Operation, boolean> | null>(null);
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
  const [food, setFood] = useState<Food | null>(null);
  const [error, setError] = useState("");
  const barcode = params.get("barcode") ?? food?.barcode ?? "";
  useEffect(() => {
    if (!id) return;
    api<{ food: Food }>(`/api/foods/${id}`).then((result) => setFood(result.food)).catch((err) => setError(message(t, err)));
  }, [id, t]);
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    try {
      const body = {
        barcode: String(form.get("barcode") ?? barcode),
        name: form.get("name"),
        basis: form.get("basis"),
        calories: readNutrient(form.get("calories")),
        protein: readNutrient(form.get("protein")),
        carbohydrates: readNutrient(form.get("carbohydrates")),
        fat: readNutrient(form.get("fat")),
        fiber: readNutrient(form.get("fiber")),
        sugars: readNutrient(form.get("sugars")),
        sodium: readNutrient(form.get("sodium")),
      };
      if (id) {
        const { name, basis, calories, protein, carbohydrates, fat, fiber, sugars, sodium } = body;
        await api(`/api/foods/${id}`, { method: "PUT", body: JSON.stringify({ name, basis, calories, protein, carbohydrates, fat, fiber, sugars, sodium }) });
      } else {
        await api("/api/foods", { method: "POST", body: JSON.stringify(body) });
      }
      navigate("/");
    } catch (err) {
      setError(message(t, err));
    }
  }
  return (
    <form className="card" onSubmit={save} key={food?.id ?? "new"}>
      <h1>{t.createFood}</h1>
      {!id && <label><span>{t.barcode}</span><input name="barcode" defaultValue={barcode} required /></label>}
      <label><span>{t.name}</span><input name="name" defaultValue={food?.name} required /></label>
      <MenuField
        name="basis"
        label={t.solid}
        defaultValue={food?.basis ?? "solid"}
        options={[
          { value: "solid", label: t.solid },
          { value: "liquid", label: t.liquid },
        ]}
      />
      {(["calories", "protein", "carbohydrates", "fat", "fiber", "sugars", "sodium"] as const).map((field) => (
        <label key={field}><span>{t[field]}</span><input name={field} defaultValue={food?.[field] ?? 0} inputMode="decimal" pattern="\d+([.,]\d+)?" required /></label>
      ))}
      {error && <p className="error">{error}</p>}
      <button type="submit">{t.save}</button>
      {id && food?.owned && (
        <button type="button" className="secondary" onClick={async () => {
          await api(`/api/foods/${id}/${food.published ? "unpublish" : "publish"}`, { method: "POST" });
          setFood({ ...food, published: !food.published });
        }}>{food.published ? t.unpublish : t.publish}</button>
      )}
    </form>
  );
}

function ProfileFields({ profile }: { profile?: Profile }) {
  const { t } = useI18n();
  const [sex, setSex] = useState<Sex>(profile?.sex ?? "female");
  const [dateOfBirth, setDateOfBirth] = useState(profile?.dateOfBirth ?? "");
  const [heightCm, setHeightCm] = useState(profile?.heightCm != null ? String(profile.heightCm) : "");
  const [weightKg, setWeightKg] = useState(profile?.weightKg != null ? String(profile.weightKg) : "");
  const [activity, setActivity] = useState<ActivityLevel>(profile?.activity ?? "sedentary");
  const [pace, setPace] = useState<WeeklyPace>(profile?.weeklyPace ?? "kg050");
  const heightNum = Number(String(heightCm).replace(",", "."));
  const weightNum = Number(String(weightKg).replace(",", "."));
  const canSuggest =
    dateOfBirth.length === 10 && Number.isFinite(heightNum) && heightNum > 0 && Number.isFinite(weightNum) && weightNum > 0;
  const suggested = canSuggest
    ? suggestedCalorieGoal({
        sex,
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
      <MenuField
        name="sex"
        label={t.sex}
        value={sex}
        onChange={(next) => setSex(next as Sex)}
        options={[
          { value: "female", label: t.female },
          { value: "male", label: t.male },
        ]}
      />
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
          value={dailyGoal}
          onChange={(event) => {
            setTouchedGoal(true);
            setDailyGoal(event.target.value);
          }}
          required
        />
      </label>
      {suggested != null && (
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

function readNutrient(value: FormDataEntryValue | null): number {
  const raw = String(value ?? "").trim().replace(",", ".");
  if (!/^\d+(\.\d+)?$/.test(raw)) throw new ApiError("invalid_body");
  return Number(raw);
}

function AnimatedNumber({ value, from }: { value: number; from: number }) {
  const shown = useEase(value, from);
  return <>{Math.round(shown)}</>;
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

function message(t: Copy, err: unknown): string {
  const code = err instanceof ApiError ? err.code : "server_error";
  return t[code as keyof Copy] ?? t.server_error;
}
