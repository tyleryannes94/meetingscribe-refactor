# Handoff: MeetingScribe — "Bloom" Visual Overhaul

## Overview
This is a **whole-app visual overhaul** of MeetingScribe in **dark mode**, internal codename **Bloom**:
playful, friendly, warm. It keeps the existing information architecture and feature set 100%
intact — only the **look** changes. Same five top-level sections (Today · Meetings · People ·
Tasks · Voice Notes), same chat rail, same detail panes. The job is to retune the design system
and restyle the surfaces — not to rebuild functionality.

## About the Design Files
The files in `designs/` are **design references created in HTML/CSS** — prototypes that show the
intended look and behavior. **They are not production code to copy.** MeetingScribe is a **SwiftUI
macOS app** with a mature design system already in place (`Sources/MeetingScribe/UI/NotionDesign.swift`,
the `NDS` enum, plus `MSComponents.swift`). The task is to **recreate the Bloom look inside that
existing SwiftUI environment** by:

1. Retuning the `NDS` tokens (color, radius, type, motion) to the Bloom values below.
2. Adjusting the shared components (`MSPrimaryButtonStyle`, `NotionChip`, `MSCard`, `MSAvatar`,
   badges, nav rail) to the Bloom component specs.
3. Letting those token + component changes cascade across every screen — most surfaces already
   consume `NDS`, so the bulk of the work is centralized.

Open the HTML files in a browser to see each screen. `designs/bloom.css` is the single source of
truth for every token and component style; the per-screen HTML files show composition.

## Fidelity
**High-fidelity (hifi).** Final colors, typography, spacing, radii, and component styling are all
specified exactly below and in `bloom.css`. Recreate pixel-faithfully using SwiftUI + the existing
component layer. The HTML uses generic feather-style SVG icons as stand-ins — **in the app, keep
using SF Symbols** (the existing `systemImage` names are correct); the SVGs only indicate which
glyph goes where.

---

## Design Tokens

All values are from `designs/bloom.css` `:root`. Map these onto `NDS` (which currently uses a warm
near-black + purple). Bloom is dark-mode-first; provide a light variant later if needed, but the
design target is dark.

### Color — surfaces & text
| Token (CSS var) | Hex / value | Role | Maps to NDS |
|---|---|---|---|
| `--bg` | `#15121a` | App background (plum-ink) | `NDS.bg` (dark tuple) |
| `--sidebar` | `#100d15` | Nav rail + titlebar | `NDS.sidebarBg` |
| `--surface` | `#1e1925` | Cards, fields, list rows | `NDS.fieldBg` / card fill |
| `--surface-2` | `#271f31` | Elevated / hover / gray chips | `NDS.rowHover` family |
| `--line` | `rgba(245,238,250,.09)` | Hairline dividers/borders | `NDS.divider` |
| `--line-2` | `rgba(245,238,250,.16)` | Stronger border (buttons, checkbox) | `NDS.hairline` |
| `--txt` | `#f3eef6` | Primary text | `NDS.textPrimary` |
| `--txt-2` | `rgba(243,238,246,.68)` | Secondary text | `NDS.textSecondary` |
| `--txt-3` | `rgba(243,238,246,.44)` | Tertiary / faint | `NDS.textTertiary` |

### Color — accents (the heart of Bloom)
| Token | Hex | Role |
|---|---|---|
| `--accent` (coral) | `#ff9173` | **Primary CTAs**, active tab, brand mark, ambient glow. Use the gradient below for fills. |
| `--accent-2` | `#f06a4c` | Coral gradient end |
| Coral gradient | `linear-gradient(135deg,#ff9173,#f06a4c)` | Primary button & active-tab fill |
| `--accent-soft` | `rgba(255,145,115,.16)` | Coral tint (Up-Next border, message bars) |
| `--lilac` | `#b79cff` | **Brand / nav** accent — active nav item icon, selection, "New page" |
| `--lilac-soft` | `rgba(183,156,255,.16)` | Nav active bg, selected-row bg |
| `--mint` | `#74e0bc` | Success / "done" / positive |
| `--sky` | `#8ab4ff` | Info / "in progress" / neutral-positive |
| `--gold` | `#ffce6b` | Warning / "due today" / voice-note |

### Color — semantic (pair every color with a glyph; never color-only)
| Token | Hex | Meaning |
|---|---|---|
| `--ok` | `#74e0bc` | Completed / healthy |
| `--info` | `#8ab4ff` | Open / in progress |
| `--warn` | `#ffce6b` | Due today |
| `--danger` | `#ff7a8a` | Overdue / high priority / destructive |

Priority bars on task cards: Low = none/hidden, Med = `--warn`, High = `--danger`. These replace
`NDS.priority()`/`status()`/`due()` color outputs — keep the function shape, swap the hexes.

### Radius
| Token | Value | Use |
|---|---|---|
| `--r-card` | **20px** | Cards (`NDS.cardRadius` 12 → **20**) |
| `--r-ctl` | **14px** | Buttons, fields (`NDS.radius` 8 → **14**) |
| pill | `999px` | Chips, badges, nav items, tabs, segmented control |
| avatar | `34%` (squircle) | `MSAvatar` — **not** a full circle |

Bloom is noticeably **chunkier/rounder** than the current build — this is intentional and central to
the personality.

### Typography
| Family | Use | Notes |
|---|---|---|
| **Bricolage Grotesque** | Display: page titles (`h1`), brand wordmark, big numbers | Weights 600/700/800. This is the only net-new dependency. |
| **Plus Jakarta Sans** | Body, labels, everything else | Weights 400/500/600/700/800 |

Type scale (default size; keep Dynamic-Type scaling via `scaledFont`):
- Page title (`h1`): **30px / 800 / -0.8px tracking** (Bricolage). Detail titles 25px/800.
- Section card title (`b`): 14px / 700 (Jakarta)
- Body: 13.5–14px / 1.5 line-height
- Eyebrow label: **11px / 700 / 0.8px tracking / uppercase**, color `--txt-3`
- Meta / faint: 11.5–12px

> SwiftUI note: register the two fonts in `Info.plist` (`ATSApplicationFontsPath`) or bundle them;
> wire them into the `NDS` font tokens (`title`, `pageTitle`, `body`, etc.). Headlines use Bricolage,
> all else Plus Jakarta Sans. Keep the `scaledFont` Dynamic-Type wrapper.

### Spacing
Unchanged from current `NDS` scale: **4 · 8 · 12 · 16 · 24 · 32**. Page padding 26–30px; card inner
padding 13–16px; gaps between cards 9–14px.

### Shadow / glow (new, signature to Bloom)
- Primary button: `box-shadow: 0 4px 16px rgba(255,145,115,.32)` (coral glow).
- Brand mark tile: `0 4px 14px rgba(255,145,115,.3)`.
- **Ambient corner glow** on the main content area: a soft radial coral light, top-right.
  CSS: `radial-gradient(circle, rgba(255,145,115,.10), transparent 70%)`, ~420×320px, offset
  off the top-right corner. In SwiftUI: a blurred coral `RadialGradient` in a `.background`/overlay
  behind the content, clipped, very low opacity. Subtle — it must not compete with content.

---

## Components

All component specs live in `designs/bloom.css`. Key ones:

### Primary button (`MSPrimaryButtonStyle`)
- Fill: coral gradient `135deg #ff9173 → #f06a4c`; text `#2a1208` (near-black warm), weight **700**.
- Radius 14, padding 9×15 (block variant 12px tall-ish, centered, 14.5px text).
- Coral drop-glow shadow (above). Press: scale 0.97 + slightly dim — keep the existing
  `.easeOut(0.1)` press animation but add a gentle spring scale.

### Secondary / ghost / danger buttons
- Secondary: `--surface` fill, `--line-2` border, `--txt` label, radius 14.
- Ghost: transparent, `--txt-2`, hover → `--surface`.
- Danger: `--danger` fill, dark text.

### Pills (quick-action row)
- Fully rounded, weight 700, tinted by purpose: Voice note = gold tint, New task = mint tint,
  New page = lilac tint. Icon + label. (See `.pill` in CSS + Today screen.)

### Chips (`NotionChip`) & Badges
- Chip: fully rounded, 11.5px/700, padding 4×11, low-alpha tint + saturated text. Tag chips use the
  `t-iris`(lilac)/`t-ok`(mint)/`t-info`(sky)/`t-gray` classes.
- Badge: same but smaller (11px, padding 3×9), used for status/due/priority. **Always icon + label**
  (color-blind safe): Overdue = danger + up-chevron/!, Today = gold + clock, Done = mint + check,
  In progress = sky.

### Avatars (`MSAvatar`)
- **Squircle** (`border-radius: 34%`), gradient fill, 800-weight monogram in dark text `#241636`.
- Stack: `-8px` overlap, 2.5px border in surface color.
- Per-person gradient (deterministic by name); palette pairs used in mocks:
  coral `#ff9173→#f06a4c`, mint `#74e0bc→#46c79f`, lilac `#b79cff→#9a7af0`, sky `#8ab4ff→#6b96ec`,
  gold `#ffce6b→#f0b43f`.

### Nav rail item (`NavRailItem`)
- **Pill-shaped** (fully rounded), 8×12 padding, margin 2×9.
- Active: `--lilac-soft` bg, `--txt` label weight 700, icon tinted `--lilac`.
- Hover: `--lilac-soft` bg. Count badge: rounded pill, `--surface` bg.
- Brand wordmark in Bricolage; brand mark is a 26px rounded tile with coral→lilac gradient + glow.

### Cards (`MSCard`)
- `--surface` fill, `--line` border, **radius 20**. Hover → `--line-2` border.
- **Tinted-header variant** (new): a card whose header strip carries a soft gradient tint
  (`linear-gradient(135deg, rgba(255,145,115,.22), rgba(183,156,255,.18))`) with a dot + label,
  body below. Use for "Up next" and other hero cards. See language card + meeting screens.

### Tabs (meeting detail)
- **Pill tabs**, not underline. Active tab = coral gradient fill + dark text; inactive = `--txt-2`,
  hover surface. (Replaces the current underlined `.tab`.)

### Segmented control (appearance Light/Dark, view switcher)
- Fully rounded track (`--surface`), rounded thumb (`--surface-2`), active label weight 700.

---

## Screens / Views

> Layouts and IA are **unchanged from the current app** — these notes describe how each restyles.
> Reference the matching HTML in `designs/`.

### 1. Today — `bloom-today.html`
- **Purpose:** home/dashboard.
- **Layout:** nav rail (234px) + main. Main = page padding 26×30, header row, then a **two-column
  feed**: left (flex 1.5) = primary "Record Meeting" block button → quick-action pill row (Voice
  note/New task/New page) → tinted "UP NEXT" card → "TODAY" meeting cards; right (flex 1) =
  "Needs attention", "Commitments", "On this day" cards.
- **Components:** block primary button (coral gradient, full width, 12px tall), pills, Up-Next card
  with coral border + Join&record primary + Open secondary, meeting rows (squircle avatar +
  title/meta + tag chip + chevron), attention rows (colored dot + label + due badge), commitment
  fields, on-this-day rows.
- **Copy:** exact strings in the HTML (e.g. "Monday, Jun 9", "2 upcoming today · 1 earlier today",
  "UP NEXT / Product Sync — Skio / Starts in 18 minutes · Google Meet").

### 2. Meeting detail — `bloom-meeting.html`
- **Purpose:** review a meeting.
- **Layout:** nav rail + **meetings list** (288px, search field + date-grouped rows, selected row =
  lilac-soft bg + lilac dot) + **detail** pane.
- **Detail header:** Bricolage title 25px, meta line (date · time · duration · source), attendee
  chips (squircle mini-avatar + name, `+N` overflow), coral conference link with video glyph, tag
  chips, action buttons (Re-transcribe secondary + export icon).
- **Tabs:** pill tabs Transcript / **Summary** (active) / Notes / Chat.
- **Summary body:** two columns — left = "AI SUMMARY" prose + "DECISIONS" list (mint check glyph);
  right = "Action items" card (checkboxes, due badge, owner name; completed = struck + filled coral
  checkbox) + **audio player** card (round coral play button, coral progress bar, time labels).

### 3. Tasks · Board — `bloom-tasks.html`
- **Purpose:** kanban task board.
- **Layout:** nav rail + **projects sub-nav** (208px: All tasks/Today/Overdue + PROJECTS + INITIATIVES,
  active = lilac-soft) + main. Main top chrome = "Tasks" title + view switcher pills (List/**Board**/
  Table/Calendar) + filter field + "New task" primary. Body = 3 **columns** (Open/In progress/
  Completed), each a rounded lane (`rgba(...,.035)` fill, radius 14) with a header (status dot + label
  + count + add) and task cards.
- **Task card:** radius 11, **left priority accent bar** (3px, danger/warn, hidden for low), optional
  project/label chip, title 13px/600, footer row = priority badge + due badge + owner squircle avatar.
  Completed cards: 0.62 opacity, struck title, mint "Done" badge.

### 4. People — `bloom-people.html`
- **Purpose:** relationship CRM.
- **Layout:** nav rail + **people list** (308px: title + Add primary, search field, filter pills
  All/Colleagues/Clients/Skio, person rows = squircle avatar + name + role/company + relative-time)
  + **detail** pane.
- **Detail:** big 64px squircle avatar (radius 18) + name (Bricolage 25px) + role + relationship/tag
  chips + Email/Log-encounter buttons; a **"Stay connected" nudge** card (gold-bordered, cadence
  copy + Reconnect primary); then a 2-col grid: left = DETAILS property rows + SHARED MEETINGS cards;
  right = MEMORIES (editable note fields) + MESSAGE INSIGHTS card (3 big stat numbers + a small
  coral bar chart).

### 5. Design language — `bloom-language.html`
- Reference sheet, not an app screen. Palette swatches, type scale, button/pill/tab/chip/badge/card/
  avatar specimens, tinted-header card. Use it to verify token + component fidelity.

---

## Interactions & Behavior
Functionality is unchanged — preserve all existing handlers, routing (`WorkspaceRouter`), recording,
transcription, MCP, etc. Visual/motion changes only:

- **Motion personality:** bouncy springs. Keep `NDS.springStandard` but slightly livelier
  (`response ~0.32, dampingFraction ~0.8`). Buttons scale-on-press (~0.97). Tab/section changes
  cross-fade with the spring. **All animations must remain gated behind `NDS.motion(_:reduce:)`**
  for Reduce Motion (existing pattern) — and entrance/celebration effects must no-op under it.
- **Task complete:** a small celebratory flourish (e.g. a brief confetti/burst or a satisfying
  checkbox fill + scale) on marking a task done — optional, reduce-motion-aware, tasteful.
- **Hover:** cards lighten border (`--line` → `--line-2`); nav/rows get lilac-soft bg.
- **Active recording:** existing red "stop" treatment; keep the pulsing record indicator
  (`pulsingSymbol`, already reduce-motion gated).

## State Management
No new state. Reuse existing stores/view models (`MeetingManager`, `ActionItemStore`, `PeopleStore`,
`WorkspaceRouter`, etc.). The overhaul is presentation-layer only.

## Assets
- **Icons:** keep SF Symbols (existing `systemImage` names). The HTML's inline SVGs are placeholders
  indicating glyph + position only.
- **Fonts:** add **Bricolage Grotesque** (display) and **Plus Jakarta Sans** (body) — Google Fonts /
  OFL, free to bundle. Register in the app bundle + `Info.plist`. No other new assets.
- **No raster images** are used in the design.

## Screenshots
Reference renders of the Bloom direction (dark mode) are in `screenshots/`:
- `01-today.png` — Today / home dashboard
- `02-meeting.png` — Meeting detail (Summary tab)
- `03-tasks.png` — Tasks board (kanban)
- `04-people.png` — People (list + person detail)
- `05-design-language.png` — design-language reference sheet

## Implementing with Claude Code
A ready-to-paste prompt for the Claude Code CLI is in **`CLAUDE_CLI_PROMPT.md`** — it tells Claude
Code to implement Bloom from this bundle on a branch, build/test/lint, merge to `main`, and reinstall
locally via `make install`.

## Files
In `designs/`:
- `bloom.css` — **single source of truth** for every token + component style.
- `bloom-today.html`, `bloom-meeting.html`, `bloom-tasks.html`, `bloom-people.html` — screen comps.
- `bloom-language.html` — design-language reference sheet.

In the app, the highest-leverage files to edit (centralized — most screens inherit):
- `Sources/MeetingScribe/UI/NotionDesign.swift` — retune `NDS` tokens, button styles, chips, fonts.
- `Sources/MeetingScribe/UI/MSComponents.swift`, `MSAvatar.swift`, `MSStatusBadge.swift`,
  `DueChip.swift` — component restyle.
- `MainWindow.swift` (nav rail), `TodayView.swift`, `MeetingDetailHeader.swift` + tab views,
  `ActionItemsBoardView.swift`, `PeopleListView.swift`/`PersonDetailView.swift` — per-surface polish.
- Run `scripts/design-lint.sh` after — keep drift at 0 (no raw `.font(.system(size:))`, no cold
  AppKit surfaces, no raw priority/status colors).
