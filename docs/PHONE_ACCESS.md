# Phone access — browse & edit your vault from your iPhone

MeetingScribe can serve your meetings, people, projects, and tasks to a phone
browser **straight off your Mac**. There is no cloud database, no account, and
nothing to pay for. Your data never leaves your machine — the phone just talks
to a small web server running inside the MeetingScribe app.

Two ways to reach it:

- **Same Wi-Fi** — works out of the box once you flip the switch.
- **From anywhere** — pair it with [Tailscale](https://tailscale.com) (free for
  personal use), a private encrypted network between *your own* devices. Still
  no public internet exposure, still no cloud copy of your data.

---

## How it works (the short version)

- The app opens a small web server on a port (default **8765**).
- Your phone's browser loads a mobile web app from that server and reads/writes
  through the same code paths the desktop app uses — so a task you check off on
  your phone is saved, indexed, and de-duplicated exactly like one you check off
  on the Mac.
- Access is gated by a secret **access token**. The QR code in Settings encodes
  a link that carries the token, so scanning it logs the phone in once and
  remembers it. Anyone without the token gets a 401.

> Security note: the token grants the same read/write access to your vault that
> a logged-in desktop session has. Only share the QR code / link with your own
> devices. You can rotate the token at any time (see *Regenerate token* below),
> which signs every paired phone out.

---

## Part 1 — Turn it on (same Wi‑Fi)

1. Open **MeetingScribe → Settings** (⌘,).
2. Find **Phone access (web)**.
3. Toggle **“Serve my vault to phone browsers”** on.
   - The first time, macOS may ask *“Do you want the application
     MeetingScribe to accept incoming network connections?”* — click **Allow**.
4. A **QR code** and one or more connection links appear.
5. On your iPhone, make sure it's on the **same Wi‑Fi** as the Mac, then open the
   **Camera** app and point it at the QR code. Tap the notification to open the
   link in Safari.
   - The link looks like `http://192.168.x.x:8765/?t=…`.
   - Don't have a QR scanner handy? Tap the copy button next to the
     **“Same Wi‑Fi”** link, AirDrop/Message it to yourself, and open it.
6. You're in. Add it to your Home Screen for an app-like experience: in Safari,
   tap **Share → Add to Home Screen**.

That's everything for home/office use. The rest of this doc is only needed if
you want access when you're **away** from that network.

---

## Part 2 — Access from anywhere with Tailscale (free)

Tailscale builds a private, encrypted network ("tailnet") that only your own
signed-in devices can join. Your Mac becomes reachable from your phone over
cellular without exposing anything to the public internet and without copying
your data anywhere.

### 2a. Install Tailscale on the Mac

1. Download the Mac app from <https://tailscale.com/download/mac> (the standalone
   app is simplest), or `brew install --cask tailscale`.
2. Open Tailscale and **sign in** (Google/GitHub/Microsoft/email — pick one).
3. Once connected, the menu-bar Tailscale icon shows this Mac's tailnet IP,
   something like **`100.x.y.z`**. (You can also find it with
   `tailscale ip -4` in Terminal.)

### 2b. Install Tailscale on the iPhone

1. Install **Tailscale** from the App Store.
2. **Sign in with the same account** you used on the Mac.
3. Turn the VPN on (toggle in the Tailscale app). iOS will ask to add a VPN
   configuration — allow it.

### 2c. Connect

1. Back in **MeetingScribe → Settings → Phone access**, you'll now see an
   **“Anywhere (Tailscale)”** link (the QR code prefers it automatically when
   Tailscale is running).
2. Scan the QR code or copy that link to your phone. It looks like
   `http://100.x.y.z:8765/?t=…`.
3. As long as Tailscale is connected on both devices, that link works from
   anywhere — coffee shop, cell network, hotel Wi‑Fi.

> Tip: Tailscale also gives each device a name (MagicDNS), so a link like
> `http://your-mac-name:8765` works too once MagicDNS is enabled in the
> Tailscale admin console. The numeric `100.x` address always works regardless.

---

## Keeping it running

- The web server runs **while MeetingScribe is open**. If you quit the app, the
  phone can't connect. (MeetingScribe normally lives in your menu bar, so this
  is rarely an issue.) If you want it always-on even when the app is quit, that
  would be a future enhancement (a background login-item service).
- The toggle state is remembered, so it comes back on automatically next launch.

## Managing access

- **Change the port:** edit the Port field in Settings and click **Apply** (use
  1024–65535; 8765 is the default). Re-scan the QR code afterward.
- **Regenerate token:** click **Regenerate access token** to invalidate the old
  one. Every paired phone is signed out and must re-scan the new QR code. Do this
  if you ever shared a link by accident.

## What you can do from the phone

- **Meetings** — browse, read summaries & transcripts, edit the title and your
  notes.
- **Tasks** — view/filter by status, check items off, create, edit (status,
  priority, due date, project, notes), delete.
- **People** — browse, view encounters & linked tasks, edit details, add a
  person.
- **Projects** — browse, edit the project notes, see its tasks; create a project.
- **Search** — across meetings, people, tasks, and projects.

## Troubleshooting

- **“Safari can't open the page.”** Confirm MeetingScribe is running and the
  toggle is on. On same-Wi‑Fi, confirm both devices are on the same network. On
  cellular, confirm Tailscale is connected on **both** the Mac and the phone.
- **macOS firewall.** System Settings → Network → Firewall. If it's on, make sure
  MeetingScribe is allowed to **accept incoming connections** (you'll usually get
  a prompt the first time the server starts).
- **“Port in use” / server won't start.** Another app may hold 8765. Change the
  port in Settings and Apply.
- **401 Unauthorized.** Your phone's saved token is stale (e.g. you regenerated
  it). Re-scan the current QR code.
- **Edits don't show in the open desktop window immediately.** They're saved to
  disk and the index right away; the desktop view refreshes when you navigate to
  it again.
