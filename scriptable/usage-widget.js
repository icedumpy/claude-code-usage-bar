// Claude Usage — Scriptable home-screen widget
// -----------------------------------------------------------------------------
// Reads usage.json (published by the Mac "Claude Usage Bar" app into Scriptable's
// iCloud Drive Documents folder) and draws a small widget: the hero limit as a
// percent ring, its label, a reset countdown, and how long ago it synced.
//
// Setup:
//   1. Install Scriptable (free) and enable iCloud Drive for it.
//   2. Paste this script into a new Scriptable script named "ClaudeUsage".
//   3. Add a small Scriptable widget to your home screen; edit it and select
//      this script.
// The Mac app writes usage.json on every successful refresh. The widget is
// sync-stale (iCloud + WidgetKit refresh on the OS budget), so it shows the
// sync age and dims when the data is old.
// -----------------------------------------------------------------------------

const FILE_NAME = "usage.json";
const STALE_MINUTES = 30; // older than this -> dim the widget

// Palette (tinted per severity, matching the Mac app's worst-wins model).
const COLORS = {
  bg: new Color("#1c1c1e"),
  track: new Color("#3a3a3c"),
  text: new Color("#ffffff"),
  subtle: new Color("#9a9a9e"),
  normal: new Color("#34c759"),
  warning: new Color("#ffcc00"),
  severe: new Color("#ff9500"),
  critical: new Color("#ff3b30"),
  unknown: new Color("#8e8e93"),
};

function severityColor(sev) {
  return COLORS[sev] || COLORS.unknown;
}

// --- Load the synced snapshot ------------------------------------------------
// Returns { state, snap? }. States: "ok", "missing" (never synced), "pending"
// (iCloud placeholder not downloaded), "unknown" (unreadable/future format).
async function loadSnapshot() {
  const fm = FileManager.iCloud();
  const path = fm.joinPath(fm.documentsDirectory(), FILE_NAME);
  if (!fm.fileExists(path)) return { state: "missing" };
  // The file may be an iCloud placeholder that isn't downloaded locally yet.
  if (!fm.isFileDownloaded(path)) {
    // In a widget, don't rely on an in-context iCloud download finishing within
    // the tight time budget (per review) — fail soft to "pending". Only trigger
    // an actual download when previewing in-app.
    if (config.runsInWidget) return { state: "pending" };
    try { await fm.downloadFileFromiCloud(path); } catch (e) { return { state: "pending" }; }
  }
  try {
    const snap = JSON.parse(fm.readString(path));
    if (typeof snap.schema !== "number" || snap.schema > 1) return { state: "unknown" };
    return { state: "ok", snap };
  } catch (e) {
    return { state: "unknown" };
  }
}

// Simple centered message widget for the non-ok states.
function messageWidget(w, lines) {
  const head = w.addText("Claude");
  head.textColor = COLORS.subtle;
  head.font = Font.mediumSystemFont(13);
  w.addSpacer();
  lines.forEach((text, i) => {
    const t = w.addText(text);
    t.textColor = i === 0 ? COLORS.text : COLORS.subtle;
    t.font = Font.systemFont(i === 0 ? 15 : 12);
  });
  return w;
}

// --- Formatting helpers ------------------------------------------------------
function minutesSince(iso) {
  const t = Date.parse(iso);
  if (isNaN(t)) return null;
  return Math.max(0, Math.floor((Date.now() - t) / 60000));
}

function countdown(iso) {
  const t = Date.parse(iso);
  if (isNaN(t)) return null;
  let mins = Math.round((t - Date.now()) / 60000);
  if (mins <= 0) return "resetting";
  if (mins < 60) return `resets ${mins}m`;
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return `resets ${h}h${m > 0 ? m + "m" : ""}`;
}

function agoText(iso) {
  const m = minutesSince(iso);
  if (m === null) return "";
  if (m < 1) return "updated now";
  if (m < 60) return `updated ${m}m ago`;
  const h = Math.floor(m / 60);
  return `updated ${h}h ago`;
}

// --- Ring drawing ------------------------------------------------------------
function drawRing(percent, color) {
  const size = 120;
  const line = 14;
  const ctx = new DrawContext();
  ctx.size = new Size(size, size);
  ctx.opaque = false;
  ctx.respectScreenScale = true;

  const center = new Point(size / 2, size / 2);
  const radius = size / 2 - line / 2;
  const frac = Math.max(0, Math.min(1, (percent || 0) / 100));

  // Track (full circle) then the progress arc on top, drawn as short segments.
  drawArc(ctx, center, radius, line, 0, 1, COLORS.track);
  if (frac > 0) drawArc(ctx, center, radius, line, 0, frac, color);

  return ctx.getImage();
}

// Approximate a stroked arc with line segments (DrawContext has no arc stroke).
function drawArc(ctx, center, radius, width, startFrac, endFrac, color) {
  const steps = Math.max(1, Math.round((endFrac - startFrac) * 90));
  const path = new Path();
  for (let i = 0; i <= steps; i++) {
    const f = startFrac + (endFrac - startFrac) * (i / steps);
    const a = -Math.PI / 2 + f * 2 * Math.PI; // start at 12 o'clock, clockwise
    const p = new Point(center.x + radius * Math.cos(a), center.y + radius * Math.sin(a));
    if (i === 0) path.move(p); else path.addLine(p);
  }
  ctx.addPath(path);
  ctx.setStrokeColor(color);
  ctx.setLineWidth(width);
  ctx.strokePath();
}

// --- Build the widget --------------------------------------------------------
async function build() {
  const w = new ListWidget();
  w.backgroundColor = COLORS.bg;
  w.setPadding(14, 14, 14, 14);

  const { state, snap } = await loadSnapshot();

  if (state === "missing") return messageWidget(w, ["Open the Mac app", "to start syncing"]);
  if (state === "pending") return messageWidget(w, ["Syncing…", "waiting on iCloud"]);
  if (state === "unknown") return messageWidget(w, ["Update needed", "refresh the widget"]);

  const stale = (minutesSince(snap.updatedAt) ?? 0) >= STALE_MINUTES;
  const tint = severityColor(snap.severity);

  const header = w.addText("Claude");
  header.textColor = COLORS.subtle;
  header.font = Font.mediumSystemFont(13);
  w.addSpacer(6);

  // Ring + percent, centered.
  const row = w.addStack();
  row.addSpacer();
  const ringImg = w.addStack();
  ringImg.addSpacer();
  const img = ringImg.addImage(drawRing(snap.heroPercent, tint));
  img.imageSize = new Size(84, 84);
  ringImg.addSpacer();
  row.addSpacer();

  const pctText = snap.heroPercent == null ? "—" : `${Math.round(snap.heroPercent)}%`;
  const pct = w.addText(pctText);
  pct.centerAlignText();
  pct.textColor = COLORS.text;
  pct.font = Font.boldSystemFont(22);

  const label = w.addText(snap.heroLabel || "");
  label.centerAlignText();
  label.textColor = COLORS.subtle;
  label.font = Font.systemFont(11);

  w.addSpacer();

  const cd = snap.resetsAt ? countdown(snap.resetsAt) : null;
  if (cd) {
    const c = w.addText(cd);
    c.textColor = COLORS.subtle;
    c.font = Font.systemFont(11);
  }
  const ago = w.addText(agoText(snap.updatedAt));
  ago.textColor = stale ? COLORS.critical : COLORS.subtle;
  ago.font = Font.systemFont(10);

  // Dim the whole widget when the data is stale (Mac likely off).
  if (stale) w.backgroundColor = new Color("#141414");

  return w;
}

const widget = await build();
if (config.runsInWidget) {
  Script.setWidget(widget);
} else {
  await widget.presentSmall();
}
Script.complete();
