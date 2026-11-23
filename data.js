"use strict";

/* ============================================================
   Xpense — data layer
   Storage, constants, and pure domain logic. No DOM access here.
   ============================================================ */

const STORAGE_KEY = "xpense.data.v1";
const SETTINGS_KEY = "xpense.settings.v1";
const STOPPED_KEY = "xpense.stopped.v1";
const META_KEY = "xpense.meta.v1";
const SCHEMA_VERSION = 1;
const CATEGORIES_KEY = "xpense.categories.v1";

const DEFAULT_CATEGORIES = [
  "Housing",
  "Utilities",
  "Subscriptions",
  "Insurance",
  "Food",
  "Transport",
  "Health",
  "Entertainment",
  "Debt",
  "Other",
];

const DEFAULT_ITEMS = [
  { name: "Rent / Mortgage", amount: 1200, category: "Housing", dueDay: 1 },
  { name: "Electricity", amount: 90, category: "Utilities", dueDay: 10 },
  { name: "Water", amount: 40, category: "Utilities", dueDay: 10 },
  { name: "Internet", amount: 60, category: "Utilities", dueDay: 15 },
  { name: "Phone", amount: 45, category: "Utilities", dueDay: 20 },
  { name: "Netflix", amount: 15.49, category: "Subscriptions", dueDay: 5 },
  { name: "Spotify", amount: 11.99, category: "Subscriptions", dueDay: 8 },
  { name: "Gym", amount: 35, category: "Subscriptions", dueDay: 3 },
  { name: "Car insurance", amount: 120, category: "Insurance", dueDay: 12 },
];

let state = loadState();
let settings = loadSettings();
let currentMonth = currentMonthKey();
let filter = "all";
let stoppedSeries = loadStopped();
let categories = loadCategories();

const RECUR_INTERVALS = {
  monthly: 1,
  bimonthly: 2,
  quarterly: 3,
  biannually: 6,
  annually: 12,
};

const RECUR_LABELS = {
  monthly: "Every month",
  bimonthly: "Every other month",
  quarterly: "Every 3 months",
  biannually: "Every 6 months",
  annually: "Every year",
};

function recurInterval(recur) {
  return RECUR_INTERVALS[recur] || 0;
}

function recurLabel(recur) {
  return RECUR_LABELS[recur] || "";
}

/* ---------- Storage ---------- */

function loadState() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY)) || {};
  } catch {
    return {};
  }
}

function saveState() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function loadSettings() {
  const defaults = { currency: "PHP" };
  try {
    return { ...defaults, ...(JSON.parse(localStorage.getItem(SETTINGS_KEY)) || {}) };
  } catch {
    return defaults;
  }
}

function saveSettings() {
  localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
}

function loadStopped() {
  try {
    return new Set(JSON.parse(localStorage.getItem(STOPPED_KEY)) || []);
  } catch {
    return new Set();
  }
}

function saveStopped() {
  localStorage.setItem(STOPPED_KEY, JSON.stringify([...stoppedSeries]));
}

function isStopped(seriesId) {
  return stoppedSeries.has(seriesId);
}

function migrate() {
  let version = 0;
  try {
    version = JSON.parse(localStorage.getItem(META_KEY))?.version || 0;
  } catch {
    version = 0;
  }
  // Future migrations go here, e.g.: if (version < 2) { ... }
  try {
    localStorage.setItem(META_KEY, JSON.stringify({ version: SCHEMA_VERSION }));
  } catch {}
}

function loadCategories() {
  try {
    const arr = JSON.parse(localStorage.getItem(CATEGORIES_KEY));
    return Array.isArray(arr) && arr.length ? arr : [...DEFAULT_CATEGORIES];
  } catch {
    return [...DEFAULT_CATEGORIES];
  }
}

function saveCategories() {
  localStorage.setItem(CATEGORIES_KEY, JSON.stringify(categories));
}

function ensureCategoriesCoverItems() {
  const used = new Set();
  for (const k of allMonthKeys()) {
    for (const item of state[k] || []) {
      if (item.category) used.add(item.category);
    }
  }
  let changed = false;
  for (const c of used) {
    if (!categories.includes(c)) {
      categories.push(c);
      changed = true;
    }
  }
  if (changed) saveCategories();
}

/* ---------- Month helpers ---------- */

function currentMonthKey() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

function shiftMonth(key, delta) {
  const [y, m] = key.split("-").map(Number);
  const d = new Date(y, m - 1 + delta, 1);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

function monthLabel(key) {
  const [y, m] = key.split("-").map(Number);
  return new Date(y, m - 1, 1).toLocaleDateString(undefined, {
    month: "long",
    year: "numeric",
  });
}

function ordinal(n) {
  const s = ["th", "st", "nd", "rd"];
  const v = n % 100;
  return n + (s[(v - 20) % 10] || s[v] || s[0]);
}

/* ---------- Data helpers ---------- */

function monthItems() {
  return materializeMonth(currentMonth);
}

function monthIndex(key) {
  const [y, m] = key.split("-").map(Number);
  return y * 12 + (m - 1);
}

function monthDiff(a, b) {
  return monthIndex(a) - monthIndex(b);
}

function allMonthKeys() {
  return Object.keys(state).filter((k) => /^\d{4}-\d{2}$/.test(k));
}

function copyRecurring(src) {
  return {
    id: makeId(),
    seriesId: src.seriesId,
    recur: src.recur,
    anchor: src.anchor,
    name: src.name,
    amount: src.amount,
    dueDay: src.dueDay,
    category: src.category,
    paid: false,
    auto: true,
  };
}

function materializeMonth(key) {
  const existing = Array.isArray(state[key]) ? state[key] : [];

  // Resolve each recurring series from its most recent prior occurrence.
  const expected = new Map(); // seriesId -> most recent source item
  const prior = allMonthKeys()
    .filter((k) => k < key)
    .sort((a, b) => (a < b ? 1 : -1));
  const resolved = new Set();

  for (const k of prior) {
    for (const src of state[k]) {
      if (!src.seriesId) continue; // one-time item
      if (isStopped(src.seriesId)) continue; // stopped series never rolls forward
      if (resolved.has(src.seriesId)) continue; // already resolved a more recent occurrence
      resolved.add(src.seriesId);

      const interval = recurInterval(src.recur);
      if (interval > 0) {
        const anchor = src.anchor || k;
        if (monthDiff(key, anchor) % interval === 0) {
          expected.set(src.seriesId, src);
        }
      }
    }
  }

  // Keep every user-entered item. Only auto-rolled copies whose series no
  // longer applies (turned off or stopped) are removed.
  const kept = existing.filter((item) => {
    if (!item.seriesId) return true; // one-time user item
    if (!item.auto) return true;     // user-entered recurring source
    if (isStopped(item.seriesId)) return false;
    return expected.has(item.seriesId);
  });

  // Add any expected recurring items not already present this month.
  for (const [seriesId, src] of expected) {
    if (!kept.some((item) => item.seriesId === seriesId)) {
      kept.push(copyRecurring(src));
    }
  }

  // Only persist when something actually changed (also avoids a save
  // storm when multiple tabs are syncing via the storage event).
  const changed =
    !Array.isArray(state[key]) ||
    kept.length !== state[key].length ||
    kept.some((item, i) => item !== state[key][i]);

  if (changed) {
    state[key] = kept;
    saveState();
  }

  return state[key];
}

function makeId() {
  return Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
}

function money(amount) {
  return new Intl.NumberFormat(undefined, {
    style: "currency",
    currency: settings.currency,
  }).format(amount || 0);
}

/* ---------- Recurrence helpers ---------- */

function isRecurring(item) {
  return !!(item && item.seriesId && item.recur && item.recur !== "none");
}

function collectRecurringRules() {
  const rules = new Map(); // seriesId -> { ...item, month }
  for (const k of allMonthKeys().sort()) {
    for (const item of state[k] || []) {
      if (!isRecurring(item)) continue;
      if (isStopped(item.seriesId)) continue;
      rules.set(item.seriesId, { ...item, month: k });
    }
  }
  return [...rules.values()].sort((a, b) => (a.dueDay || 99) - (b.dueDay || 99));
}

function stopSeries(seriesId) {
  if (isStopped(seriesId)) return;
  stoppedSeries.add(seriesId);
  for (const k of allMonthKeys()) {
    const arr = state[k] || [];
    const kept = [];
    for (const item of arr) {
      if (item.seriesId !== seriesId) {
        kept.push(item);
      } else if (k <= currentMonth) {
        // Keep as a one-time historical record.
        item.recur = "none";
        delete item.auto;
        kept.push(item);
      }
      // else: drop future occurrences
    }
    state[k] = kept;
  }
  saveStopped();
  saveState();
}

function getDueStatus(item) {
  if (item.paid || !item.dueDay) return null;
  if (currentMonth !== currentMonthKey()) return null; // only annotate the real current month
  const today = new Date().getDate();
  if (item.dueDay < today) return { kind: "overdue", label: "Overdue" };
  if (item.dueDay === today) return { kind: "due-today", label: "Due today" };
  if (item.dueDay - today <= 3) return { kind: "due-soon", label: "Due soon" };
  return null;
}

/* ---------- Seeding ---------- */

function seedIfEmpty() {
  // Seed default bills only on a completely fresh install.
  if (Object.keys(state).length > 0) return;
  state[currentMonth] = DEFAULT_ITEMS.map((it) => ({
    ...it,
    id: makeId(),
    seriesId: makeId(),
    recur: "monthly",
    paid: false,
  }));
  saveState();
}
