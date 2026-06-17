# UX Group Compilation — MeetingScribe v2 Audit

> **Compilation status:** UX5 (AI Chat & Second Brain UX) filed. UX1–UX4 findings files were not present at compilation time — this document will need a second pass once those agents complete their work. All UX5 findings are included in full below and flagged with their source. Cross-agent convergence analysis is marked "pending" where UX1–UX4 data is absent.

---

## Convergence within this group (items 2+ agents raised independently)

*Full cross-agent convergence analysis pending UX1–UX4 findings.*

The following themes from UX5 are highly likely to converge with other UX agents based on the shared briefing and codebase topology:

- **Proactive AI surfaces missing across all tabs** (UX5-1, likely UX4-Today) — Today dashboard and chat rail both lack "push" intelligence; agents covering both will almost certainly flag the same gap.
- **"Ask AI about this" entry points absent from entity cards** (UX5-5, likely UX2-People, UX3-Meetings) — the absence of contextual AI entry points on People and Meeting cards will be raised by all entity-focused agents.
- **Discoverability / empty-state gaps** (UX5-2, likely UX1-Nav) — the hidden-by-default chat rail and lack of capability signaling touches navigation architecture (UX1's domain) and all content tabs.
- **Session fragmentation (meeting chat vs. global chat)** (UX5-4, likely UX3-Meetings) — UX3 will observe that the meeting-detail chat tab and the global sidebar are disconnected; UX5 identified the same root cause at the ChatSession layer.
- **Inline AI insight cards on entity views** (UX5-3, likely UX2-People, UX3-Meetings) — absence of pinned, proactive AI context on PersonDetailView and UnifiedMeetingDetail is visible from both the People and Meetings agent perspectives.

---

## All net-new recommendations (deduplicated, with source agent IDs)

| ID | Title | Effort | Impact | Source |
|----|-------|--------|--------|--------|
| UX5-1 | Proactive AI Nudge Engine — "Ambient Second Brain" | L | High | UX5 |
| UX5-2 | Capability Discovery Panel ("What can I ask?") | S | High | UX5 |
| UX5-3 | Inline AI Insight Cards on Entity Detail Views | M | High | UX5 |
| UX5-4 | Unified Chat Session with Entity Deep-Link Navigation | M | High | UX5 |
| UX5-5 | "Ask about this" Contextual Entry Points on Every Entity | S | Med | UX5 |
| UX5-6 | Tool-Use Narration and Write-Back Confirmation Cards | M | Med | UX5 |
| UX5-7 | Chat History Export and Session Memory Digest | S | Med | UX5 |
| UX5-8 | Semantic Search Transparency — "Why this answer?" | S | Med | UX5 |

*Items from UX1–UX4 will be merged here when those agents file.*

---

## Group's top 10 picks with rationale

*(Based on UX5 findings; to be re-ranked after UX1–UX4 merge)*

1. **UX5-1 — Proactive AI Nudge Engine:** The single largest gap between current behavior and Tyler's "second brain" vision. Every other UX improvement makes the existing reactive chat better; this one changes the paradigm from reactive to proactive. Nudges on Today + badge on chat toggle reach users who never open the chat rail.

2. **UX5-3 — Inline AI Insight Cards on Entity Views:** Brings AI intelligence into the user's existing workflow (browsing people and meetings) without requiring them to switch to a chat paradigm. Eliminates the activation-energy barrier. Especially high-value on PersonDetailView where the relationship health signal is already computed but buried.

3. **UX5-2 — Capability Discovery Panel:** The tool suite (iMessage analysis, Linear, Notion, relationship graph, semantic recall) is already implemented. The ROI on surfacing it is enormous relative to the tiny build cost. This unblocks value from every other AI feature.

4. **UX5-4 — Unified Chat Session with Entity Deep-Link Navigation:** Session fragmentation between meeting-detail chat and global chat creates a "two brains" problem. Unifying them with a `focusContext` pattern and making `meetingscribe://` links tappable is an architectural fix with high long-term leverage.

5. **UX5-5 — "Ask about this" Contextual Entry Points:** One-click path from any entity card to an AI query. The `WorkspaceRouter.openChat(query:)` hook already exists — this is a pure UX wiring exercise with near-zero backend cost.

6. **UX5-8 — Semantic Search Transparency:** The hybrid retrieval/grounding infrastructure (C2-2) is already built. Adding a "Sources" disclosure group to AI responses requires only a UI change to ChatBubble. High trust-building value for low effort.

7. **UX5-6 — Tool-Use Narration and Write-Back Confirmation Cards:** Raw JSON tool-call bubbles are a developer artifact. Replacing them with human-readable narration and inline confirmation cards for write operations makes the AI feel like a product instead of a prototype.

8. **UX5-7 — Chat History Export and Session Memory Digest:** Preventing silent context loss via pre-trim summarization is low-effort and closes a second-brain integrity gap. Export to markdown is a power-user feature that makes the chat history part of the user's external memory system.

9. *(Reserved for UX1 navigation finding)*

10. *(Reserved for UX2/UX3/UX4 finding)*

---

## Highest-priority single recommendation from this group

**UX5-1: Proactive AI Nudge Engine**

The core promise of MeetingScribe v2 is a *second brain* — something that makes Tyler smarter about his commitments, relationships, and upcoming work without requiring him to remember to ask. Every feature currently in the app requires Tyler to initiate: open the chat rail, type a question, navigate to a view. A proactive nudge engine is the one architectural change that makes the app feel qualitatively different from a v1 feature set. It runs entirely on local Ollama (free, private, always-on), surfaces through existing UI primitives (Today widget, chat rail badge), and creates the "app told me something I forgot" moments that define a second-brain experience. All other UX improvements are polish; this one is the vision.
