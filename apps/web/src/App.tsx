import { useEffect, useRef, useState, type FormEvent } from "react";
import { createPortal } from "react-dom";
import { Link, NavLink, Navigate, Route, Routes, useLocation, useNavigate, useParams, useSearchParams } from "react-router-dom";
import {
  api,
  ApiError,
  type DayResponse,
  type FastingSession,
  type FastingState,
  type Food,
  MEALS,
  type MealCategory,
  type Me,
  OPERATIONS,
  type Operation,
  type PermissionsResponse,
  type Profile,
  type WeekResponse,
  type WeightPoint,
} from "./api";
import { addDays, formatJerusalem, formatJerusalemDay, formatJerusalemTime, hourLabel, jerusalemParts, msUntilHour } from "./clock";
import { useI18n, type Copy, type Lang } from "./i18n";

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
  function closeMenu() {
    setMenuOpen(false);
  }
  useEffect(() => {
    if (!menuOpen) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.body.style.overflow = prev;
    };
  }, [menuOpen]);
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
          <button type="button" onClick={async () => { await api("/api/auth/logout", { method: "POST" }); setMe(null); }}>{t.logout}</button>
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
        <Routes location={location}>
          <Route path="/" element={<Today canVerifyFoods={canVerifyFoods} />} />
          <Route path="/week" element={<WeekPage />} />
          <Route path="/weight" element={<WeightPage />} />
          <Route path="/fasting" element={<FastingPage />} />
          <Route path="/settings" element={<SettingsPage me={me} setMe={setMe} />} />
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
  const checks = checkSignupPassword(password, confirmPassword);

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
            <label><span>{t.fastingLength}</span>
              <select value={lengthHours} onChange={(event) => setLengthHours(Number(event.target.value))}>
                <option value="12">12 {t.hours}</option>
                <option value="14">14 {t.hours}</option>
                <option value="16">16 {t.hours}</option>
              </select>
            </label>
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
    try {
      await api("/api/profile", {
        method: "PUT",
        body: JSON.stringify({
          sex: form.get("sex"),
          dateOfBirth: form.get("dateOfBirth"),
          heightCm: Number(form.get("heightCm")),
          weightKg: Number(form.get("weightKg")),
          activity: form.get("activity"),
          weeklyPace: form.get("weeklyPace"),
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
              <div className="pair"><span>{t.goal}</span><b>{day.goalKcal} {t.kcal}</b></div>
              <div className="pair"><span>{t.eaten}</span><b>{day.totals.calories} {t.kcal}</b></div>
              <p className="muted">{over ? t.missed : day.success ? t.success : t.estimate}</p>
            </div>
          </div>
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

function mealLabel(t: Copy, meal: MealCategory) {
  switch (meal) {
    case "breakfast": return t.breakfast;
    case "lunch": return t.lunch;
    case "dinner": return t.dinner;
    case "snacks": return t.snacks;
  }
}

function FastingPage() {
  const { t } = useI18n();
  const [fasting, setFasting] = useState<FastingState | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    api<FastingState>("/api/fasting").then(setFasting).catch((err) => setError(message(t, err)));
  }, [t]);

  useEffect(() => {
    const tick = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(tick);
  }, []);

  useEffect(() => {
    if (!fasting?.enabled) return;
    const timers = [
      window.setTimeout(() => notify(t.reminderStart, setNotice), msUntilHour(fasting.startHour)),
      window.setTimeout(() => notify(t.reminderEnd, setNotice), msUntilHour(fasting.endHour)),
    ];
    if (fasting.running && fasting.endsAt) {
      const wait = new Date(fasting.endsAt).getTime() - Date.now();
      if (wait > 0) timers.push(window.setTimeout(() => notify(t.reminderDone, setNotice), wait));
    }
    return () => timers.forEach((id) => window.clearTimeout(id));
  }, [fasting, t]);

  async function toggle() {
    if (!fasting) return;
    try {
      const next = await api<FastingState>(fasting.running ? "/api/fasting/stop" : "/api/fasting/start", { method: "POST" });
      setFasting(next);
      setError("");
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
        {notice && <p className="rise">{notice}</p>}
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
  return (
    <section className="card rise" key={week.sunday}>
      <h1>{t.week}</h1>
      <div className="row">
        <button className="secondary" onClick={() => setParams({ on: addDays(week.sunday, -7) })}>{t.previousWeek}</button>
        <button className="secondary" onClick={() => setParams({ on: addDays(week.sunday, 7) })}>{t.nextWeek}</button>
      </div>
      <div className="stats">
        <div className="stat"><span>{t.calorieIntake}</span><b>{week.calorieIntake}</b></div>
        <div className="stat"><span>{t.successCount}</span><b>{week.successCount}</b></div>
        <div className="stat"><span>{t.weightChange}</span><b>{week.weightChangeKg == null ? "—" : week.weightChangeKg}</b></div>
      </div>
      {week.weightChangeKg == null && <p className="muted">{t.noWeightChange}</p>}
      {week.days.map((day) => (
        <div className="week-day" key={day.day}>
          <span>{day.day}</span>
          <span>{day.calories} / {day.goalKcal}</span>
          <span>{day.future || !day.success && day.calories === 0 ? t.notYet : day.success ? t.success : t.missed}</span>
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
          weightKg: Number(data.get("weightKg")),
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
        <label><span>{t.weightKg}</span><input name="weightKg" inputMode="decimal" required /></label>
        <label><span>{t.loggedAt}</span><input name="loggedAt" type="datetime-local" /></label>
        {error && <p className="error">{error}</p>}
        <button type="submit">{t.logWeight}</button>
      </form>
      <section className="card">
        {weights.length === 0 ? <p className="muted">{t.graphEmpty}</p> : <WeightGraph weights={weights} />}
        {weights.map((point) => (
          <div className="entry" key={point.id}><span>{formatJerusalem(point.loggedAt)}</span><strong>{point.weightKg}</strong></div>
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
  const points = weights.map((point) => {
    const x = maxT === minT ? width / 2 : ((new Date(point.loggedAt).getTime() - minT) / (maxT - minT)) * (width - 24) + 12;
    const y = maxV === minV ? height / 2 : height - 16 - ((point.weightKg - minV) / (maxV - minV)) * (height - 32);
    return `${x},${y}`;
  }).join(" ");
  return (
    <svg viewBox={`0 0 ${width} ${height}`} width="100%" role="img">
      <polyline className="graph-line" pathLength={1} fill="none" stroke="#e07a2f" strokeWidth="3" points={points} />
      {points.split(" ").map((pair) => {
        const [x, y] = pair.split(",");
        return <circle className="graph-dot" key={pair} cx={x} cy={y} r="4" fill="#e07a2f" />;
      })}
    </svg>
  );
}

function SettingsPage({ me, setMe }: { me: Me; setMe: (me: Me) => void }) {
  const { t, setLang } = useI18n();
  const [profile, setProfile] = useState<Profile | null>(null);
  const [fasting, setFasting] = useState<FastingState | null>(null);
  const [autoPublish, setAutoPublish] = useState(me.user.autoPublishFoods);
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [passwordStatus, setPasswordStatus] = useState("");
  const [passwordError, setPasswordError] = useState("");
  const [error, setError] = useState("");
  const pwChecks = checkSignupPassword(newPassword, confirmPassword);
  useEffect(() => {
    Promise.all([
      api<{ profile: Profile }>("/api/profile"),
      api<FastingState>("/api/fasting"),
    ]).then(([profileResponse, fastingResponse]) => {
      setProfile(profileResponse.profile);
      setFasting(fastingResponse);
    }).catch((err) => setError(message(t, err)));
  }, [t]);
  async function saveProfile(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    try {
      await api("/api/profile", {
        method: "PUT",
        body: JSON.stringify({
          sex: form.get("sex"),
          dateOfBirth: form.get("dateOfBirth"),
          heightCm: Number(form.get("heightCm")),
          weightKg: Number(form.get("weightKg")),
          activity: form.get("activity"),
          weeklyPace: form.get("weeklyPace"),
        }),
      });
    } catch (err) {
      setError(message(t, err));
    }
  }
  async function saveFasting(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const next = await api<FastingState>("/api/fasting", {
      method: "PUT",
      body: JSON.stringify({
        enabled: form.get("enabled") === "on",
        lengthHours: Number(form.get("lengthHours")),
        startHour: Number(form.get("startHour")),
      }),
    });
    setFasting(next);
    setMe({ ...me, fastingEnabled: next.enabled });
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
        <label><span>{t.language}</span>
          <select value={me.user.language} onChange={(event) => saveLanguage(event.target.value as Lang)}>
            <option value="en">{t.english}</option>
            <option value="he">{t.hebrew}</option>
          </select>
        </label>
        <label>
          <input type="checkbox" checked={autoPublish} onChange={async (event) => {
            const next = event.target.checked;
            setAutoPublish(next);
            await api("/api/profile/settings", { method: "PUT", body: JSON.stringify({ autoPublishFoods: next, language: me.user.language }) });
            setMe({ ...me, user: { ...me.user, autoPublishFoods: next } });
          }} style={{ width: "auto", marginInlineEnd: "0.5rem" }} />
          {t.autoPublish}
        </label>
      </section>
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
        {passwordStatus && <p className="rise" style={{ color: "#8fd9a8" }}>{passwordStatus}</p>}
        <button type="submit" disabled={!currentPassword || !pwChecks.valid}>{t.save}</button>
      </form>
      {profile && (
        <form className="card" onSubmit={saveProfile} key={profile.dateOfBirth}>
          <h2>{t.profileTitle}</h2>
          <ProfileFields profile={profile} />
          <button type="submit">{t.save}</button>
        </form>
      )}
      {fasting && (
        <form className="card" onSubmit={saveFasting} key={`${fasting.enabled}-${fasting.lengthHours}-${fasting.startHour}`}>
          <h2>{t.fasting}</h2>
          <label><input name="enabled" type="checkbox" defaultChecked={fasting.enabled} style={{ width: "auto", marginInlineEnd: "0.5rem" }} />{t.fastingOn}</label>
          <label><span>{t.fastingLength}</span>
            <select name="lengthHours" defaultValue={String(fasting.lengthHours)}>
              <option value="12">12</option>
              <option value="14">14</option>
              <option value="16">16</option>
            </select>
          </label>
          <HourField name="startHour" label={t.startHour} defaultValue={fasting.startHour} />
          <p className="muted">{t.endHour}: {hourLabel(fasting.endHour)}</p>
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
                  style={{ width: "auto" }}
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
    const body = {
      barcode: String(form.get("barcode") ?? barcode),
      name: form.get("name"),
      basis: form.get("basis"),
      calories: Number(form.get("calories")),
      protein: Number(form.get("protein")),
      carbohydrates: Number(form.get("carbohydrates")),
      fat: Number(form.get("fat")),
      fiber: Number(form.get("fiber")),
      sugars: Number(form.get("sugars")),
      sodium: Number(form.get("sodium")),
    };
    try {
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
      <label><span>{t.solid}</span>
        <select name="basis" defaultValue={food?.basis ?? "solid"}>
          <option value="solid">{t.solid}</option>
          <option value="liquid">{t.liquid}</option>
        </select>
      </label>
      {(["calories", "protein", "carbohydrates", "fat", "fiber", "sugars", "sodium"] as const).map((field) => (
        <label key={field}><span>{t[field]}</span><input name={field} defaultValue={food?.[field] ?? 0} inputMode="decimal" required /></label>
      ))}
      {error && <p className="error">{error}</p>}
      <button type="submit">{t.save}</button>
      {id && food?.owned && (
        <button type="button" className="secondary" style={{ marginInlineStart: "0.5rem" }} onClick={async () => {
          await api(`/api/foods/${id}/${food.published ? "unpublish" : "publish"}`, { method: "POST" });
          setFood({ ...food, published: !food.published });
        }}>{food.published ? t.unpublish : t.publish}</button>
      )}
    </form>
  );
}

function ProfileFields({ profile }: { profile?: Profile }) {
  const { t } = useI18n();
  return (
    <>
      <label><span>{t.sex}</span>
        <select name="sex" defaultValue={profile?.sex ?? "female"}>
          <option value="female">{t.female}</option>
          <option value="male">{t.male}</option>
        </select>
      </label>
      <label><span>{t.dateOfBirth}</span><input name="dateOfBirth" type="date" defaultValue={profile?.dateOfBirth} required /></label>
      <label><span>{t.height}</span><input name="heightCm" inputMode="decimal" defaultValue={profile?.heightCm} required /></label>
      <label><span>{t.weightKg}</span><input name="weightKg" inputMode="decimal" defaultValue={profile?.weightKg} required /></label>
      <label><span>{t.activity}</span>
        <select name="activity" defaultValue={profile?.activity ?? "sedentary"}>
          <option value="sedentary">{t.sedentary}</option>
          <option value="light">{t.light}</option>
          <option value="moderate">{t.moderate}</option>
          <option value="very">{t.very}</option>
          <option value="extra">{t.extra}</option>
        </select>
      </label>
      <label><span>{t.pace}</span>
        <select name="weeklyPace" defaultValue={profile?.weeklyPace ?? "kg050"}>
          <option value="kg025">{t.pace025}</option>
          <option value="kg050">{t.pace050}</option>
          <option value="kg100">{t.pace100}</option>
        </select>
      </label>
    </>
  );
}

function HourField({ name, label, defaultValue, value, onChange }: { name: string; label: string; defaultValue?: number; value?: number; onChange?: (hour: number) => void }) {
  return (
    <label><span>{label}</span>
      <select
        name={name}
        defaultValue={value == null ? String(defaultValue ?? 0) : undefined}
        value={value == null ? undefined : String(value)}
        onChange={onChange ? (event) => onChange(Number(event.target.value)) : undefined}
      >
        {Array.from({ length: 24 }, (_, hour) => <option key={hour} value={hour}>{hourLabel(hour)}</option>)}
      </select>
    </label>
  );
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
