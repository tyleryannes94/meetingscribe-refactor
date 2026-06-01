# G5 Competitive — macOS-Native Feel (Things 3 / Linear / Craft / Apple HIG)

**Lens:** Does MeetingScribe feel like a *premium native Mac app* — or a SwiftUI shell wrapping a web-app mental model? I judge it against the Apple HIG, macOS 26 "Tahoe" Liquid Glass, and the apps Mac users hold up as the bar (Things 3, Craft, Bear, Fantastical, Apple's own System Settings/Notes). Every recommendation is tied to the cold-start / runtime / crash constraint.

## Audit (through my lens)

The app is well-styled but built on **hand-rolled chrome rather than native macOS structure** — the single biggest "web-app-ish" tell. Concrete evidence:

- **Navigation is a custom `HStack` rail, not `NavigationSplitView`.** `MainWindow.body` builds `HStack { navRail; Divider; tabContent; ChatSidebar }` (`UI/MainWindow.swift:243-267`), and `navRail` is a fixed `.frame(width: 240)` `VStack` (`MainWindow.swift:110-168`). This means: no native sidebar translucency/Liquid Glass, no system "collapse sidebar" toolbar control, no `⌥⌘S` toggle, no automatic full-height-under-titlebar treatment, no system-managed minimum widths. Real Mac apps (Things, Mail, System Settings) get all of that free from `NavigationSplitView`. The code even fights the titlebar manually with magic insets — `splitPaneTopInset = 60` (`NotionDesign.swift:18-20`), `.padding(.top, 48)` (`Graph/GraphDetailPanel.swift:65`), and a comment about content "slid under the toolbar and were cut off" (`UnifiedMeetingDetail.swift:79-81`). That's the symptom of *not* using the split-view container that handles the safe area for you.

- **Tab switching is opacity layering, not navigation.** `tabContent` keeps every visited tab alive in a `ZStack` and cross-fades opacity (`MainWindow.swift:90-106`). Clever for warmth, but it's a web "router swaps a div" pattern, not a Mac "select a sidebar row → detail column updates" pattern. It also means every visited tab's view tree stays resident and re-renders on `section` changes — a memory/CPU cost that grows with session length.

- **Two parallel toolbars, neither fully native.** Search + appearance + ⌘K live *inside* the custom rail's bottom row (`MainWindow.swift:139-163`), while a real `.toolbar { }` exists separately with Assistant/Search/Persistent buttons (`MainWindow.swift:284-302`). Duplicated search entry points, and the appearance toggle is a custom segmented control in the sidebar (`AppearanceToggle`, `NotionDesign.swift:491-525`) where Mac users expect it under the system Appearance setting or nowhere (apps usually just follow the system).

- **Window doesn't restore frame.** `WindowGroup` sets `.frame(minWidth: 720, minHeight: 560)` and `.windowResizability(.contentMinSize)` (`MeetingScribeApp.swift:49,75`) but there's no `.defaultSize`, no scene-based size/position restoration, and `restorationBehavior` isn't set. A native Mac app reopens exactly where you left it; this one re-centers at min size each launch — a subtle but constant "this isn't quite native" signal.

- **Color/type system is bespoke, not semantic.** `NDS` hardcodes sRGB tuples for bg/sidebar/divider (`NotionDesign.swift:44-55`) instead of `NSColor.windowBackgroundColor`, `.separatorColor`, `.selectedContentBackgroundColor`, or materials. It's a "Notion palette" (the name says it) — so it tracks a *web* product's look, not the Mac's. No `.regularMaterial`/glass anywhere, so on macOS 26 Tahoe it reads as a flat web surface next to System Settings, Reeder, Tot which adopted Liquid Glass.

- **Keyboard model is thin for a power app.** ⌘K search + ⌘1–5 navigate (`MeetingScribeApp.swift:86-98`) is good, but there's no "hold ⌘ to reveal shortcuts" affordance (Things), no type-to-jump in lists (Things' Type Travel), and selection/focus isn't a shared cross-tab concept — so keyboard-only flow across tabs is limited.

**Net:** visually polished, structurally web-shaped. The fastest path to "premium Mac app" is adopting the native containers — which *also* helps perf, because the system manages safe-area layout, sidebar collapse, and column sizing more cheaply than the hand-rolled GeometryReader + opacity stack.

## NET-NEW recommendations

### CM-1 — Adopt `NavigationSplitView` for the shell (sidebar + detail), keep tab warmth via `@SceneStorage` selection
**What/why:** Replace the custom `HStack(navRail / tabContent)` with a two/three-column `NavigationSplitView`: sidebar = the 5 sections + Settings, content = the tab, optional third column = the Assistant. The system then provides translucent sidebar material, the standard collapse control, `⌥⌘S`, automatic under-titlebar safe area (deletes the `splitPaneTopInset=60`/`padding(.top,48)` hacks), and system min-width management. Preserve the "instant tab" feel by keeping the lightweight stores warm (already done) and binding the selected section to `@SceneStorage` so it restores per-window.
**UX impact:** Instantly reads as native; sidebar collapses for focus mode (new capability, 0→1 click via toolbar/keyboard). Removes duplicated chrome. No regression in click counts to reach any tab (still 1 click / ⌘1–5).
**Perf/stability:** *Improves* load — drop the all-tabs `ZStack` opacity keep-alive (`MainWindow.swift:90-106`) that keeps every visited view tree resident and re-rendering; `NavigationSplitView` lazily builds the detail and the system caches column layout. Lower steady-state memory in long sessions. Keep the warm `MeetingStore`/`MeetingBodyCache` so first paint of a newly selected column is still skeleton-free. Risk: it's a structural refactor — gate behind a feature flag and migrate one column at a time.
**Effort:** L · **Impact:** High · **Deps:** none (foundational)

### CM-2 — Restore window frame + set `.defaultSize`/`.restorationBehavior`
**What/why:** Add `.defaultSize(width:1180,height:760)` to the `WindowGroup`, let the scene restore size/position across launches (WWDC24 "Tailor macOS windows"), and persist sidebar/assistant collapse in `@SceneStorage`. Mac users expect a window to reopen exactly where they left it.
**UX impact:** App reopens at the user's chosen size/place instead of re-centering at 720×560 each launch — a constant native-feel cue, 0 clicks.
**Perf/stability:** Negligible cost; state restoration is a tiny plist write. Pin a sane `.defaultSize` so first launch isn't a cramped min-size window (which currently makes the chat rail auto-hide at <860pt, `MainWindow.swift:248`).
**Effort:** S · **Impact:** Med · **Deps:** plays into CM-1.

### CM-3 — Move to semantic system colors + materials (Liquid Glass-ready), keep NDS as a thin alias layer
**What/why:** Repoint `NDS.bg/sidebarBg/divider/rowSelected` (`NotionDesign.swift:44-55`) at `NSColor.windowBackgroundColor`, `.underPageBackgroundColor`, `.separatorColor`, `.selectedContentBackgroundColor`, and give the sidebar/toolbar `.regularMaterial`/glass on macOS 26. Keep the `NDS` names so call sites don't churn. This is what Reeder/Tot/Screens did to "do Liquid Glass right."
**UX impact:** Matches System Settings/Notes side-by-side; selection highlight, dividers, and vibrancy track the OS (including accent-color and increased-contrast settings) instead of a fixed purple-on-warm-gray.
**Perf/stability:** Materials are GPU-composited and cheap; semantic colors avoid per-appearance `NSColor` closures the current `dyn()` allocates (`NotionDesign.swift:60-67`). Net neutral-to-positive. Guard glass behind `if #available(macOS 26)` to keep older OS flat.
**Effort:** M · **Impact:** High · **Deps:** CM-1 (so the sidebar that gets the material is the native one).

### CM-4 — Consolidate to one native `.toolbar`, with a trailing native search field
**What/why:** Remove the search/appearance buttons baked into the custom rail (`MainWindow.swift:139-163`); put them in the single `.toolbar` using semantic placements (`.navigation`, `.primaryAction`), and make Search a real toolbar `.searchable`/search field at the trailing edge per HIG. Drop the in-sidebar appearance toggle and just follow the system (offer the override in Settings only).
**UX impact:** One obvious search entry (today there are two: rail ⌘K pill *and* toolbar magnifier). Toolbar becomes user-customizable (right-click → Customize Toolbar) — a hallmark native affordance, currently absent.
**Perf/stability:** Removes a chunk of custom view code from the always-rendered rail. No runtime cost.
**Effort:** M · **Impact:** Med · **Deps:** CM-1.

### CM-5 — "Hold ⌘ to reveal shortcuts" + type-to-jump in lists (Things parity)
**What/why:** Add a transient overlay that surfaces the current view's key shortcuts while ⌘ is held (Things' signature affordance), and type-ahead selection in Meetings/People/Tasks lists so typing a name jumps to it (Things' "Type Travel"). Both are pure-native power-user cues.
**UX impact:** Teaches the keyboard model in-context (discoverability with 0 menu digging); list navigation drops from "scroll + click" to "type 3 chars + Return."
**Perf/stability:** Overlay is a momentary view, lists already exist — cheap. Type-ahead is O(visible rows) string match; cap to the already-loaded/cached slice so it never forces a full fetch.
**Effort:** M · **Impact:** Med · **Deps:** none (complements existing ⌘K).

### CM-6 — Native sidebar selection list with system disclosure groups & badges
**What/why:** Once on `NavigationSplitView` (CM-1), render the sidebar as a `List(selection:)` with `Section`s ("Workspace"/"Organize", already conceptually present at `MainWindow.swift:122-134`) and native `.badge()` counts (e.g. open Tasks, today's meetings). This is the System Settings / Mail sidebar pattern.
**UX impact:** Counts visible at a glance in the sidebar (e.g. overdue tasks) — surfaces state that today requires opening a tab (1+ click → 0). Native selection styling, keyboard arrow navigation, and VoiceOver rotor for free.
**Perf/stability:** Badges must be cache-backed — read counts from the existing in-memory stores / a persisted lightweight counts cache, never a live query on every render, or the sidebar becomes a scroll-jank source. Recompute on store change, not on paint.
**Effort:** M · **Impact:** Med · **Deps:** CM-1.

### CM-7 — Replace bespoke buttons/shadows with native control idioms where they're load-bearing
**What/why:** The custom `MSPrimary/Secondary/Danger` styles with drop shadows (`NotionDesign.swift:253-328`, `.shadow(color: brand.opacity(0.25)…)`) read as web-CTA buttons. Keep them for marketing-y empty states, but use `.buttonStyle(.borderedProminent)`/`.bordered` with `.controlSize` for in-chrome actions so they inherit native focus rings, accent color, and pressed states.
**UX impact:** Buttons feel like Mac buttons (focus ring for keyboard users, accent-color tracking) rather than purple web pills with soft shadows.
**Perf/stability:** Native button styles are cheaper than custom backgrounds+shadows+overlays composited per button. Minor positive.
**Effort:** S–M · **Impact:** Low–Med · **Deps:** none.

## Top 3 picks

1. **CM-1 — Adopt `NavigationSplitView` shell.** Highest conviction and the single highest-value change: it's the difference between "SwiftUI web shell" and "Mac app," and it *removes* the opacity keep-alive stack and titlebar-inset hacks, so it pays for itself in perf and memory. **Phase 1** (foundational/perf + infra — everything else builds on it).
2. **CM-3 — Semantic colors + Liquid Glass materials.** Biggest visual leap toward premium-native on macOS 26, cheap at runtime, low regression risk once CM-1 lands. **Phase 2.**
3. **CM-5 — Hold-⌘ shortcuts + type-to-jump.** The power-user polish that makes Things/Linear feel fast and "yours"; independent of the refactor so it can ship early for quick wins. **Phase 3.**

(CM-2 window restoration → Phase 1 alongside CM-1; CM-4 toolbar → Phase 2; CM-6 badges → Phase 3; CM-7 buttons → Phase 4 polish.)

## Sources
- Apple HIG — Sidebars: https://developer.apple.com/design/human-interface-guidelines/sidebars
- Apple HIG — Split views: https://developer.apple.com/design/human-interface-guidelines/split-views
- Apple HIG — Toolbars: https://developer.apple.com/design/human-interface-guidelines/toolbars
- Apple HIG — Layout: https://developer.apple.com/design/human-interface-guidelines/layout
- Apple HIG (root): https://developer.apple.com/design/human-interface-guidelines
- Customizing window styles & state-restoration in macOS (SwiftUI): https://developer.apple.com/documentation/SwiftUI/Customizing-window-styles-and-state-restoration-behavior-in-macOS
- WWDC24 — Tailor macOS windows with SwiftUI: https://developer.apple.com/videos/play/wwdc2024/10148/
- macOS Tahoe apps doing Liquid Glass right (Reeder/Tot/Screens/System Settings): https://openmarkapp.com/blog/macos-tahoe-apps-liquid-glass
- Liquid Glass official best practices (iOS 26 / macOS Tahoe): https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo
- Things 3 keyboard shortcuts / Type Travel: https://culturedcode.com/things/support/articles/2785159/
