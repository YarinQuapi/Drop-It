import { useEffect, useState, type FormEvent } from "react";
import { Link, NavLink, Navigate, Route, Routes, useNavigate, useParams, useSearchParams } from "react-router-dom";
import {
  api,
  ApiError,
  type DayResponse,
  type FastingState,
  type Food,
  type Me,
  type Profile,
  type WeekResponse,
  type WeightPoint,
} from "./api";
import { addDays, formatJerusalem, hourLabel, msUntilHour } from "./clock";
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

  if (me === undefined) return <main className="shell"><p className="muted">…</p></main>;

  return (
    <Routes>
      <Route path="/login" element={<AuthPage mode="login" onAuth={setMe} />} />
      <Route path="/signup" element={<AuthPage mode="signup" onAuth={setMe} />} />
      <Route path="/setup/fasting" element={me ? <FastingSetup onDone={() => setMe({ ...me })} /> : <Navigate to="/login" />} />
      <Route path="/setup/profile" element={me ? <ProfileSetup onDone={(next) => setMe(next)} /> : <Navigate to="/login" />} />
      <Route path="/*" element={me ? <Shell me={me} setMe={setMe} /> : <Navigate to="/login" />} />
    </Routes>
  );
}

function Shell({ me, setMe }: { me: Me; setMe: (me: Me | null) => void }) {
  const { t } = useI18n();
  if (!me.hasProfile && !location.pathname.startsWith("/setup")) {
    return <Navigate to="/setup/fasting" />;
  }
  return (
    <div className="shell">
      <nav className="nav">
        <strong>{t.appName}</strong>
        <NavLink to="/" end>{t.today}</NavLink>
        <NavLink to="/week">{t.week}</NavLink>
        <NavLink to="/weight">{t.weight}</NavLink>
        <NavLink to="/settings">{t.settings}</NavLink>
        <button className="secondary spacer" onClick={async () => { await api("/api/auth/logout", { method: "POST" }); setMe(null); }}>{t.logout}</button>
      </nav>
      <Routes>
        <Route path="/" element={<Today admin={me.user.isAdmin} />} />
        <Route path="/week" element={<WeekPage />} />
        <Route path="/weight" element={<WeightPage />} />
        <Route path="/settings" element={<SettingsPage me={me} setMe={setMe} />} />
        <Route path="/foods/new" element={<FoodForm />} />
        <Route path="/foods/:id" element={<FoodForm />} />
      </Routes>
    </div>
  );
}

function AuthPage({ mode, onAuth }: { mode: "login" | "signup"; onAuth: (me: Me) => void }) {
  const { t, lang } = useI18n();
  const navigate = useNavigate();
  const [error, setError] = useState("");
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    try {
      await api(mode === "login" ? "/api/auth/login" : "/api/auth/signup", {
        method: "POST",
        body: JSON.stringify({
          email: form.get("email"),
          password: form.get("password"),
          language: lang,
        }),
      });
      const me = await api<Me>("/api/auth/me");
      onAuth(me);
      navigate(mode === "signup" || !me.hasProfile ? "/setup/fasting" : "/");
    } catch (err) {
      setError(message(t, err));
    }
  }
  return (
    <main className="shell">
      <form className="card" onSubmit={submit}>
        <h1>{mode === "login" ? t.login : t.signup}</h1>
        <label><span>{t.email}</span><input name="email" type="email" required /></label>
        <label><span>{t.password}</span><input name="password" type="password" minLength={8} required /></label>
        {error && <p className="error">{error}</p>}
        <button type="submit">{mode === "login" ? t.login : t.signup}</button>
        <p>{mode === "login" ? <Link to="/signup">{t.needAccount}</Link> : <Link to="/login">{t.haveAccount}</Link>}</p>
      </form>
    </main>
  );
}

function FastingSetup({ onDone }: { onDone: () => void }) {
  const { t } = useI18n();
  const navigate = useNavigate();
  const [wants, setWants] = useState<boolean | null>(null);
  const [error, setError] = useState("");
  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    try {
      await api("/api/fasting", {
        method: "PUT",
        body: JSON.stringify({
          enabled: wants === true,
          lengthHours: Number(form.get("lengthHours") ?? 16),
          startHour: Number(form.get("startHour") ?? 20),
          endHour: Number(form.get("endHour") ?? 12),
        }),
      });
      onDone();
      navigate("/setup/profile");
    } catch (err) {
      setError(message(t, err));
    }
  }
  return (
    <main className="shell">
      <form className="card" onSubmit={save}>
        <h1>{t.fastingQuestion}</h1>
        <div className="row">
          <button type="button" className={wants === true ? "" : "secondary"} onClick={() => setWants(true)}>{t.yes}</button>
          <button type="button" className={wants === false ? "" : "secondary"} onClick={() => setWants(false)}>{t.no}</button>
        </div>
        {wants && (
          <>
            <label><span>{t.fastingLength}</span>
              <select name="lengthHours" defaultValue="16">
                <option value="12">12 {t.hours}</option>
                <option value="14">14 {t.hours}</option>
                <option value="16">16 {t.hours}</option>
              </select>
            </label>
            <HourField name="startHour" label={t.startHour} defaultValue={20} />
            <HourField name="endHour" label={t.endHour} defaultValue={12} />
          </>
        )}
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
    <main className="shell">
      <form className="card" onSubmit={save}>
        <h1>{t.profileTitle}</h1>
        <ProfileFields />
        {error && <p className="error">{error}</p>}
        <button type="submit">{t.save}</button>
      </form>
    </main>
  );
}

function Today({ admin }: { admin: boolean }) {
  const { t } = useI18n();
  const [day, setDay] = useState<DayResponse | null>(null);
  const [fasting, setFasting] = useState<FastingState | null>(null);
  const [barcode, setBarcode] = useState("");
  const [lookup, setLookup] = useState<{ status: string; food: Food | null; foods: Food[] } | null>(null);
  const [picked, setPicked] = useState<Food | null>(null);
  const [amount, setAmount] = useState("100");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [now, setNow] = useState(Date.now());

  async function reload() {
    const [nextDay, nextFast] = await Promise.all([
      api<DayResponse>("/api/days/today"),
      api<FastingState>("/api/fasting"),
    ]);
    setDay(nextDay);
    setFasting(nextFast);
  }

  useEffect(() => {
    reload().catch((err) => setError(message(t, err)));
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

  async function findFood(event: FormEvent) {
    event.preventDefault();
    setError("");
    const result = await api<{ status: string; food: Food | null; foods: Food[] }>(`/api/foods/barcode/${encodeURIComponent(barcode.trim())}`);
    setLookup(result);
    setPicked(result.food);
  }

  async function addFood(event: FormEvent) {
    event.preventDefault();
    if (!picked) return;
    try {
      await api(`/api/days/today/entries`, {
        method: "POST",
        body: JSON.stringify({ foodId: picked.id, amount: Number(amount) }),
      });
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

  async function toggleTimer() {
    if (!fasting) return;
    try {
      const next = await api<FastingState>(fasting.running ? "/api/fasting/stop" : "/api/fasting/start", { method: "POST" });
      setFasting(next);
    } catch (err) {
      setError(message(t, err));
    }
  }

  const remaining = day ? day.goalKcal - day.totals.calories : 0;
  const left = fasting?.running && fasting.endsAt ? Math.max(0, new Date(fasting.endsAt).getTime() - now) : 0;

  return (
    <>
      {day && (
        <section className="card">
          <h1>{t.today}</h1>
          <div className="stats">
            <div className="stat"><span>{t.goal}</span><b>{day.goalKcal}</b></div>
            <div className="stat"><span>{t.eaten}</span><b>{day.totals.calories}</b></div>
            <div className="stat"><span>{t.remaining}</span><b>{Math.round(remaining)}</b></div>
          </div>
          <p className="muted">{t.estimate}</p>
          <div className="nutrients">
            <span>{t.protein}: {day.totals.protein}</span>
            <span>{t.carbohydrates}: {day.totals.carbohydrates}</span>
            <span>{t.fat}: {day.totals.fat}</span>
            <span>{t.fiber}: {day.totals.fiber}</span>
            <span>{t.sugars}: {day.totals.sugars}</span>
            <span>{t.sodium}: {day.totals.sodium}</span>
          </div>
        </section>
      )}
      {fasting && (
        <section className="card">
          <h2>{t.fasting}</h2>
          {fasting.enabled ? (
            <>
              <p>{t.scheduled}: {hourLabel(fasting.startHour)} – {hourLabel(fasting.endHour)} · {fasting.lengthHours} {t.hours}</p>
              {fasting.running && <p>{t.timeLeft}: {formatDuration(left)}</p>}
              <button onClick={toggleTimer}>{fasting.running ? t.stopFast : t.startFast}</button>
              <button className="secondary" style={{ marginInlineStart: "0.5rem" }} onClick={() => Notification.requestPermission()}>{t.notify}</button>
            </>
          ) : <p className="muted">{t.fastingQuestion}</p>}
          {notice && <p>{notice}</p>}
        </section>
      )}
      <section className="card">
        <form onSubmit={findFood} className="row">
          <label><span>{t.barcode}</span><input value={barcode} onChange={(event) => setBarcode(event.target.value)} required /></label>
          <button type="submit">{t.lookUp}</button>
        </form>
        {lookup?.status === "none" && (
          <p>{t.noFood} <Link to={`/foods/new?barcode=${encodeURIComponent(barcode)}`}>{t.createFood}</Link></p>
        )}
        {lookup?.status === "list" && (
          <div>
            <h2>{t.chooseFood}</h2>
            {lookup.foods.map((food) => (
              <button key={food.id} className="secondary" onClick={() => setPicked(food)}>{food.name}{food.verified ? ` · ${t.verified}` : ""}</button>
            ))}
          </div>
        )}
        {picked && (
          <form onSubmit={addFood}>
            <p><strong>{picked.name}</strong> · {picked.owned ? t.personal : ""} {picked.verified ? t.verified : ""}</p>
            <p className="muted">{picked.calories} kcal / 100 {picked.basis === "solid" ? t.grams : t.milliliters}</p>
            <label><span>{t.amount} ({picked.basis === "solid" ? t.grams : t.milliliters})</span>
              <input value={amount} onChange={(event) => setAmount(event.target.value)} inputMode="decimal" required />
            </label>
            <button type="submit">{t.add}</button>
            {picked.owned && <Link className="secondary" to={`/foods/${picked.id}`} style={{ marginInlineStart: "0.5rem" }}>{t.edit}</Link>}
            {!picked.owned && <Link className="secondary" to={`/foods/${picked.id}`} style={{ marginInlineStart: "0.5rem" }}>{t.edit}</Link>}
            {admin && picked.published && !picked.verified && (
              <button type="button" className="secondary" style={{ marginInlineStart: "0.5rem" }} onClick={async () => {
                const result = await api<{ food: Food }>(`/api/foods/${picked.id}/verify`, { method: "POST" });
                setPicked(result.food);
              }}>{t.verify}</button>
            )}
          </form>
        )}
        {error && <p className="error">{error}</p>}
      </section>
      <section className="card">
        {day && day.entries.length === 0 && <p className="muted">{t.emptyDay}</p>}
        {day?.entries.map((entry) => (
          <div className="entry" key={entry.id}>
            <div>
              <strong>{entry.name}</strong>
              <div className="muted">{entry.amount} {entry.basis === "solid" ? t.grams : t.milliliters} · {entry.calories} kcal</div>
            </div>
            <button className="danger" onClick={() => remove(entry.id)}>{t.delete}</button>
          </div>
        ))}
      </section>
    </>
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
  if (!week) return error ? <p className="error">{error}</p> : <p className="muted">…</p>;
  return (
    <section className="card">
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
      <polyline fill="none" stroke="#1f7a4d" strokeWidth="3" points={points} />
      {points.split(" ").map((pair) => {
        const [x, y] = pair.split(",");
        return <circle key={pair} cx={x} cy={y} r="4" fill="#1f7a4d" />;
      })}
    </svg>
  );
}

function SettingsPage({ me, setMe }: { me: Me; setMe: (me: Me) => void }) {
  const { t, setLang } = useI18n();
  const [profile, setProfile] = useState<Profile | null>(null);
  const [fasting, setFasting] = useState<FastingState | null>(null);
  const [autoPublish, setAutoPublish] = useState(me.user.autoPublishFoods);
  const [error, setError] = useState("");
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
        endHour: Number(form.get("endHour")),
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
          <HourField name="endHour" label={t.endHour} defaultValue={fasting.endHour} />
          <button type="submit">{t.save}</button>
        </form>
      )}
      {error && <p className="error">{error}</p>}
    </>
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

function HourField({ name, label, defaultValue }: { name: string; label: string; defaultValue: number }) {
  return (
    <label><span>{label}</span>
      <select name={name} defaultValue={String(defaultValue)}>
        {Array.from({ length: 24 }, (_, hour) => <option key={hour} value={hour}>{hourLabel(hour)}</option>)}
      </select>
    </label>
  );
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
