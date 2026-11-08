# Agent Guidelines - Drop It

Monorepo: `apps/api` (API), `apps/web` (React + Vite), `apps/mobile` (Flutter).

## Design system: Apple HIG (mandatory for all UI work)

Web and mobile share one Apple Human Interface Guidelines design system with adaptive appearance: **System (default), Light, Dark** (user-selectable in Settings on both platforms).

Full rules: [.cursor/rules/apple-hig-design.mdc](.cursor/rules/apple-hig-design.mdc). Source of truth for tokens:
- Web: [apps/web/src/styles.css](apps/web/src/styles.css) (CSS variables), theme state in [apps/web/src/i18n.tsx](apps/web/src/i18n.tsx) (`ThemeProvider`, `useTheme`).
- Mobile: [apps/mobile/lib/theme.dart](apps/mobile/lib/theme.dart) (`AppleColors`, `Radii`, `Gaps`, `buildAppleTheme`, `AppList`), wired in [apps/mobile/lib/main.dart](apps/mobile/lib/main.dart).

Quick rules:
1. No hardcoded colors; use semantic tokens (`var(--accent-primary)`, `context.apple.accentPrimary`).
2. Radii: 10 (segmented/tiles), 12 (buttons/inputs), 16 (cards), 20 (sheets/hero), pill for chips.
3. 8pt spacing grid: 8/12/16 gaps, 16px page and card padding, 44px minimum touch target, 0.5px separators.
4. System blue accent (#007AFF / #0A84FF); orange for calorie/fasting energy; green success; red danger.
5. Translucent blurred top and tab bars (no hamburger drawer), iOS-style switches, segmented controls.
6. Every user-facing string exists in English and Hebrew; support RTL.

When changing the design system, update both platforms and `.cursor/rules/apple-hig-design.mdc` together.
