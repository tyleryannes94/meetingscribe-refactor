# UX Audit — Meeting Detail View

*Agent: meeting-view designer. Scope: `UnifiedMeetingDetail.swift`, `MeetingSummaryTab.swift`, `MeetingTranscriptTab.swift`, `MeetingChatTab.swift`, `MeetingDetailHeader.swift`, `PreMeetingBriefView.swift`, `MeetingPeopleRail.swift`.*

Current tabs: **Notes** (editable markdown + collapsible AI summary) · **Actions** · **Transcript** (or pre-brief for upcoming) · **Ask AI**.

## P0
- **Over-fragmented tabs.** Notes + Summary + Transcript are one logical "content canvas" split across tabs; you tab-switch to read the recap and the transcript together. → Merge Notes + Transcript into one scrolling **Meeting** tab (outcomes → highlights → summary → notes → transcript → related), keep Actions + Ask AI. `UnifiedMeetingDetail.swift:152-157,248-267`.
- **Summary crushed into a 320pt box.** `MeetingSummaryTab.swift:170 .frame(maxHeight: 320)` makes long recaps illegible (~5 lines visible). → Remove the cap; let the canvas scroll.
- **Dense header.** `MeetingDetailHeader.swift:8-111` stacks source picker + tags + upcoming actions + status banner with tight padding. → `.padding(.vertical, 20)`; move source picker into Options menu; collapse attendees >8.

## P1
- **Post-meeting summary not reliably auto-generated.** Only runs via `transcribeNow(regenerateSummary:true)`; if Ollama is down it fails silently and the user sees "No summary yet" (`MeetingSummaryTab.swift:304,315-319`). → Track a `summaryGenerating` state, auto-retry (backoff, max 3), show "Generating summary…".
- **Pre-meeting brief auto-generates but has no retry.** `PreMeetingBriefView.swift:45,340-355` — add a "Regenerate brief…" button; pre-warm ~24h before start (currently cached only after first generation, line 412).
- **Nested ScrollView** around the summary editor (`MeetingSummaryTab.swift:164-171`) → choppy scroll; remove the inner ScrollView.

## P2
- Show the outcomes strip in **all** modes (live/upcoming/past), not just past (`MeetingSummaryTab.swift:12-26`).
- "People rail hidden" has no indicator once toggled off (`UnifiedMeetingDetail.swift:74-75,218-224`).
- Related-meetings strip is buried at the bottom of Notes (`MeetingSummaryTab.swift:28-57`) → move up as a compact carousel.
- No in-view "Search transcript" affordance (`UnifiedMeetingDetail.swift:76-77`).
- "Actions N" badge "unconfirmed" is unclear; show total + pending, add tooltip.
- Attendee inline limit (12) forces horizontal scroll; series spine font is 11pt (too small).

**Generation state today:** pre-meeting brief ✅ auto-generates (no manual retry); post-meeting summary ⚠️ *should* but isn't guaranteed (silent fail) — the P0-3 fix makes it reliable.
