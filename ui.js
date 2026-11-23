"use strict";

/* ============================================================
   Xpense — UI layer
   DOM references and rendering. No business logic or persistence.
   ============================================================ */

const $ = (sel) => document.querySelector(sel);

const els = {
  monthLabel: $("#month-label"),
  prev: $("#prev-month"),
  next: $("#next-month"),
  today: $("#today-btn"),
  settingsBtn: $("#settings-btn"),

  totalAmount: $("#total-amount"),
  totalCount: $("#total-count"),
  unpaidAmount: $("#unpaid-amount"),
  unpaidCount: $("#unpaid-count"),
  paidAmount: $("#paid-amount"),
  paidCount: $("#paid-count"),
  progressFill: $("#progress-fill"),
  progressText: $("#progress-text"),

  filters: document.querySelectorAll(".filter-btn"),
  addBtn: $("#add-btn"),
  list: $("#list"),
  empty: $("#empty"),
  emptyAdd: $("#empty-add-btn"),

  modal: $("#modal"),
  modalTitle: $("#modal-title"),
  modalClose: $("#modal-close"),
  cancelBtn: $("#cancel-btn"),
  form: $("#expense-form"),
  fieldId: $("#field-id"),
  fieldName: $("#field-name"),
  fieldAmount: $("#field-amount"),
  fieldDue: $("#field-due"),
  fieldCategory: $("#field-category"),
  fieldCategoryNew: $("#field-category-new"),
  categoryNewWrap: $("#category-new-wrap"),
  fieldRecur: $("#field-recur"),
  fieldRecurMonth: $("#field-recur-month"),
  recurMonthWrap: $("#recur-month-wrap"),
  deleteBtn: $("#delete-btn"),
  stopRecurBtn: $("#stop-recur-btn"),

  recurringBtn: $("#recurring-btn"),
  recurringModal: $("#recurring-modal"),
  recurringClose: $("#recurring-close"),
  recurringList: $("#recurring-list"),

  settingsModal: $("#settings-modal"),
  settingsClose: $("#settings-close"),
  settingsForm: $("#settings-form"),
  fieldCurrency: $("#field-currency"),
  resetBtn: $("#reset-btn"),
  categoryManager: $("#category-manager"),
  exportBtn: $("#export-btn"),
  importBtn: $("#import-btn"),
  importFile: $("#import-file"),
};

/* ---------- Rendering ---------- */

function render() {
  const items = monthItems();
  const total = items.reduce((s, i) => s + i.amount, 0);
  const paid = items.filter((i) => i.paid);
  const unpaid = items.filter((i) => !i.paid);
  const paidAmount = paid.reduce((s, i) => s + i.amount, 0);
  const unpaidAmount = total - paidAmount;

  els.monthLabel.textContent = monthLabel(currentMonth);

  els.totalAmount.textContent = money(total);
  els.totalCount.textContent = `${items.length} item${items.length === 1 ? "" : "s"}`;
  els.unpaidAmount.textContent = money(unpaidAmount);
  els.unpaidCount.textContent = `${unpaid.length} item${unpaid.length === 1 ? "" : "s"}`;
  els.paidAmount.textContent = money(paidAmount);
  els.paidCount.textContent = `${paid.length} item${paid.length === 1 ? "" : "s"}`;

  const pct = total > 0 ? Math.round((paidAmount / total) * 100) : 0;
  els.progressFill.style.width = `${pct}%`;
  els.progressText.textContent = `${pct}% paid`;

  renderList(items);
}

function renderList(items) {
  const visible = items.filter((i) => {
    if (filter === "unpaid") return !i.paid;
    if (filter === "paid") return i.paid;
    return true;
  });

  // Sort: unpaid first, then by due day (items without a due day go last).
  const sorted = [...visible].sort((a, b) => {
    if (a.paid !== b.paid) return a.paid ? 1 : -1;
    const da = a.dueDay || 99;
    const db = b.dueDay || 99;
    return da - db;
  });

  els.list.innerHTML = "";
  els.empty.hidden = items.length > 0;

  if (sorted.length === 0 && items.length > 0) {
    els.list.innerHTML = `<p class="empty" style="padding:24px">No ${filter} expenses.</p>`;
  }

  for (const item of sorted) {
    els.list.appendChild(renderItem(item));
  }
}

function renderItem(item) {
  const row = document.createElement("div");
  row.className = "item" + (item.paid ? " paid-item" : "");
  row.dataset.id = item.id;

  const metaParts = [];
  if (item.category) metaParts.push(`<span class="badge"></span>`);
  if (item.dueDay) metaParts.push(`<span>Due ${ordinal(item.dueDay)}</span>`);
  const recurText = recurDisplay(item);
  if (recurText) {
    metaParts.push(
      item.auto
        ? `<span class="auto-badge">↻ ${recurText} · auto</span>`
        : `<span class="recur-badge">↻ ${recurText}</span>`
    );
  }
  const status = getDueStatus(item);
  if (status) metaParts.push(`<span class="status-badge ${status.kind}">${status.label}</span>`);

  row.innerHTML = `
    <div class="item-main" data-action="edit">
      <div class="item-name"></div>
      <div class="item-meta">${metaParts.join("")}</div>
    </div>
    <div class="item-amount"></div>
    <div class="item-actions">
      <button class="mini-btn" data-action="edit" title="Edit" aria-label="Edit">✎</button>
    </div>
    <label class="switch">
      <input type="checkbox" data-action="toggle" ${item.paid ? "checked" : ""}
             aria-label="Mark ${item.paid ? "unpaid" : "paid"}">
      <span class="slider"></span>
    </label>
  `;

  row.querySelector(".item-name").textContent = item.name;
  row.querySelector(".item-amount").textContent = money(item.amount);
  const badge = row.querySelector(".badge");
  if (badge) badge.textContent = item.category;

  row.addEventListener("click", (e) => {
    const action = e.target.closest("[data-action]")?.dataset.action;
    if (!action) return;
    if (action === "toggle") togglePaid(item.id);
    else if (action === "edit") openEdit(item.id);
  });

  return row;
}

function renderCategoryOptions(selected) {
  const select = els.fieldCategory;
  select.innerHTML = "";
  const opts = [...categories].sort((a, b) => a.localeCompare(b));
  for (const c of opts) {
    const o = document.createElement("option");
    o.value = c;
    o.textContent = c;
    select.appendChild(o);
  }
  const addOpt = document.createElement("option");
  addOpt.value = "__add__";
  addOpt.textContent = "＋ Add new category…";
  select.appendChild(addOpt);

  if (selected && categories.includes(selected)) {
    select.value = selected;
  } else {
    select.value = "";
  }
  els.fieldCategoryNew.value = "";
  els.categoryNewWrap.hidden = true;
}

function renderRecurMonthOptions(month) {
  const select = els.fieldRecurMonth;
  select.innerHTML = "";
  MONTHS.forEach((name, i) => {
    const o = document.createElement("option");
    o.value = String(i + 1);
    o.textContent = name;
    select.appendChild(o);
  });
  select.value = String(month || new Date().getMonth() + 1);
}

function updateRecurMonthVisibility() {
  const recur = els.fieldRecur.value;
  const needsMonth = ["bimonthly", "quarterly", "biannually", "annually"].includes(recur);
  els.recurMonthWrap.hidden = !needsMonth;
}

function renderCategoryManager() {
  const container = els.categoryManager;
  container.innerHTML = "";
  const opts = [...categories].sort((a, b) => a.localeCompare(b));
  for (const c of opts) {
    const row = document.createElement("div");
    row.className = "category-row";
    row.innerHTML = `
      <span class="category-row-name"></span>
      <div class="category-row-actions">
        <button class="mini-btn" data-action="rename-cat" title="Rename" aria-label="Rename">✎</button>
        <button class="mini-btn danger" data-action="delete-cat" title="Delete" aria-label="Delete">✕</button>
      </div>
    `;
    row.querySelector(".category-row-name").textContent = c;
    row.addEventListener("click", (e) => {
      const action = e.target.closest("[data-action]")?.dataset.action;
      if (action === "delete-cat") deleteCategory(c);
      else if (action === "rename-cat") renameCategory(c);
    });
    container.appendChild(row);
  }
}

function renderRecurringList() {
  const rules = collectRecurringRules();
  const container = els.recurringList;
  container.innerHTML = "";

  if (rules.length === 0) {
    container.innerHTML = `<p class="recurring-empty">No recurring bills yet. Set any expense's "Repeats" to start one.</p>`;
    return;
  }

  for (const rule of rules) {
    const row = document.createElement("div");
    row.className = "recurring-rule";
    row.innerHTML = `
      <div class="recurring-rule-main">
        <div class="recurring-rule-name"></div>
        <div class="recurring-rule-meta">
          <span class="recur-badge">↻ ${recurDisplay(rule)}</span>
          ${rule.category ? `<span class="badge"></span>` : ""}
          ${rule.dueDay ? `<span>Due ${ordinal(rule.dueDay)}</span>` : ""}
        </div>
      </div>
      <div class="recurring-rule-amount"></div>
      <div class="recurring-rule-actions">
        <button class="rule-btn" data-action="edit-rule">Edit</button>
        <button class="rule-btn danger" data-action="stop-rule">Stop</button>
      </div>
    `;
    row.querySelector(".recurring-rule-name").textContent = rule.name;
    row.querySelector(".recurring-rule-amount").textContent = money(rule.amount);
    const badge = row.querySelector(".badge");
    if (badge) badge.textContent = rule.category;

    row.addEventListener("click", (e) => {
      const action = e.target.closest("[data-action]")?.dataset.action;
      if (action === "stop-rule") stopRule(rule);
      else if (action === "edit-rule") editRule(rule);
    });

    container.appendChild(row);
  }
}
