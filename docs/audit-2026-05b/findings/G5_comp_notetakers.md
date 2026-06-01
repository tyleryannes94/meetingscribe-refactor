# G5 Competitive Experts — AI Meeting Notetaker Design/UX

**Lens:** Steal the click-efficient layout/navigation patterns the market converged on (Granola, Fathom, Otter, Fireflies, tl;dv, Zoom AI Companion), and design MeetingScribe's local-first version to beat them — every pattern bent to the cold-start / first-open / runtime-smoothness constraint.

## Audit (through my lens)

MeetingScribe's current shape vs. the field:

- **Meetings tab is a 2-column `NavigationSplitView`** — list (300–480px) + full-page `UnifiedMeetingDetail` (`MeetingsView.swift:53–78`). Detail is a 3-tab stack: Transcript / My Notes / Summary (`UnifiedMeetingDetail.swift:26`, `:88–90`). This matches Fireflies' Notebook (left nav → center thread → right transcript) and Granola's two-pane note canvas, but our tabs **hide** transcript+notes+summary behind a picker, where Granola/Fireflies show notes and transcript **side-by-side**.
- **Today is a single scrolling feed** (`TodayView.swift:44–60`): header → quick actions → up-next → live → NeedsAttention → today's calls. Good, but it is the only "list" surface that mixes work + meetings; competitors keep a persistent **left rail of recent meetings always one click away** (Granola/Fireflies/tl;dv).
- **Keep-alive tabs with opacity cross-fade** (`MainWindow.swift:90–106`) already give near-instant tab switches after first visit — a real perf advantage to protect.
- **Selection is router-owned** (`WorkspaceRouter`, `MeetingsView.swift:24–27`) so a meeting opens one canonical way — good foundation; competitors' web apps reload routes.
- **Summary tab is the default** (`UnifiedMeetingDetail.swift:26`) — correct, matches the market: everyone leads with the summary, not the transcript.

What the field does better today (with sources):

- **Granola: merged "enhanced notes"** — your typed notes (black) fused with AI summary (gray) into one canvas, no tab switching; chat opens as a right sidebar via `Cmd+J` over a single meeting, a folder, or all meetings ([help.granola.ai](https://help.granola.ai/article/ai-enhanced-notes), [granola.ai/blog](https://www.granola.ai/blog/get-the-best-from-granola)). Zero-learning-curve "just a notepad" ([meetjamie.ai](https://www.meetjamie.ai/blog/granola-review)).
- **Fathom / Zoom / Otter: "Ask" as a ChatGPT-style cross-meeting search with cited answers** — "What did the customer say about pricing last quarter?" ([fathom.ai](https://www.fathom.ai/), [zoom.com AI Companion](https://www.zoom.com/en/products/ai-assistant/)). Zoom adds **preset prompts** ("Catch me up", "Action items?") ([support.zoom.com](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0058013)).
- **Fireflies: structured "thread" view** — overview / notes / action items / outline in the center, transcript with per-speaker talk-time on the right; **Smart Search** filters by keyword/speaker/sentiment/topic; clickable **Outline** jumps you through the meeting ([guide.fireflies.ai](https://guide.fireflies.ai/articles/6653885315-learn-about-the-fireflies-notepad), [lindy.ai](https://www.lindy.ai/blog/fireflies-ai-review)).
- **tl;dv: timestamped highlights + one-click clip** — type a note during the call and it becomes a jumpable timestamp; one click tags a decision/objection ([tldv.io](https://tldv.io/blog/tldv-honest-review/), [meetjamie.ai](https://www.meetjamie.ai/blog/tldv-review)).
- **Otter: consolidated "My Action Items" across all meetings** + a Takeaways panel ([otter.ai blog](https://otter.ai/blog/otter-ai-new-feature-my-action-items)).
- **Speed bar set industry-wide:** summary ready in **<30s** after stop (Fathom, Motion); one-click share (Jamie); "walk out with the summary before you close your laptop" (Tactiq) ([usemotion.com](https://www.usemotion.com/features/ai-meeting-notetaker), [tactiq.io](https://tactiq.io/)).

## NET-NEW recommendations

### CN-1 — Granola-style "Enhanced Notes" merged canvas (collapse the 3 tabs into 1 default view)
**What/why:** Replace the Transcript/Notes/Summary *picker* as the landing surface with a single merged canvas: AI summary + your typed notes in one document (Granola's black/gray fusion), transcript demoted to a secondary toggle. The market's strongest signal is that notetaking should feel like "just a notepad," not a tabbed inspector ([help.granola.ai](https://help.granola.ai/article/ai-enhanced-notes)).
**UX impact:** Reading summary + your notes today = land on Summary, then 1 click to Notes (can't see both). After: both visible, 0 clicks. Transcript stays 1 click.
**Perf/stability:** Cheaper, not more — render only the merged markdown (already cached via `MeetingBodyCache`); lazy-load the transcript pane only when toggled, so the heavy full-transcript string never inflates first paint. Keep the existing `bodyLoadTask` cancellation so switching meetings stays smooth.
**Effort:** M · **Impact:** High · **Deps:** UnifiedMeetingDetail tab refactor; respects WorkspaceRouter.

### CN-2 — Clickable meeting Outline / jump-to-moment rail (Fireflies + tl;dv)
**What/why:** Generate a section/topic outline from the summary headings and timestamps; clicking a row scrolls the transcript/audio to that moment. Fireflies' Outline and tl;dv's typed-note-→-timestamp are the fastest in-meeting recall pattern in the field.
**UX impact:** Finding "the pricing part" of a 60-min call today = scroll/scan transcript (many scrolls). After: 1 click from outline.
**Perf/stability:** Outline is derived once at finalize and **persisted** alongside the summary (precomputed cache) — no runtime parse, no transcript load until a row is clicked. Tiny JSON, negligible memory.
**Effort:** M · **Impact:** High · **Deps:** Summary section parser; audio player seek (`AudioPlayerView` exists).

### CN-3 — Persistent "Recents" rail + always-on global search (Granola/Fireflies left nav)
**What/why:** Every competitor keeps recent meetings one click away in a left rail and a global search bar always visible. We have per-tab search (`MeetingsView.swift:101`) but no global recents strip outside the Meetings tab.
**UX impact:** Jumping to last meeting from People/Tasks/Today today = switch to Meetings tab → find row (2–3 clicks). After: 1 click from a recents strip anywhere.
**Perf/stability:** Back it with the existing FTS5 index + a small in-memory "last N meetings" cache (id/title/date only — no bodies) so it renders instantly on cold start as a skeleton, hydrating lazily. Pure metadata = trivial memory.
**Effort:** M · **Impact:** Med · **Deps:** WorkspaceRouter; FTS5 wire-up (see V4 C2-1).

### CN-4 — Preset "ask this meeting" chips (Zoom AI Companion's Catch-me-up pattern)
**What/why:** Above the per-meeting chat, show 3–4 one-tap prompt chips: "Catch me up", "Action items?", "Decisions made", "Was I mentioned?" — Zoom's most-used AI affordance ([support.zoom.com](https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0058013)).
**UX impact:** Getting a recap today = open chat, type a question (type + send). After: 1 tap.
**Perf/stability:** Chips run the *same* local Ollama path already wired in `MeetingChatTab`; cache the "Catch me up" answer at finalize so the most common chip returns instantly with zero inference on open. Stream tokens (V4 C5-4) so no spinner.
**Effort:** S · **Impact:** High · **Deps:** existing meeting chat; ResourceGovernor gating on battery.

### CN-5 — One-click highlight/clip → timestamped, shareable (tl;dv)
**What/why:** Let the user select a transcript span (or hit a hotkey live) to mark a highlight with timestamp; collect into a per-meeting "Highlights" strip. tl;dv's single-click decision/objection tag is its signature retention hook ([tldv.io](https://tldv.io/blog/tldv-honest-review/)).
**UX impact:** Capturing "the one quote" today = copy text manually, paste into notes (multi-step). After: 1 click, auto-timestamped.
**Perf/stability:** Highlights stored as light offset+text records in the meeting JSON — no media re-encode (we're local audio, not video, so even cheaper than tl;dv). Renders from cache, no runtime cost.
**Effort:** M · **Impact:** Med · **Deps:** transcript selection; CN-2 seek.

### CN-6 — Sub-30s "summary-ready" path with optimistic skeleton (industry speed bar)
**What/why:** The whole market advertises summary <30s and "walk out with it." Make the perceived path instant: on stop, immediately show the merged-notes canvas with a **streaming** summary skeleton instead of a blank/spinner ([usemotion.com](https://www.usemotion.com/features/ai-meeting-notetaker), [tactiq.io](https://tactiq.io/)).
**UX impact:** After stop today the user waits on a spinner with nothing to read. After: the canvas is there instantly (their typed notes + live-streaming summary), 0 perceived wait.
**Perf/stability:** This *is* a perf feature — render typed notes (already in memory) first, stream summary tokens (V4 C5-4), warm-pool whisper (V4 C5-1) so finalize doesn't cold-load the model ~36×. Pure win for first-open feel.
**Effort:** M · **Impact:** High · **Deps:** streaming summarization; warm-pool.

### CN-7 — "Ask across all meetings" with cited, deep-linked answers (Fathom/Zoom moat parity, done local)
**What/why:** Fathom/Zoom's cross-meeting Q&A is table stakes; ours can be the only 100%-on-device cited version. Each answer cites the meeting + jumps there via `meetingscribe://`.
**UX impact:** "What did we decide about X last quarter?" today = manual search + open + scan across several meetings (5+ clicks). After: 1 query, cited answers, 1 click to source.
**Perf/stability:** Build on FTS5 + on-device embeddings (V4 C2-1/C5-10) as a **persisted** vector cache; retrieve top-k then summarize so the LLM never ingests the whole corpus (bounded memory). Skeleton the answer; stream tokens.
**Effort:** L · **Impact:** High · **Deps:** FTS5 wire-up, embeddings, deep links (overlaps V4 Phase 2 — frame here as the *navigation/UX* layer).

### CN-8 — Density/comfort toggle + scannable list rows (against Fathom's "cluttered" critique)
**What/why:** Reviews ding Fathom for distracting pop-ups and Otter/Fireflies for clutter; Granola wins on calm minimalism. Add a Comfortable/Compact density toggle and tighten list rows to title + one-line meta + tag, matching Granola's restraint ([meetjamie.ai/granola](https://www.meetjamie.ai/blog/granola-review)).
**UX impact:** Power users scan more meetings per screen (compact); new users get breathing room (comfortable) — no extra clicks, better scan speed.
**Perf/stability:** Pure layout constants, no data cost. Fewer shadow/scale effects in compact mode (`MeetingCard.swift:51–55`) = cheaper scroll on long lists.
**Effort:** S · **Impact:** Med · **Deps:** MSCard/MSListRow extraction (V4 D2-1).

### CN-9 — Local-first advantage made visible: "instant, offline, no bot" trust strip
**What/why:** Every cloud competitor is dinged for a "visible bot in the meeting" and cloud-trust anxiety (Fathom critique; Recall backlash). Granola already markets "no bot." MeetingScribe is bot-less *and* offline — surface it: a tiny status chip ("On device · Offline · No bot") on the meeting header and empty states.
**UX impact:** Reinforces the differentiator at the exact moment of doubt; no click cost.
**Perf/stability:** Static UI; zero runtime cost. Reinforces the egress-allowlist invariant (V4 E4-3) as a *visible* promise.
**Effort:** S · **Impact:** Med · **Deps:** none.

## Top 3 picks

1. **CN-1 — Enhanced Notes merged canvas** → **Phase 2.** The single highest-conviction layout change: kills the tab-juggling, matches Granola's proven calm UX, and is *cheaper* to render than the current 3-tab load.
2. **CN-6 — Sub-30s optimistic streaming summary** → **Phase 1.** Foundational perf+UX: hits the industry speed bar and makes first-open-after-stop feel instant; depends on warm-pool/streaming that Phase 1 should land anyway.
3. **CN-4 — Preset "ask this meeting" chips** → **Phase 3.** Cheapest high-leverage recall affordance; turns the existing local chat into a one-tap recap, with the common answer pre-cached at finalize.

Single highest-value: **CN-1** — collapsing Transcript/Notes/Summary into one Granola-style canvas is the layout decision that most reduces clicks *and* reduces load (render cached merged markdown; lazy-load transcript only on toggle).
