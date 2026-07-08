# Claude Usage Bar

[![CI](https://github.com/icedumpy/claude-code-usage-bar/actions/workflows/ci.yml/badge.svg)](https://github.com/icedumpy/claude-code-usage-bar/actions/workflows/ci.yml)

A tiny menu bar app for your Mac that shows how much of your Claude Code usage
you've got left — right next to the clock, so you always know before you hit a
limit.

<p align="center">
  <img src="docs/hero-race.png" alt="Claude Usage Bar — the menu bar badge and its dropdown" width="340">
</p>

## What it does

- **At a glance:** a small colored dot in your menu bar — green when you're
  fine, amber when you're getting close, red when you're nearly out — next to
  your usage percentage.
- **The full picture:** click it for your 5-hour and weekly limits, when each
  one resets, and a per-model breakdown of what you've used this week.
- **A heads-up before you hit a wall:** an optional notification when you cross
  80% (and 95%).
- **Stays out of the way:** it lives in the menu bar, not the Dock, and updates
  itself quietly in the background.

## Before you install

You need **Claude Code installed and signed in with a Claude subscription**
(Pro or Max) — this app just reads the usage that Claude Code already tracks. If
you use Claude through a pay-as-you-go API key instead of a subscription, the
usage numbers won't show up (you'll see a **!** in the menu bar).

You'll also need **macOS 13 or later** (any Mac from the last several years, Intel
or Apple Silicon).

## Install (recommended)

Copy this line, paste it into the **Terminal** app, and press Return:

```sh
curl -fsSL https://raw.githubusercontent.com/icedumpy/claude-code-usage-bar/main/scripts/install-release.sh | bash
```

That's it. It downloads the app, puts it in your Applications folder, and opens
it — no security prompts to fight. (New to Terminal? It's in
Applications → Utilities, or press ⌘-Space and type "Terminal".)

Look for the colored Claude dot in your menu bar, up near the clock.

<details>
<summary><b>Prefer not to use Terminal? Install by hand instead.</b></summary>

This works too, but because the app isn't signed through Apple's paid developer
program, macOS will show an extra security prompt the first time — see
[If macOS blocks the app](#if-macos-blocks-the-app) below.

1. Download **ClaudeUsageBar.zip** from the
   [latest release](https://github.com/icedumpy/claude-code-usage-bar/releases/latest).
2. Double-click the zip to unpack it, then drag **ClaudeUsageBar** into your
   **Applications** folder.
3. Open it (see the security-prompt note below if macOS stops you).

</details>

## If macOS blocks the app

If you installed by hand, macOS may say the app *"cannot be opened because Apple
cannot check it for malicious software"* or that it's from an *"unidentified
developer."* That's expected: it just means the app isn't signed through
Apple's $99/year developer program — **not** that anything is wrong with it.
The code is open source and right here in this repo.

To allow it (one time):

1. Try to open the app once and let the warning appear, then close it.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the Security section — you'll see a line about ClaudeUsageBar
   being blocked. Click **Open Anyway** and confirm.
4. Open the app again.

(The recommended Terminal install above skips all of this.)

## First run

- The app appears as a **colored Claude dot in the menu bar**, not in the Dock.
  If you don't see it, your menu bar may be full — try quitting an app or two,
  or widening the bar.
- **Click the dot** to see your limits and this week's breakdown.
- To have it start automatically with your Mac: click the dot, choose
  **Settings…**, and turn on **Launch at login**.

> The dollar amounts are an *estimate of value*, not a bill. On a subscription
> you pay a flat fee; the figure shows what the same usage would cost at
> pay-as-you-go API prices. You are **not** being charged that.

## A few handy extras

- **Pick what the menu bar shows** (Settings): the percentage, the week's dollar
  estimate, or both — and which limit it tracks (the 5-hour window, a weekly
  limit, or whichever is most urgent).
- **Rabbit-and-turtle view:** an optional way to draw each limit as a race — a
  rabbit (your usage) chasing a turtle (time elapsed) — so you can instantly see
  if you're burning faster than the clock. Turn it on in Settings.
- **Pin it on top:** the **Pin** button in the dropdown floats a small always-on-
  top panel that stays visible over any window or fullscreen app. Drag it
  anywhere; drag its right edge to make it wider; adjust its see-through-ness in
  Settings.

## Keeping it up to date

When a new version is out, the dropdown shows an **Update available** banner —
click **Update & Relaunch** and the app updates itself and restarts. No Terminal,
nothing to download by hand. Your settings and any custom icons are kept.

> Already on an old version (1.0.0 or earlier)? That build doesn't have the
> one-click updater yet, so do the [recommended install](#install-recommended)
> once more to get onto it — after that, updates are a single click.

## iPhone widget (optional)

Want your usage on your phone's home screen too? You can, with no Apple Developer
account and no App Store, using the free [Scriptable](https://scriptable.app)
app. The Mac app writes a small summary (percentages and reset times only —
never your login token) into Scriptable's iCloud folder, and a widget shows it
on your phone. It updates whenever your Mac is on and syncs, and dims when the
data gets stale.

<details>
<summary>One-time setup</summary>

**Before you start**, this needs iCloud to carry the file from your Mac to your
phone, so:

- Your **Mac and iPhone must be signed into the same iCloud account** (Apple ID).
  Check on the Mac in **System Settings → [your name]** and on the phone in
  **Settings → [your name]** — the email at the top should match.
- **iCloud Drive must be on** on *both*. On the Mac: **System Settings → [your
  name] → iCloud → iCloud Drive → on**. On the phone: same path.

If those don't match, the phone will never see the data no matter what else you
do — that's the most common reason it "doesn't work."

1. Install **Scriptable** from the App Store and turn on iCloud Drive for it
   (Settings → your name → iCloud → Drive → **Scriptable** on).
2. In this app's **Settings**, turn on **Sync to iPhone widget**. The Settings
   panel then shows the sync status, so you can tell when your phone is connected.
3. Run the Mac app once. It writes the usage summary **and** drops the widget
   script (**ClaudeUsage**) straight into Scriptable — no copying and pasting.
4. Open **Scriptable** on your phone. After iCloud syncs (a minute or two), a
   script named **ClaudeUsage** appears in the list. Tap it once to check it runs.
5. Add it to your home screen: long-press → add a small **Scriptable** widget →
   edit it → choose **ClaudeUsage**.

**On the nightstand (StandBy):** on iOS 17+ you can show this in StandBy — the
sideways, always-on view while the phone charges. Turn the phone landscape on a
charger to enter StandBy, swipe to the widgets panel, long-press → **+** → add a
small **Scriptable** widget → choose **ClaudeUsage**. It refreshes on your Mac's
schedule and spells out "STALE" if the data gets old (handy since StandBy's night
tint would otherwise hide a color-only warning).

**If the script or numbers don't show up right away:** the first iCloud sync can
take a few minutes, especially if you just turned iCloud Drive on. Keep both
devices on Wi-Fi and open Scriptable on the phone for a moment to nudge it. The
app's **Settings** panel tells you whether it's still "waiting for Scriptable's
iCloud folder" or already synced.

*Already set the widget up by hand before?* If you pasted the script yourself,
the app won't touch your copy (it never overwrites your edits). To switch to the
auto-updating one, delete your **ClaudeUsage** script in Scriptable and run the
Mac app again — it'll reinstall a managed copy.

If Scriptable isn't installed, the Mac app just skips this — nothing else
changes.

</details>

## Privacy

The app has no server of its own and no hidden secrets. Your Claude login token
is read from *your* Mac's Keychain at runtime and sent only to Anthropic — the
exact same thing Claude Code itself does — never to the author or anyone else.
The usage and cost breakdown is calculated entirely from files already on your
Mac.

## Questions & troubleshooting

- **I see a `!` in the menu bar.** You're not signed in to Claude Code with a
  subscription. Open Claude Code, sign in, and it'll clear.
- **I see a `?` or the numbers look stale.** The app couldn't reach Anthropic
  just now (a hiccup or a rate limit). It keeps showing the last known numbers
  and retries automatically.
- **Nothing in the menu bar.** The bar may be full and hiding it — free up space,
  or check the app is running (it has no Dock icon).
- **Is this official?** No — it's an independent, open-source app that reads the
  same usage data Claude Code uses.

## For developers

Building from source, how it works under the hood, the architecture, and the
release process live in **[DEVELOPMENT.md](DEVELOPMENT.md)**. Contributions
welcome.

## License

MIT — see [LICENSE](LICENSE).
