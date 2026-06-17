# UX Audit — AI Chat Consistency

*Agent: AI-chat PM. Scope: `ChatPanel.swift`, `ChatSidebar.swift`, `MeetingChatTab.swift`, `PersonDetailView.swift` (personChatColumn), `ChatSession.swift`.*

## Three surfaces today (the fragmentation)
| | Today sidebar | Meeting detail | Person detail |
|---|---|---|---|
| Session | app-wide `chatSession` | **per-meeting `meetingChat` (ephemeral)** | app-wide `chatSession` |
| Context | page label (`MainWindow.contextLabel`) | inline `contextPrefix` per message | `setContext()` person-scoped |
| Capability UI | categorized (4 groups) | flat `examplePrompts` (4) | flat `examplePrompts` (4) |
| Messages persist | ✅ | ❌ **lost on navigation** | ✅ |
| Header | "Chat" + folders/new | (none) | "Ask AI about <Name>" + clear |

## P0
- **Per-meeting chat is ephemeral.** `UnifiedMeetingDetail.swift:96 @StateObject var meetingChat = ChatSession()` — messages vanish when you leave the meeting; cross-referencing across meetings/people is impossible. → Delete it; use the injected `chatSession`; in `MeetingChatTab.swift:10` switch `session: meetingChat` → `session: chatSession` and `chatSession.setContext(chatContext(for: m))` on appear.

## P1
- **Inconsistent capability discovery** — Today shows categorized "What can I ask?", meeting/person show flat prompts. → Use `capabilitySections` everywhere (reuse `ChatSidebar.capabilitySections()` or a meeting variant: "This Meeting / Follow-up / Analysis").
- **Redundant person-chat header** "Ask AI about <Name>" duplicates the context the AI already has → change to "Chat".

## P2 — the "overwhelming navbar"
- The header is actually minimal; the weight is the **empty-state capability panel** (4 DisclosureGroups + 12 prompts + lock label, ~300–350px). `ChatPanel.swift:81-95`. → Collapse the groups by default (only first expanded); tighten spacing; de-emphasize the lock label.
- Optional: a small **context breadcrumb** pill above the input ("About: <Meeting/Person>") so users see the AI is scoped without a heavy header (`ChatPanel.swift` inputBar ~164).

## Outcome of the refactor
One persistent, context-aware assistant across Today/Meetings/People · no message loss · unified discovery · cleaner headers · calmer empty state · clear context signaling. Local-first philosophy unchanged.
