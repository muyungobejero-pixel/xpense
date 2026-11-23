"use strict";

/* ============================================================
   Xpense — actions & wiring
   CRUD operations, event handlers, and app initialization.
   ============================================================ */

/* ---------- Actions ---------- */

function togglePaid(id) {
  const item = monthItems().find((i) => i.id === id);
  if (!item) return;
  item.paid = !item.paid;
  saveState();
  render();
}

function openAdd() {
  els.modalTitle.textContent = "Add expense";
  els.form.reset();
  els.fieldId.value = "";
  els.deleteBtn.hidden = true;
  els.stopRecurBtn.hidden = true;
  els.deleteBtn.textContent = "Delete";
  renderCategoryOptions("");
  els.modal.hidden = false;
  els.fieldName.focus();
}

function openEdit(id) {
  const item = monthItems().find((i) => i.id === id);
  if (!item) return;
  els.modalTitle.textContent = "Edit expense";
  els.fieldId.value = item.id;
  els.fieldName.value = item.name;
  els.fieldAmount.value = item.amount;
  els.fieldDue.value = item.dueDay || "";
  renderCategoryOptions(item.category || "");
  els.fieldRecur.value = item.recur || "none";
  els.deleteBtn.hidden = false;
  els.stopRecurBtn.hidden = !isRecurring(item);
  els.deleteBtn.textContent = isRecurring(item) ? "Delete this month" : "Delete";
  els.modal.hidden = false;
  els.fieldName.focus();
}

function closeModal() {
  els.modal.hidden = true;
}

function saveFromForm(e) {
  e.preventDefault();
  const id = els.fieldId.value;
  const name = els.fieldName.value.trim();
  const amount = parseFloat(els.fieldAmount.value);
  const dueDay = els.fieldDue.value ? parseInt(els.fieldDue.value, 10) : null;
  const addingCategory = els.fieldCategory.value === "__add__";
  const category = (addingCategory ? els.fieldCategoryNew.value : els.fieldCategory.value).trim();
  const recur = els.fieldRecur.value || "none";

  if (!name || isNaN(amount) || amount < 0) return;

  if (category && !categories.includes(category)) {
    categories.push(category);
    categories.sort((a, b) => a.localeCompare(b));
    saveCategories();
  }

  const items = monthItems();
  if (id) {
    const item = items.find((i) => i.id === id);
    if (item) {
      const prevRecur = item.recur;
      item.name = name;
      item.amount = amount;
      item.dueDay = dueDay;
      item.category = category;
      item.recur = recur;
      if (recur !== "none") {
        if (!item.seriesId) item.seriesId = makeId();
        if (prevRecur !== recur || !item.anchor) item.anchor = currentMonth;
        if (stoppedSeries.delete(item.seriesId)) saveStopped();
      }
    }
  } else {
    items.push({
      id: makeId(),
      seriesId: recur !== "none" ? makeId() : undefined,
      recur,
      anchor: recur !== "none" ? currentMonth : undefined,
      name,
      amount,
      dueDay,
      category,
      paid: false,
    });
  }

  saveState();
  closeModal();
  render();
}

function deleteCurrent() {
  const id = els.fieldId.value;
  if (!id) return;
  const items = monthItems();
  const idx = items.findIndex((i) => i.id === id);
  if (idx === -1) return;
  if (!confirm(`Delete "${items[idx].name}"?`)) return;
  items.splice(idx, 1);
  saveState();
  closeModal();
  render();
}

function stopCurrentRecurring() {
  const id = els.fieldId.value;
  const item = monthItems().find((i) => i.id === id);
  if (!item || !item.seriesId) return;
  if (!confirm(`Stop "${item.name}" from recurring? Current and past months are kept; future months are removed.`)) return;
  stopSeries(item.seriesId);
  closeModal();
  render();
}

function openRecurringModal() {
  renderRecurringList();
  els.recurringModal.hidden = false;
}

function stopRule(rule) {
  if (!confirm(`Stop "${rule.name}" from recurring?`)) return;
  stopSeries(rule.seriesId);
  renderRecurringList();
  render();
}

function editRule(rule) {
  els.recurringModal.hidden = true;
  currentMonth = rule.month;
  render();
  openEdit(rule.id);
}

function resetAll() {
  if (!confirm("Delete all saved expenses for every month? This cannot be undone.")) return;
  state = {};
  saveState();
  settings = { currency: settings.currency };
  saveSettings();
  categories = [...DEFAULT_CATEGORIES];
  saveCategories();
  seedIfEmpty();
  render();
}

/* ---------- Settings ---------- */

function openSettings() {
  els.fieldCurrency.value = settings.currency;
  renderCategoryManager();
  els.settingsModal.hidden = false;
}

function saveSettingsForm(e) {
  e.preventDefault();
  settings.currency = els.fieldCurrency.value;
  saveSettings();
  els.settingsModal.hidden = true;
  render();
}

/* ---------- Data backup ---------- */

function exportData() {
  const payload = {
    app: "xpense",
    version: SCHEMA_VERSION,
    exportedAt: new Date().toISOString(),
    state,
    settings,
    categories,
    stoppedSeries: [...stoppedSeries],
  };
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `xpense-backup-${currentMonthKey()}.json`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

function importData(file) {
  const reader = new FileReader();
  reader.onload = () => {
    try {
      const data = JSON.parse(reader.result);
      if (!data || typeof data !== "object" || !data.state) throw new Error("Not an Xpense backup file");
      if (!confirm("Replace all current data with this backup? This cannot be undone.")) return;
      state = typeof data.state === "object" && data.state ? data.state : {};
      settings = { currency: (data.settings && data.settings.currency) || "PHP" };
      categories = Array.isArray(data.categories) && data.categories.length ? data.categories : [...DEFAULT_CATEGORIES];
      stoppedSeries = new Set(Array.isArray(data.stoppedSeries) ? data.stoppedSeries : []);
      saveState();
      saveSettings();
      saveCategories();
      saveStopped();
      currentMonth = currentMonthKey();
      els.fieldCurrency.value = settings.currency;
      renderCategoryManager();
      render();
      alert("Backup restored.");
    } catch (err) {
      alert("Could not import: " + (err && err.message ? err.message : "invalid file"));
    }
  };
  reader.readAsText(file);
}

/* ---------- Category management ---------- */

function deleteCategory(name) {
  if (!categories.includes(name)) return;
  if (!confirm(`Delete category "${name}"? Any expenses using it will have their category cleared.`)) return;
  categories = categories.filter((c) => c !== name);
  for (const k of allMonthKeys()) {
    for (const item of state[k] || []) {
      if (item.category === name) item.category = "";
    }
  }
  saveCategories();
  saveState();
  renderCategoryManager();
  render();
}

function renameCategory(name) {
  const newName = prompt("Rename category:", name);
  if (newName === null) return;
  const trimmed = newName.trim();
  if (!trimmed || trimmed === name) return;
  if (categories.includes(trimmed)) {
    alert(`Category "${trimmed}" already exists.`);
    return;
  }
  const idx = categories.indexOf(name);
  categories[idx] = trimmed;
  for (const k of allMonthKeys()) {
    for (const item of state[k] || []) {
      if (item.category === name) item.category = trimmed;
    }
  }
  saveCategories();
  saveState();
  renderCategoryManager();
  render();
}

/* ---------- Wire up events ---------- */

els.prev.addEventListener("click", () => {
  currentMonth = shiftMonth(currentMonth, -1);
  render();
});
els.next.addEventListener("click", () => {
  currentMonth = shiftMonth(currentMonth, 1);
  render();
});
els.today.addEventListener("click", () => {
  currentMonth = currentMonthKey();
  render();
});
els.monthLabel.addEventListener("click", () => {
  currentMonth = currentMonthKey();
  render();
});

els.filters.forEach((btn) => {
  btn.addEventListener("click", () => {
    filter = btn.dataset.filter;
    els.filters.forEach((b) => {
      const active = b === btn;
      b.classList.toggle("active", active);
      b.setAttribute("aria-selected", String(active));
    });
    renderList(monthItems());
  });
});

els.addBtn.addEventListener("click", openAdd);
els.emptyAdd.addEventListener("click", openAdd);
els.modalClose.addEventListener("click", closeModal);
els.cancelBtn.addEventListener("click", closeModal);
els.form.addEventListener("submit", saveFromForm);
els.fieldCategory.addEventListener("change", () => {
  const adding = els.fieldCategory.value === "__add__";
  els.categoryNewWrap.hidden = !adding;
  if (adding) els.fieldCategoryNew.focus();
});
els.deleteBtn.addEventListener("click", deleteCurrent);
els.stopRecurBtn.addEventListener("click", stopCurrentRecurring);

els.settingsBtn.addEventListener("click", openSettings);
els.settingsClose.addEventListener("click", () => (els.settingsModal.hidden = true));
els.settingsForm.addEventListener("submit", saveSettingsForm);
els.resetBtn.addEventListener("click", resetAll);
els.exportBtn.addEventListener("click", exportData);
els.importBtn.addEventListener("click", () => els.importFile.click());
els.importFile.addEventListener("change", (e) => {
  const file = e.target.files && e.target.files[0];
  if (file) importData(file);
  e.target.value = "";
});
els.recurringBtn.addEventListener("click", openRecurringModal);
els.recurringClose.addEventListener("click", () => (els.recurringModal.hidden = true));

// Close modals when clicking the backdrop.
[els.modal, els.settingsModal, els.recurringModal].forEach((m) => {
  m.addEventListener("click", (e) => {
    if (e.target === m) m.hidden = true;
  });
});

// Close on Escape.
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    els.modal.hidden = true;
    els.settingsModal.hidden = true;
    els.recurringModal.hidden = true;
  }
});

// Keep multiple browser tabs in sync.
window.addEventListener("storage", (e) => {
  if (e.key === STORAGE_KEY) {
    state = loadState();
    render();
  } else if (e.key === SETTINGS_KEY) {
    settings = loadSettings();
    render();
  } else if (e.key === STOPPED_KEY) {
    stoppedSeries = loadStopped();
    render();
  } else if (e.key === CATEGORIES_KEY) {
    categories = loadCategories();
    render();
  }
});

/* ---------- Init ---------- */

migrate();
seedIfEmpty();
ensureCategoriesCoverItems();
render();
