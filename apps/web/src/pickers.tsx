import { useEffect, useId, useRef, useState, type CSSProperties } from "react";
import { createPortal } from "react-dom";
import { useI18n, type Lang } from "./i18n";

export type MenuOption = { value: string; label: string };

type Anchor = { top: number; left: number; width: number; maxHeight: number; openUp: boolean };

function useAnchoredMenu(open: boolean) {
  const rootRef = useRef<HTMLDivElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const closeRef = useRef<() => void>(() => {});
  const [anchor, setAnchor] = useState<Anchor | null>(null);

  useEffect(() => {
    if (!open) return;
    const place = () => {
      const trigger = rootRef.current?.querySelector("button");
      if (!trigger) return;
      const box = trigger.getBoundingClientRect();
      const margin = 8;
      const below = window.innerHeight - box.bottom - margin;
      const above = box.top - margin;
      const openUp = below < 220 && above > below;
      setAnchor({
        top: openUp ? box.top : box.bottom,
        left: box.left,
        width: box.width,
        maxHeight: Math.max(160, (openUp ? above : below) - margin),
        openUp,
      });
    };
    place();
    window.addEventListener("resize", place);
    window.addEventListener("scroll", place, true);
    return () => {
      window.removeEventListener("resize", place);
      window.removeEventListener("scroll", place, true);
    };
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const onPointerDown = (event: PointerEvent) => {
      const target = event.target as Node;
      if (rootRef.current?.contains(target) || panelRef.current?.contains(target)) return;
      closeRef.current();
    };
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") closeRef.current();
    };
    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  return { rootRef, panelRef, anchor, closeRef };
}

function panelStyle(anchor: Anchor): CSSProperties {
  return {
    position: "fixed",
    left: anchor.left,
    width: anchor.width,
    maxHeight: anchor.maxHeight,
    zIndex: 180,
    top: anchor.openUp ? undefined : anchor.top + 4,
    bottom: anchor.openUp ? window.innerHeight - anchor.top + 4 : undefined,
  };
}

export function MenuField({
  name,
  label,
  options,
  value,
  defaultValue,
  onChange,
}: {
  name?: string;
  label: string;
  options: MenuOption[];
  value?: string;
  defaultValue?: string;
  onChange?: (value: string) => void;
}) {
  const listId = useId();
  const labelId = useId();
  const valueId = useId();
  const controlled = value != null;
  const [internal, setInternal] = useState(defaultValue ?? options[0]?.value ?? "");
  const selected = controlled ? value : internal;
  const [open, setOpen] = useState(false);
  const { rootRef, panelRef, anchor, closeRef } = useAnchoredMenu(open);
  closeRef.current = () => setOpen(false);
  const current = options.find((option) => option.value === selected) ?? options[0];

  function choose(next: string) {
    if (!controlled) setInternal(next);
    onChange?.(next);
    setOpen(false);
  }

  return (
    <div className="picker" ref={rootRef}>
      <span className="label" id={labelId}>{label}</span>
      <button
        type="button"
        className="picker-trigger"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={listId}
        aria-labelledby={`${labelId} ${valueId}`}
        onClick={() => setOpen((currentOpen) => !currentOpen)}
      >
        <span id={valueId}>{current?.label}</span>
        <Chevron />
      </button>
      {name && <input type="hidden" name={name} value={selected} />}
      {open && anchor && createPortal(
        <div className="picker-menu" ref={panelRef} style={panelStyle(anchor)}>
          <ul id={listId} role="listbox" aria-labelledby={labelId}>
            {options.map((option) => (
              <li key={option.value} role="none">
                <button
                  type="button"
                  role="option"
                  className="picker-option"
                  aria-selected={option.value === selected}
                  onClick={() => choose(option.value)}
                >
                  {option.label}
                </button>
              </li>
            ))}
          </ul>
        </div>,
        document.body,
      )}
    </div>
  );
}

function Chevron() {
  return (
    <svg className="picker-chevron" width="12" height="8" viewBox="0 0 12 8" aria-hidden="true">
      <path d="M1 1.5l5 5 5-5" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function toIso(date: Date): string {
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${date.getFullYear()}-${month}-${day}`;
}

function parseIso(value: string): Date | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return null;
  const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  if (date.getFullYear() !== Number(match[1]) || date.getMonth() !== Number(match[2]) - 1 || date.getDate() !== Number(match[3])) return null;
  return date;
}

function startOfToday(): Date {
  const today = new Date();
  return new Date(today.getFullYear(), today.getMonth(), today.getDate());
}

function formatBirthDate(iso: string, lang: Lang): string {
  const date = parseIso(iso);
  if (!date) return iso;
  return new Intl.DateTimeFormat(lang === "he" ? "he-IL" : "en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
  }).format(date);
}

export function DateField({ name, label, defaultValue }: { name: string; label: string; defaultValue?: string }) {
  const { t, lang } = useI18n();
  const labelId = useId();
  const valueId = useId();
  const [value, setValue] = useState(defaultValue ?? "");
  const [open, setOpen] = useState(false);
  const { rootRef, panelRef, anchor, closeRef } = useAnchoredMenu(open);
  closeRef.current = () => setOpen(false);

  return (
    <div className="picker" ref={rootRef}>
      <span className="label" id={labelId}>{label}</span>
      <button
        type="button"
        className="picker-trigger"
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-labelledby={`${labelId} ${valueId}`}
        onClick={() => setOpen((currentOpen) => !currentOpen)}
      >
        <span id={valueId} className={value ? undefined : "placeholder"}>
          {value ? formatBirthDate(value, lang) : t.chooseDate}
        </span>
        <Chevron />
      </button>
      <input type="hidden" name={name} value={value} />
      {open && anchor && createPortal(
        <div
          className="picker-menu calendar"
          ref={panelRef}
          style={{ ...panelStyle(anchor), height: Math.min(anchor.maxHeight, 380) }}
          role="dialog"
          aria-label={label}
        >
          <Calendar
            value={value}
            lang={lang}
            onChange={(next) => {
              setValue(next);
              setOpen(false);
            }}
          />
        </div>,
        document.body,
      )}
    </div>
  );
}

function Calendar({ value, lang, onChange }: { value: string; lang: Lang; onChange: (iso: string) => void }) {
  const { t } = useI18n();
  const today = startOfToday();
  const selected = parseIso(value);
  const initial = selected ?? new Date(today.getFullYear() - 25, today.getMonth(), 1);
  const [cursor, setCursor] = useState(() => new Date(initial.getFullYear(), initial.getMonth(), 1));
  const [pickingYear, setPickingYear] = useState(!selected);
  const selectedYearRef = useRef<HTMLButtonElement>(null);
  const locale = lang === "he" ? "he-IL" : "en-GB";
  const monthLabel = new Intl.DateTimeFormat(locale, { month: "long", year: "numeric" }).format(cursor);
  const weekday = new Intl.DateTimeFormat(locale, { weekday: "narrow" });
  const weekdays = Array.from({ length: 7 }, (_, index) => weekday.format(new Date(2023, 0, 1 + index)));
  const min = new Date(1900, 0, 1);
  const years = Array.from({ length: today.getFullYear() - 1899 }, (_, index) => today.getFullYear() - index);

  useEffect(() => {
    const node = selectedYearRef.current;
    const list = node?.closest(".year-list");
    if (!node || !(list instanceof HTMLElement)) return;
    const align = () => {
      const top = node.getBoundingClientRect().top - list.getBoundingClientRect().top + list.scrollTop;
      list.scrollTop = top - list.clientHeight / 2 + node.clientHeight / 2;
    };
    align();
    const frame = requestAnimationFrame(align);
    return () => cancelAnimationFrame(frame);
  }, [pickingYear]);

  function shiftMonth(delta: number) {
    const next = new Date(cursor.getFullYear(), cursor.getMonth() + delta, 1);
    if (next < min || next > new Date(today.getFullYear(), today.getMonth(), 1)) return;
    setCursor(next);
  }

  const first = new Date(cursor.getFullYear(), cursor.getMonth(), 1);
  const gridStart = new Date(cursor.getFullYear(), cursor.getMonth(), 1 - first.getDay());
  const days = Array.from({ length: 42 }, (_, index) => new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + index));

  return (
    <>
      <div className="calendar-head">
        <button type="button" className="calendar-nav" aria-label={t.prevMonth} onClick={() => shiftMonth(-1)}>
          <span className="chevron prev" />
        </button>
        <button type="button" className="calendar-title" aria-expanded={pickingYear} onClick={() => setPickingYear((open) => !open)}>
          {pickingYear ? t.chooseYear : monthLabel}
        </button>
        <button type="button" className="calendar-nav" aria-label={t.nextMonth} onClick={() => shiftMonth(1)}>
          <span className="chevron next" />
        </button>
      </div>
      {pickingYear ? (
        <ul className="year-list calendar-body">
          {years.map((year) => (
            <li key={year}>
              <button
                type="button"
                ref={year === cursor.getFullYear() ? selectedYearRef : undefined}
                className="picker-option"
                aria-selected={year === cursor.getFullYear()}
                onClick={() => {
                  setCursor(new Date(year, cursor.getMonth(), 1));
                  setPickingYear(false);
                }}
              >
                {year}
              </button>
            </li>
          ))}
        </ul>
      ) : (
        <div className="calendar-grid calendar-body">
          {weekdays.map((name, index) => <span className="calendar-dow" key={index}>{name}</span>)}
          {days.map((day) => {
            const iso = toIso(day);
            const outside = day.getMonth() !== cursor.getMonth();
            const disabled = day < min || day > today;
            const pressed = iso === value;
            return (
              <button
                type="button"
                key={iso}
                className={outside ? "calendar-day outside" : "calendar-day"}
                disabled={disabled}
                aria-pressed={pressed}
                aria-current={iso === toIso(today) ? "date" : undefined}
                onClick={() => onChange(iso)}
              >
                {day.getDate()}
              </button>
            );
          })}
        </div>
      )}
    </>
  );
}
