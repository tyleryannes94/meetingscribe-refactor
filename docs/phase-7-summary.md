# Phase 7 — People Mindmap + iPhone Input

Branch: `phase/7-people-mindmap`

Phase 7 adds an interactive, force-directed mindmap to the People tab and three
ways to get people into MeetingScribe from a phone or external source. No
third-party libraries — the graph layout, rendering, QR code, and local HTTP
server are all first-party (SwiftUI Canvas, CoreImage, Network.framework).

## 7-A — Node/Edge mindmap (`Sources/MeetingScribe/People/Graph/`)

| File | Role |
|------|------|
| `PersonNode.swift` | Laid-out person; position, pin/selection state, size (56→72pt for >5 meetings), initials fallback. |
| `RelationshipEdge.swift` | Undirected connection; shared tags, shared-meeting count, derived 0–1 weight, render width. |
| `GraphLayoutEngine.swift` | `GraphLayout` — simplified Fruchterman–Reingold. Repulsion `k²/d`, attraction `d²/k`, `k=√(area/n)`, 150 iterations with cooling, pinned nodes skipped, clamped to bounds. |
| `PeopleGraphViewModel.swift` | `@Observable @MainActor`. `buildGraph`, `applyForceLayout`, `filterByTags`, selection, pinning, remove, and BFS `findPath` for shortest-path highlight. |
| `PersonNodeView.swift` | Avatar (photo or tinted initials), name, ≤3 tag pills (+N), selection ring, pin badge, dim-when-unfocused, context menu (Pin/Profile/Find Connections/Remove). |
| `GraphFilterBar.swift` | Search field, scrolling tag chips (toggle filters, pulse when active), Reset, Re-layout, List View. |
| `GraphDetailPanel.swift` | 300pt right panel for the selected person: tags, last-interaction, meeting count, connections list with shared context, View Profile, Find Path menu. |
| `PeopleGraphView.swift` | Canvas edge rendering + node overlay, pan (drag) / zoom (`MagnifyGesture`) / per-node drag, selection dimming, midpoint count pills for >2 shared meetings, legend, empty state. |

**Edge rule:** two people connect if they share ≥1 tag **or** appeared in ≥1
meeting together (`Person.meetingMentions` intersection). Edge color comes from
the first shared people-tag (`MeetingTag.colorHex`), else the brand accent;
width scales with weight; a midpoint pill shows the shared-meeting count when >2.

**Wiring:** `PeopleListView` gains a "Graph View" toolbar button that swaps the
list/detail split for `PeopleGraphView`; the graph's "List View" button and a
node double-tap / "View Profile" return to the list and select that person.

## 7-B — iPhone & external input (`Sources/MeetingScribe/People/iPhone/`)

| File | Role |
|------|------|
| `iPhoneInputService.swift` | `Network.framework` HTTP server on an ephemeral port. Serves a mobile form on GET, creates a `Person` on `POST /add-person`. LAN IP via `getifaddrs`. |
| `iPhoneInputHTML.swift` | Self-contained mobile form + confirmation pages (inline CSS, base64 photo shim). |
| `iPhoneInputQRView.swift` | Start/Stop toggle, `CIQRCodeGenerator` QR for the URL, copyable URL, live connection/added counts. |
| `ContactsImporter.swift` (extended) | `importContact(_:)→Person`, `importAll(matching:)→[Person]`, `suggestFromMeetings(participantNames:)→[CNContact]`. |
| `ContactsImportView.swift` | Searchable, multi-select Contacts list with a pre-import diff (N new / M existing), imports via `PeopleStore.importPeople` (dedupes). |
| `iPhoneInputSettingsView.swift` | Aggregates QR + Contacts + CSV bulk import (columns: name, role, company, email, tags). |

**Wiring:** the People import menu gains "Add via iPhone / Contacts / CSV…",
opening `iPhoneInputSettingsView` as a sheet.

## Design decisions (made autonomously per Task 4)

- **`id` is `String`, not `UUID`.** The spec types node/edge ids as `UUID`, but
  `Person.id` is a `String` (UUID string) across the whole codebase
  (Meeting/QuickNote/tags key on `String`). Nodes/edges mirror that so they
  cross-reference `Person` and the FTS index with no type bridge.
- **iPhone form posts URL-encoded, not multipart.** The optional photo is
  base64-encoded into a hidden field by a tiny JS `FileReader` shim, which
  avoids multipart parsing for a single contact.
- **Ephemeral server port.** `NWListener` takes a system-assigned port (read
  back from `listener.port`) so it never collides with another process.
- **`suggestFromMeetings` takes participant names.** The spec's no-arg signature
  can't match anything; the roster is passed in and resolved against Contacts.
- **CSV bulk import creates directly** (via `PeopleStore.createPerson`) so the
  `tags` column is honored; users can run "Merge duplicates" afterward.

## Build

`swift build` and `swift build -c release` both succeed. Force layout, BFS
path-finding, QR generation, and the HTTP server are all dependency-free.

## Known follow-ups (see the Next Level audit)

- Lazy node rendering for 200+ contacts (only layout/draw the visible viewport).
- Cluster/community detection and a timeline animation of the graph.
- Export graph as SVG/PDF; privacy blur for screenshots.
