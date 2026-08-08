const views = {
  dashboard: document.getElementById("dashboard-view"),
  users: document.getElementById("users-view"),
  audit: document.getElementById("audit-view"),
  analytics: document.getElementById("analytics-view"),
  services: document.getElementById("services-view"),
  haircuts: document.getElementById("haircuts-view"),
  schedule: document.getElementById("schedule-view"),
  settings: document.getElementById("settings-view"),
};

const state = {
  users: { customers: [], barbers: [], receptionists: [], admins: [] },
  services: [],
  haircuts: [],
  haircutDetail: null,
  haircutEditor: null,
  variantEditor: null,
  audit: [],
  activities: [],
  schedule: null,
  scheduleCalendar: null,
  scheduleCalSelected: null,
  currentUser: null,
  profileEditMode: false,
  accountEditor: null,
  serviceEditor: null,
  analytics: null,
  statusChart: null,
  servicesChart: null,
  pagination: {},
};

const CHATBOT_API_KEY = "AQ.Ab8RN6KlvnR-121WQ5uxMLL8cMZN7yWFg8-319S1KXo169ZEBQ";
const CHATBOT_MODEL = "gemini-2.5-flash";

const DEFAULT_PAGE_SIZE = 5;
const PAGE_SIZE_BY_KEY = {
  "activity-list": 5,
  "customers-table": 5,
  "barbers-table": 5,
  "receptionists-table": 5,
  "admins-table": 5,
  "services-table": 5,
  "haircuts-table": 5,
  "audit-list": 5,
};

const navButtons = document.querySelectorAll(".nav button");

function showView(view) {
  navButtons.forEach((b) => b.classList.toggle("active", b.dataset.view === view));
  Object.values(views).forEach((section) => section.setAttribute("hidden", ""));
  if (views[view]) {
    views[view].removeAttribute("hidden");
  }
}

navButtons.forEach((button) => {
  button.addEventListener("click", () => {
    const view = button.dataset.view;
    if (view === "logout") {
      sessionStorage.clear();
      window.location.href = "../login.html";
      return;
    }
    showView(view);
  });
});

document.querySelectorAll("[data-jump]").forEach((button) => {
  button.addEventListener("click", () => {
    const view = button.getAttribute("data-jump");
    if (view) showView(view);
  });
});

function requireAdmin() {
  const rolesRaw = sessionStorage.getItem("roles");
  if (!rolesRaw) {
    window.location.href = "../login.html";
    return false;
  }

  const roles = JSON.parse(rolesRaw).map((role) => String(role).toLowerCase());
  if (!roles.includes("admin")) {
    window.location.href = "../login.html";
    return false;
  }

  return true;
}

function toast(message, type = "info") {
  if (window.PortalUi?.toast) {
    window.PortalUi.toast(message, type);
    return;
  }
  console.log(message);
}

async function confirmAction(message, options = {}) {
  if (window.PortalUi?.confirmDialog) {
    return window.PortalUi.confirmDialog({
      title: options.title || "Confirm",
      message,
      confirmLabel: options.confirmLabel || "Confirm",
      cancelLabel: options.cancelLabel || "Cancel",
      danger: Boolean(options.danger),
    });
  }
  return false;
}

function getStoredUser() {
  try {
    const userRaw = sessionStorage.getItem("user");
    const rolesRaw = sessionStorage.getItem("roles");
    const user = userRaw ? JSON.parse(userRaw) : {};
    const roles = rolesRaw ? JSON.parse(rolesRaw) : [];
    const fullName = user.fullName || user.full_name || user.name || "Admin";
    const email = user.email || "-";
    const role = roles.length ? String(roles[0]) : "Admin";
    const id = user.userID || user.user_id || user.staff_id || "-";
    return { fullName, email, role, id };
  } catch (_) {
    return { fullName: "Admin", email: "-", role: "Admin", id: "-" };
  }
}

function renderProfileChip() {
  state.currentUser = getStoredUser();
  const initialEl = document.getElementById("profile-avatar-initial");
  const nameEl = document.getElementById("profile-avatar-name");
  if (initialEl) {
    initialEl.textContent = String(state.currentUser.fullName || "A").trim().charAt(0).toUpperCase() || "A";
  }
  if (nameEl) {
    nameEl.textContent = state.currentUser.fullName;
  }
}

function renderProfileDialogContent() {
  const content = document.getElementById("profile-dialog-content");
  const saveBtn = document.getElementById("profile-dialog-save");
  const cancelBtn = document.getElementById("profile-dialog-cancel");
  const closeBtn = document.getElementById("profile-dialog-close");
  const editBtn = document.getElementById("profile-dialog-edit");
  if (!content) return;

  const profile = state.currentUser || getStoredUser();
  if (!state.profileEditMode) {
    content.innerHTML = `
      <div class="profile-row"><strong>Name</strong><span>${profile.fullName}</span></div>
      <div class="profile-row"><strong>Email</strong><span>${profile.email}</span></div>
      <div class="profile-row"><strong>Role</strong><span>${profile.role}</span></div>
      <div class="profile-row"><strong>ID</strong><span>${profile.id}</span></div>
    `;
    if (saveBtn) saveBtn.hidden = true;
    if (cancelBtn) cancelBtn.hidden = true;
    if (closeBtn) closeBtn.hidden = false;
    if (editBtn) editBtn.hidden = false;
    return;
  }

  content.innerHTML = `
    <label>Name
      <input class="input" id="profile-edit-name" value="${profile.fullName}" />
    </label>
    <label>Email
      <input class="input" id="profile-edit-email" value="${profile.email}" />
    </label>
    <div class="profile-row"><strong>Role</strong><span>${profile.role}</span></div>
    <div class="profile-row"><strong>ID</strong><span>${profile.id}</span></div>
  `;
  if (saveBtn) saveBtn.hidden = false;
  if (cancelBtn) cancelBtn.hidden = false;
  if (closeBtn) closeBtn.hidden = true;
  if (editBtn) editBtn.hidden = true;
}

function openProfileDialog() {
  const dialog = document.getElementById("profile-dialog");
  if (!(dialog instanceof HTMLDialogElement)) return;
  state.profileEditMode = false;
  renderProfileDialogContent();
  dialog.showModal();
}

async function saveProfileEdits() {
  const nameInput = document.getElementById("profile-edit-name");
  const emailInput = document.getElementById("profile-edit-email");
  if (!(nameInput instanceof HTMLInputElement) || !(emailInput instanceof HTMLInputElement)) return;

  const fullName = nameInput.value.trim();
  const email = emailInput.value.trim();
  if (!fullName || !email) {
    toast("Name and email are required.");
    return;
  }

  const profile = state.currentUser || getStoredUser();
  try {
    const response = await fetch(resolveApiUrl("staff_profile.php"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        action: "updateProfile",
        staffID: Number(profile.id),
        fullName,
        email,
        role: String(profile.role || "admin").toLowerCase(),
      }),
    });

    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.error || "Profile update failed");
    }

    if (data?.user) {
      sessionStorage.setItem("user", JSON.stringify(data.user));
      if (Array.isArray(data.user.roles)) {
        sessionStorage.setItem("roles", JSON.stringify(data.user.roles));
      }
    }

    renderProfileChip();
    state.profileEditMode = false;
    renderProfileDialogContent();
    toast("Profile updated.", "success");
  } catch (error) {
    toast(error.message || "Profile update failed", "error");
  }
}

function setLastUpdated() {
  const el = document.getElementById("last-updated");
  if (el) el.textContent = new Date().toLocaleString();
}

function toCsv(rows) {
  if (!rows.length) return "";
  const keys = Object.keys(rows[0]);
  const esc = (v) => {
    const text = String(v ?? "");
    if (text.includes(",") || text.includes("\"") || text.includes("\n")) {
      return `"${text.replaceAll("\"", "\"\"")}"`;
    }
    return text;
  };
  const lines = [keys.join(",")];
  rows.forEach((row) => lines.push(keys.map((k) => esc(row[k])).join(",")));
  return lines.join("\n");
}

function downloadCsv(fileName, rows) {
  const csv = toCsv(rows);
  const blob = new Blob([csv], { type: "text/csv" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = fileName;
  a.click();
  URL.revokeObjectURL(url);
}

function renderStats(stats) {
  const grid = document.getElementById("stats-grid");
  if (!grid) return;
  grid.innerHTML = "";
  if (!stats?.length) {
    grid.innerHTML = "<div class=\"card empty\">No stats available.</div>";
    return;
  }
  stats.forEach((stat) => {
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `
      <h3>${stat.title}</h3>
      <div class="value">${stat.value}</div>
      <div class="meta ${stat.changeType || ""}">${stat.change || ""}</div>
    `;
    grid.appendChild(card);
  });
}

function getPageSize(key) {
  return PAGE_SIZE_BY_KEY[key] || DEFAULT_PAGE_SIZE;
}

function getVisiblePages(currentPage, totalPages, maxVisible = 5) {
  if (totalPages <= maxVisible) {
    return Array.from({ length: totalPages }, (_, index) => index + 1);
  }

  const half = Math.floor(maxVisible / 2);
  let start = currentPage - half;
  let end = currentPage + half;

  if (maxVisible % 2 === 0) {
    end -= 1;
  }

  if (start < 1) {
    end += 1 - start;
    start = 1;
  }

  if (end > totalPages) {
    start -= end - totalPages;
    end = totalPages;
  }

  if (start < 1) {
    start = 1;
  }

  return Array.from({ length: end - start + 1 }, (_, index) => start + index);
}

function paginateRows(key, rows) {
  const pageSize = getPageSize(key);
  const totalPages = Math.max(1, Math.ceil(rows.length / pageSize));
  const stored = Number(state.pagination[key] || 1);
  const currentPage = Math.max(1, Math.min(stored, totalPages));
  state.pagination[key] = currentPage;

  const start = (currentPage - 1) * pageSize;
  const items = rows.slice(start, start + pageSize);
  return { items, currentPage, totalPages };
}

function resetPagination(keys) {
  keys.forEach((key) => {
    state.pagination[key] = 1;
  });
}

function paginationMarkup(key, currentPage, totalPages) {
  if (totalPages <= 1) {
    return "";
  }

  const pageButtons = getVisiblePages(currentPage, totalPages)
    .map((page) => `
      <button
        class="btn secondary pager-btn${page === currentPage ? " is-active" : ""}"
        data-page-key="${key}"
        data-page="${page}"
        ${page === currentPage ? "disabled" : ""}
      >${page}</button>
    `)
    .join("");

  return `
    <div class="pager">
      <button class="btn secondary pager-btn" data-page-key="${key}" data-page="${currentPage - 1}" ${currentPage <= 1 ? "disabled" : ""}>Previous</button>
      <div class="pager-numbers">${pageButtons}</div>
      <button class="btn secondary pager-btn" data-page-key="${key}" data-page="${currentPage + 1}" ${currentPage >= totalPages ? "disabled" : ""}>Next</button>
    </div>
  `;
}

function rerenderByPaginationKey(key) {
  if (["customers-table", "barbers-table", "receptionists-table", "admins-table"].includes(key)) {
    renderUserTables();
    return;
  }
  if (key === "services-table") {
    renderServices();
    return;
  }
  if (key === "haircuts-table") {
    renderHaircuts();
    return;
  }
  if (key === "audit-list") {
    renderAudit();
    return;
  }
  if (key === "activity-list") {
    renderActivities(state.activities || []);
  }
}

function renderActivities(activities) {
  const list = document.getElementById("activity-list");
  const filterValue = document.getElementById("activity-category-filter")?.value || "all";
  if (!list) return;
  list.innerHTML = "";
  if (!activities?.length) {
    list.innerHTML = "<div class=\"card empty\">No recent activity.</div>";
    return;
  }

  const categorize = (titleText) => {
    const text = String(titleText || "").toLowerCase();
    if (text.includes("appointment")) return "appointments";
    if (text.includes("user") || text.includes("customer") || text.includes("barber") || text.includes("receptionist") || text.includes("admin")) return "users";
    if (text.includes("service")) return "services";
    return "system";
  };

  const categories = {
    appointments: "Appointments",
    users: "Users",
    services: "Services",
    system: "System",
  };

  const filtered = activities.filter((activity) => {
    if (filterValue === "all") return true;
    return categorize(activity.title) === filterValue;
  });

  if (!filtered.length) {
    list.innerHTML = "<div class=\"card empty\">No activity for this category.</div>";
    return;
  }

  const paged = paginateRows("activity-list", filtered);

  const grouped = { appointments: [], users: [], services: [], system: [] };
  paged.items.forEach((activity) => {
    const bucket = categorize(activity.title);
    grouped[bucket].push(activity);
  });

  Object.entries(categories).forEach(([key, label]) => {
    if (!grouped[key].length) return;
    const wrapper = document.createElement("div");
    wrapper.className = "group-section";
    wrapper.innerHTML = `<h4 class="group-title">${label}</h4>`;

    grouped[key].forEach((activity) => {
      const item = document.createElement("div");
      item.className = "card gradient list-item";
      item.innerHTML = `
        <div class="icon-box">${activity.icon || "AI"}</div>
        <div>
          <h4>${activity.title || "Activity"}</h4>
          <p>${activity.description || ""}</p>
        </div>
        <div class="time">${activity.time || ""}</div>
      `;
      wrapper.appendChild(item);
    });
    list.appendChild(wrapper);
  });

  if (!list.innerHTML.trim()) {
    list.innerHTML = "<div class=\"card empty\">No activity for this category.</div>";
    return;
  }

  const pager = paginationMarkup("activity-list", paged.currentPage, paged.totalPages);
  if (pager) {
    list.insertAdjacentHTML("beforeend", pager);
  }
}

async function loadAiStatus() {
  const panel = document.getElementById("ai-status-panel");
  const badge = document.getElementById("ai-health-badge");
  if (!panel || !badge) return;

  try {
    const response = await fetch(resolveApiUrl("ai_status.php"));
    if (!response.ok) throw new Error("Unable to fetch AI status");
    const data = await response.json();

    const scanEnabled = Boolean(data?.scan?.enabled);
    const tryonConfigured = Boolean(data?.tryon?.configured);
    const probeCode = data?.tryon?.probe?.httpCode ?? "-";

    badge.textContent = scanEnabled ? "AI: Online" : "AI: Limited";
    badge.className = `badge ${scanEnabled ? "status-ok" : "status-warn"}`;

    panel.innerHTML = `
      <div class="card gradient">
        <h4>Face Scan AI</h4>
        <p class="meta">Provider: ${data?.scan?.provider || "-"} • Model: ${data?.scan?.model || "-"}</p>
        <div class="tag ${scanEnabled ? "success" : "warning"}">${scanEnabled ? "Enabled" : "Disabled"}</div>
      </div>
      <div class="card gradient">
        <h4>Try-On AI</h4>
        <p class="meta">Provider: ${data?.tryon?.provider || "-"} • Probe: ${probeCode}</p>
        <div class="tag ${tryonConfigured ? "success" : "warning"}">${tryonConfigured ? "Configured" : "Not Configured"}</div>
      </div>
    `;
  } catch (_) {
    badge.textContent = "AI: Unavailable";
    badge.className = "badge status-warn";
    panel.innerHTML = "<div class=\"empty\">AI status endpoint is unavailable.</div>";
  }
}

async function loadDashboard() {
  try {
    const response = await fetch(resolveApiUrl("admin_dashboard.php"));
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    state.activities = data.activities ?? [];
    renderStats(data.stats ?? []);
    renderActivities(state.activities);
  } catch (_) {
    state.activities = [];
    renderStats([]);
    renderActivities([]);
  }
}

function renderTable(containerId, columns, rows) {
  const container = document.getElementById(containerId);
  if (!container) return;
  if (!rows?.length || !columns.length) {
    container.innerHTML = "<div class=\"empty\">No records found.</div>";
    return;
  }

  const paged = paginateRows(containerId, rows);

  const columnTemplate = `repeat(${columns.length}, minmax(0, 1fr))`;
  const header = `
    <div class="table-row table-header" style="grid-template-columns:${columnTemplate};">
      ${columns.map((c) => `<div>${c.label}</div>`).join("")}
    </div>
  `;
  const body = paged.items
    .map(
      (row) => `
      <div class="table-row" style="grid-template-columns:${columnTemplate};">
        ${columns.map((c) => `<div>${row[c.key] ?? "-"}</div>`).join("")}
      </div>
    `
    )
    .join("");
  container.innerHTML = header + body + paginationMarkup(containerId, paged.currentPage, paged.totalPages);
}

function filterRows(rows, query, fields) {
  const text = query.trim().toLowerCase();
  if (!text) return rows;
  return rows.filter((row) =>
    fields.some((field) => String(row[field] ?? "").toLowerCase().includes(text))
  );
}

function renderUserTables() {
  const query = document.getElementById("users-search")?.value || "";
  const roleFilter = document.getElementById("users-role-filter")?.value || "all";

  const removeGhostRows = (rows) =>
    rows.filter((row) => String(row.full_name || row.email || "").trim() !== "");

  const data = {
    customers: removeGhostRows(filterRows(state.users.customers, query, ["full_name", "email", "phone"])),
    barbers: removeGhostRows(filterRows(state.users.barbers, query, ["full_name", "email", "specialty"])),
    receptionists: removeGhostRows(filterRows(state.users.receptionists, query, ["full_name", "email", "role"])),
    admins: removeGhostRows(filterRows(state.users.admins, query, ["full_name", "email", "role"])),
  };

  renderTable(
    "customers-table",
    [
      { key: "full_name", label: "Name" },
      { key: "email", label: "Email" },
      { key: "phone", label: "Phone" },
      { key: "role", label: "Role" },
      { key: "is_active", label: "Active" },
      { key: "created_at", label: "Created" },
      { key: "actions", label: "Actions" },
    ],
    (roleFilter === "all" || roleFilter === "customers"
      ? data.customers.map((row) => ({
          ...row,
          actions: `<button class="btn btn-edit" data-type="customer" data-id="${row.user_id}">Edit</button> <button class="btn secondary btn-delete" data-type="customer" data-id="${row.user_id}">Delete</button>`,
        }))
      : [])
  );

  renderTable(
    "barbers-table",
    [
      { key: "full_name", label: "Name" },
      { key: "queue_label", label: "Queue" },
      { key: "specialty", label: "Specialty" },
      { key: "rating", label: "Rating" },
      { key: "role", label: "Role" },
      { key: "is_active", label: "Active" },
      { key: "created_at", label: "Created" },
      { key: "actions", label: "Actions" },
    ],
    (roleFilter === "all" || roleFilter === "barbers"
      ? data.barbers.map((row) => ({
          ...row,
          queue_label: String(row.barber_channel || "").toLowerCase() === "walk_in" ? "Regular" : "Exclusive",
          actions: `<button class="btn btn-edit" data-type="barber" data-id="${row.barber_id}">Edit</button> <button class="btn secondary btn-delete" data-type="barber" data-id="${row.barber_id}">Delete</button>`,
        }))
      : [])
  );

  renderTable(
    "receptionists-table",
    [
      { key: "full_name", label: "Name" },
      { key: "email", label: "Email" },
      { key: "role", label: "Role" },
      { key: "is_active", label: "Active" },
      { key: "created_at", label: "Created" },
      { key: "actions", label: "Actions" },
    ],
    (roleFilter === "all" || roleFilter === "receptionists"
      ? data.receptionists.map((row) => ({
          ...row,
          actions: `<button class="btn btn-edit" data-type="staff" data-id="${row.staff_id}">Edit</button> <button class="btn secondary btn-delete" data-type="staff" data-id="${row.staff_id}">Delete</button>`,
        }))
      : [])
  );

  renderTable(
    "admins-table",
    [
      { key: "full_name", label: "Name" },
      { key: "email", label: "Email" },
      { key: "role", label: "Role" },
      { key: "is_active", label: "Active" },
      { key: "created_at", label: "Created" },
      { key: "actions", label: "Actions" },
    ],
    (roleFilter === "all" || roleFilter === "admins"
      ? data.admins.map((row) => ({
          ...row,
          actions: `<button class="btn btn-edit" data-type="staff" data-id="${row.staff_id}">Edit</button> <button class="btn secondary btn-delete" data-type="staff" data-id="${row.staff_id}">Delete</button>`,
        }))
      : [])
  );
}

async function loadUsers() {
  try {
    const response = await fetch(resolveApiUrl("admin_users.php"));
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    state.users = {
      customers: data.customers ?? [],
      barbers: data.barbers ?? [],
      receptionists: data.receptionists ?? [],
      admins: data.admins ?? [],
    };
  } catch (_) {
    state.users = { customers: [], barbers: [], receptionists: [], admins: [] };
  }
  renderUserTables();
}

async function updateUser(payload) {
  const response = await fetch(resolveApiUrl("admin_users.php"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    const data = await parseJsonResponse(response);
    throw new Error(data.error || "Update failed");
  }
}

async function assignPortalRole(payload) {
  const response = await fetch(resolveApiUrl("admin_users.php"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    const data = await parseJsonResponse(response);
    throw new Error(data.error || "Role update failed");
  }
}

function findBarberRoleForEmail(email) {
  const normalized = String(email || "").trim().toLowerCase();
  if (!normalized) {
    return false;
  }
  return (state.users.barbers || []).some(
    (row) => String(row.email || "").trim().toLowerCase() === normalized && Number(row.is_active) === 1,
  );
}

function findPortalRoleForEmail(email) {
  const normalized = String(email || "").trim().toLowerCase();
  if (!normalized) {
    return "";
  }

  const admin = state.users.admins.find((row) => String(row.email || "").toLowerCase() === normalized);
  if (admin) {
    return "Admin";
  }

  const receptionist = state.users.receptionists.find(
    (row) => String(row.email || "").toLowerCase() === normalized
  );
  if (receptionist) {
    return "Receptionist";
  }

  return "";
}

function getUserRowForEdit(type, id) {
  if (type === "customer") {
    return state.users.customers.find((row) => Number(row.user_id) === Number(id)) || null;
  }
  if (type === "barber") {
    return state.users.barbers.find((row) => Number(row.barber_id) === Number(id)) || null;
  }
  if (type === "staff") {
    const allStaff = [...state.users.receptionists, ...state.users.admins];
    return allStaff.find((row) => Number(row.staff_id) === Number(id)) || null;
  }
  return null;
}

function openAccountCreateDialog() {
  const dialog = document.getElementById("account-editor-dialog");
  const title = document.getElementById("account-editor-title");
  const form = document.getElementById("account-editor-form");
  if (!(dialog instanceof HTMLDialogElement) || !title || !form) return;

  state.accountEditor = { mode: "create" };
  title.textContent = "Add account";
  form.innerHTML = `
    <label>Account type
      <select class="select" id="ae-create-kind">
        <option value="customer">Customer (mobile app)</option>
        <option value="barber">Barber</option>
        <option value="staff">Staff (Admin / Receptionist portal)</option>
      </select>
    </label>
    <label>Full name
      <input class="input" id="ae-fullName" placeholder="Full name" />
    </label>
    <label>Email
      <input class="input" id="ae-email" type="email" placeholder="email@example.com" />
    </label>
    <label>Password (min 8 characters)
      <input class="input" id="ae-password" type="password" autocomplete="new-password" />
    </label>
    <label id="ae-phone-wrap">Phone (optional)
      <input class="input" id="ae-phone" placeholder="+63..." />
    </label>
    <label id="ae-barber-fields" style="display:none;">Specialty
      <input class="input" id="ae-specialty" placeholder="General" />
    </label>
    <label id="ae-barber-years-wrap" style="display:none;">Years experience
      <input class="input" id="ae-years" type="number" min="0" value="1" />
    </label>
    <label id="ae-barber-channel-wrap" style="display:none;">Barber queue
      <select class="select" id="ae-barber-channel">
        <option value="appointment">Exclusive (appointments)</option>
        <option value="walk_in">Regular (walk-in / kiosk)</option>
      </select>
    </label>
    <label id="ae-staff-role-wrap" style="display:none;">Portal role
      <select class="select" id="ae-create-staff-role">
        <option value="Receptionist">Receptionist</option>
        <option value="Admin">Admin</option>
      </select>
    </label>
  `;

  const kindEl = document.getElementById("ae-create-kind");
  const syncCreateFields = () => {
    const kind = kindEl?.value || "customer";
    const phoneWrap = document.getElementById("ae-phone-wrap");
    const bf = document.getElementById("ae-barber-fields");
    const by = document.getElementById("ae-barber-years-wrap");
    const bc = document.getElementById("ae-barber-channel-wrap");
    const sr = document.getElementById("ae-staff-role-wrap");
    if (phoneWrap) phoneWrap.style.display = kind === "customer" ? "" : "none";
    if (bf) bf.style.display = kind === "barber" ? "" : "none";
    if (by) by.style.display = kind === "barber" ? "" : "none";
    if (bc) bc.style.display = kind === "barber" ? "" : "none";
    if (sr) sr.style.display = kind === "staff" ? "" : "none";
  };
  kindEl?.addEventListener("change", syncCreateFields);
  syncCreateFields();

  dialog.showModal();
}

function openAccountEditor(type, id) {
  const dialog = document.getElementById("account-editor-dialog");
  const title = document.getElementById("account-editor-title");
  const form = document.getElementById("account-editor-form");
  if (!(dialog instanceof HTMLDialogElement) || !title || !form) return;

  const row = getUserRowForEdit(type, id);
  if (!row) {
    toast("Record not found.");
    return;
  }

  state.accountEditor = { mode: "edit", type, id: Number(id) };

  if (type === "customer") {
    const appRole = findBarberRoleForEmail(row.email ?? "") ? "barber" : "customer";
    title.textContent = "Edit Customer";
    form.innerHTML = `
      <label>Full Name
        <input class="input" id="ae-fullName" value="${row.full_name ?? ""}" />
      </label>
      <label>Email
        <input class="input" id="ae-email" value="${row.email ?? ""}" />
      </label>
      <label>Phone
        <input class="input" id="ae-phone" value="${row.phone ?? ""}" />
      </label>
      <label>App Role
        <select class="select" id="ae-app-role">
          <option value="customer" ${appRole === "customer" ? "selected" : ""}>Customer</option>
          <option value="barber" ${appRole === "barber" ? "selected" : ""}>Barber</option>
        </select>
      </label>
      <label>Active
        <select class="select" id="ae-active">
          <option value="1" ${Number(row.is_active) === 1 ? "selected" : ""}>Yes</option>
          <option value="0" ${Number(row.is_active) === 0 ? "selected" : ""}>No</option>
        </select>
      </label>
    `;
  }

  if (type === "barber") {
    title.textContent = "Edit Barber";
    form.innerHTML = `
      <label>Full Name
        <input class="input" id="ae-fullName" value="${row.full_name ?? ""}" />
      </label>
      <label>Email
        <input class="input" id="ae-email" value="${row.email ?? ""}" />
      </label>
      <label>Specialty
        <input class="input" id="ae-specialty" value="${row.specialty ?? ""}" />
      </label>
      <label>Years Experience
        <input class="input" id="ae-years" type="number" min="0" value="${Number(row.years_experience ?? 0)}" />
      </label>
      <label>Rating
        <input class="input" id="ae-rating" type="number" min="0" max="5" step="0.1" value="${Number(row.rating ?? 5)}" />
      </label>
      <label>Barber queue
        <select class="select" id="ae-barber-channel">
          <option value="appointment" ${String(row.barber_channel || "appointment").toLowerCase() !== "walk_in" ? "selected" : ""}>Exclusive (appointments)</option>
          <option value="walk_in" ${String(row.barber_channel || "").toLowerCase() === "walk_in" ? "selected" : ""}>Regular (walk-in / kiosk)</option>
        </select>
      </label>
      <label>Role
        <input class="input" value="Barber" disabled />
      </label>
      <label>Active
        <select class="select" id="ae-active">
          <option value="1" ${Number(row.is_active) === 1 ? "selected" : ""}>Yes</option>
          <option value="0" ${Number(row.is_active) === 0 ? "selected" : ""}>No</option>
        </select>
      </label>
    `;
  }

  if (type === "staff") {
    title.textContent = "Edit Staff";
    form.innerHTML = `
      <label>Full Name
        <input class="input" id="ae-fullName" value="${row.full_name ?? ""}" />
      </label>
      <label>Email
        <input class="input" id="ae-email" value="${row.email ?? ""}" />
      </label>
      <label>Role
        <select class="select" id="ae-role">
          <option value="Receptionist" ${String(row.role).toLowerCase() === "receptionist" ? "selected" : ""}>Receptionist</option>
          <option value="Admin" ${String(row.role).toLowerCase() === "admin" ? "selected" : ""}>Admin</option>
        </select>
      </label>
      <label>Active
        <select class="select" id="ae-active">
          <option value="1" ${Number(row.is_active) === 1 ? "selected" : ""}>Yes</option>
          <option value="0" ${Number(row.is_active) === 0 ? "selected" : ""}>No</option>
        </select>
      </label>
    `;
  }

  dialog.showModal();
}

async function saveAccountEditor() {
  const dialog = document.getElementById("account-editor-dialog");
  if (!(dialog instanceof HTMLDialogElement)) return;

  if (state.accountEditor?.mode === "create") {
    const kind = document.getElementById("ae-create-kind")?.value || "customer";
    const fullName = document.getElementById("ae-fullName")?.value?.trim() || "";
    const email = document.getElementById("ae-email")?.value?.trim() || "";
    const password = document.getElementById("ae-password")?.value || "";
    if (!fullName || !email || password.length < 8) {
      toast("Name, email, and password (8+ characters) are required.");
      return;
    }
    try {
      const payload = {
        action: "create",
        accountKind: kind,
        fullName,
        email,
        password,
      };
      if (kind === "customer") {
        payload.phone = document.getElementById("ae-phone")?.value?.trim() || "";
      }
      if (kind === "barber") {
        payload.specialty = document.getElementById("ae-specialty")?.value?.trim() || "General";
        payload.yearsExperience = Number(document.getElementById("ae-years")?.value ?? 1);
        payload.barberChannel = document.getElementById("ae-barber-channel")?.value || "appointment";
      }
      if (kind === "staff") {
        payload.role = document.getElementById("ae-create-staff-role")?.value || "Receptionist";
      }
      await updateUser(payload);
      toast("Account created.");
      await loadUsers();
      dialog.close();
      state.accountEditor = null;
    } catch (error) {
      toast(error.message || "Create failed");
    }
    return;
  }

  if (!state.accountEditor) return;

  const { type, id } = state.accountEditor;
  const fullName = document.getElementById("ae-fullName")?.value?.trim() || "";
  const email = document.getElementById("ae-email")?.value?.trim() || "";
  const activeValue = Number(document.getElementById("ae-active")?.value ?? 1);

  if (!fullName || !email) {
    toast("Name and email are required.");
    return;
  }

  try {
    if (type === "customer") {
      const phone = document.getElementById("ae-phone")?.value?.trim() || "";
      const appRole = document.getElementById("ae-app-role")?.value || "customer";
      await updateUser({
        action: "update",
        type,
        id,
        fullName,
        email,
        phone,
        role: "customer",
        appRole,
        isActive: activeValue,
      });
    }

    if (type === "barber") {
      const specialty = document.getElementById("ae-specialty")?.value?.trim() || "";
      const yearsExperience = Number(document.getElementById("ae-years")?.value ?? 0);
      const rating = Number(document.getElementById("ae-rating")?.value ?? 5);
      const barberChannel = document.getElementById("ae-barber-channel")?.value || "appointment";
      await updateUser({
        action: "update",
        type,
        id,
        fullName,
        email,
        specialty,
        yearsExperience,
        rating,
        barberChannel,
        role: "barber",
        isActive: activeValue,
      });
    }

    if (type === "staff") {
      const role = document.getElementById("ae-role")?.value || "Receptionist";
      await updateUser({ action: "update", type, id, fullName, email, role, isActive: activeValue });
    }

    toast("Record updated successfully.");
    await loadUsers();
    dialog.close();
    state.accountEditor = null;
  } catch (error) {
    toast(error.message || "Update failed");
  }
}

async function deleteAccount(type, id) {
  const label = type === "customer" ? "customer" : type === "barber" ? "barber" : "staff account";
  const ok = await confirmAction(`Delete this ${label}? This will deactivate the account.`, {
    title: "Deactivate account",
    confirmLabel: "Deactivate",
    danger: true,
  });
  if (!ok) {
    return;
  }

  try {
    await updateUser({ action: "delete", type, id });
    toast("Account deactivated.");
    await loadUsers();
  } catch (error) {
    toast(error.message || "Delete failed");
  }
}

function formatServiceChannel(channel) {
  const value = String(channel || "appointment").toLowerCase();
  if (value === "walk_in" || value === "walkin" || value === "regular") {
    return "Regular (kiosk) — ₱100";
  }
  return "Exclusive (appointments) — ₱500";
}

function openServiceEditor(existing) {
  const dialog = document.getElementById("service-editor-dialog");
  const title = document.getElementById("service-editor-title");
  const form = document.getElementById("service-editor-form");
  if (!(dialog instanceof HTMLDialogElement) || !title || !form) return;

  const isEdit = Boolean(existing);
  state.serviceEditor = { mode: isEdit ? "edit" : "create", serviceId: existing?.service_id ?? null };
  title.textContent = isEdit ? "Edit service" : "Add service";

  const channel = existing?.service_channel ?? "appointment";
  const active = existing?.is_active === false || existing?.is_active === "f" ? "0" : "1";

  form.innerHTML = `
    <label>Service name
      <input class="input" id="se-name" value="${existing?.service_name ?? ""}" />
    </label>
    <label>Description
      <input class="input" id="se-description" value="${existing?.description ?? ""}" />
    </label>
    <label>Duration (minutes)
      <input class="input" id="se-duration" type="number" min="1" value="${Number(existing?.base_duration ?? 30)}" />
    </label>
    <label>Price (PHP)
      <input class="input" id="se-price" type="number" min="0" step="0.01"
        value="${Number(existing?.base_price ?? (channel === "walk_in" ? 100 : 500))}" />
    </label>
    <label>Category
      <select class="select" id="se-category">
        <option value="Haircut" ${(existing?.category ?? "Haircut") === "Haircut" ? "selected" : ""}>Haircut</option>
        <option value="Styling" ${existing?.category === "Styling" ? "selected" : ""}>Styling</option>
        <option value="Beard" ${existing?.category === "Beard" ? "selected" : ""}>Beard</option>
        <option value="Treatment" ${existing?.category === "Treatment" ? "selected" : ""}>Treatment</option>
      </select>
    </label>
    <label>Channel
      <select class="select" id="se-channel">
        <option value="walk_in" ${channel === "walk_in" ? "selected" : ""}>Regular (kiosk) — walk-in</option>
        <option value="appointment" ${channel !== "walk_in" ? "selected" : ""}>Exclusive (appointments)</option>
      </select>
    </label>
    <label>Active
      <select class="select" id="se-active">
        <option value="1" ${active === "1" ? "selected" : ""}>Yes</option>
        <option value="0" ${active === "0" ? "selected" : ""}>No</option>
      </select>
    </label>
  `;

  dialog.showModal();
}

async function saveServiceEditor() {
  const dialog = document.getElementById("service-editor-dialog");
  if (!(dialog instanceof HTMLDialogElement) || !state.serviceEditor) return;

  const payload = {
    serviceName: document.getElementById("se-name")?.value?.trim() || "",
    description: document.getElementById("se-description")?.value?.trim() || "",
    baseDuration: Number(document.getElementById("se-duration")?.value ?? 30),
    basePrice: Number(document.getElementById("se-price")?.value ?? 0),
    category: document.getElementById("se-category")?.value || "Haircut",
    serviceChannel: document.getElementById("se-channel")?.value || "appointment",
    isActive: Number(document.getElementById("se-active")?.value ?? 1) !== 0,
  };

  if (!payload.serviceName || payload.baseDuration <= 0) {
    toast("Service name and duration are required.");
    return;
  }

  try {
    if (state.serviceEditor.mode === "create") {
      await saveService("create", payload);
      toast("Service created.");
    } else {
      await saveService("update", { serviceID: state.serviceEditor.serviceId, ...payload });
      toast("Service updated.");
    }
    await loadServices();
    dialog.close();
    state.serviceEditor = null;
  } catch (error) {
    toast(error.message || "Save failed");
  }
}

async function saveService(action, payload) {
  const response = await fetch(resolveApiUrl("admin_services.php"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action, ...payload }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.error || "Save failed");
  }
}

function renderServices() {
  const query = document.getElementById("services-search")?.value || "";
  const normalized = (state.services || []).map((r) => ({
    ...r,
    service_name: r.service_name || r.service_code || "(Unnamed Service)",
    category: r.category || r.service_category || "(Uncategorized)",
    channel_label: formatServiceChannel(r.service_channel),
    base_price: `₱${Number(r.base_price ?? 0).toFixed(2)}`,
    is_active: r.is_active === false || r.is_active === "f" ? "No" : "Yes",
  }));

  const rows = filterRows(normalized, query, ["service_name", "category", "description", "channel_label"]);
  renderTable(
    "services-table",
    [
      { key: "service_name", label: "Service" },
      { key: "channel_label", label: "Channel" },
      { key: "category", label: "Category" },
      { key: "base_duration", label: "Duration (min)" },
      { key: "base_price", label: "Price" },
      { key: "is_active", label: "Active" },
      { key: "actions", label: "Actions" },
    ],
    rows.map((row) => ({
      ...row,
      actions: `
        <button class="btn secondary btn-service" data-id="${row.service_id}" type="button">Edit</button>
        <button class="btn secondary btn-service-delete" data-id="${row.service_id}" type="button">Delete</button>
      `,
    })),
  );
}

async function loadServices() {
  try {
    const response = await fetch(resolveApiUrl("admin_services.php"));
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    state.services = data.services ?? [];
  } catch (_) {
    state.services = [];
  }
  renderServices();
}

function overlayPreviewUrl(assetPath) {
  if (!assetPath) return "";
  const clean = String(assetPath).replace(/^assets\//, "");
  return `../../mobile-app/assets/${clean}`;
}

async function loadHaircuts() {
  try {
    const response = await fetch(resolveApiUrl("admin_hairstyles.php"));
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    state.haircuts = data.hairstyles ?? [];
  } catch (_) {
    state.haircuts = [];
  }
  renderHaircuts();
}

function renderHaircuts() {
  const query = document.getElementById("haircuts-search")?.value || "";
  const normalized = (state.haircuts || []).map((row) => ({
    ...row,
    overlay_status: row.has_overlay_assets ? "Ready" : "Missing PNGs",
    is_active: row.is_active === false || row.is_active === "f" ? "No" : "Yes",
  }));
  const rows = filterRows(normalized, query, ["style_name", "style_code", "description", "gender"]);
  renderTable(
    "haircuts-table",
    [
      { key: "style_name", label: "Name" },
      { key: "style_code", label: "Code" },
      { key: "gender", label: "Gender" },
      { key: "variant_count", label: "Variants" },
      { key: "overlay_status", label: "Overlays" },
      { key: "is_active", label: "Active" },
      { key: "actions", label: "Actions" },
    ],
    rows.map((row) => ({
      ...row,
      actions: `
        <button class="btn secondary btn-haircut" data-id="${row.hairstyle_id}" type="button">Manage</button>
        <button class="btn secondary btn-haircut-delete" data-id="${row.hairstyle_id}" type="button">Delete</button>
      `,
    })),
  );
}

async function fetchHaircutDetail(hairstyleId) {
  const response = await fetch(resolveApiUrl("admin_hairstyles.php"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action: "get", hairstyleID: hairstyleId }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.error || "Failed to load haircut");
  }
  return data;
}

async function saveHaircut(action, payload) {
  const response = await fetch(resolveApiUrl("admin_hairstyles.php"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action, ...payload }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.error || "Save failed");
  }
  return data;
}

async function saveVariant(action, payload) {
  const response = await fetch(resolveApiUrl("admin_hairstyles.php"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action, ...payload }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.error || "Variant save failed");
  }
  return data;
}

async function uploadHaircutOverlay(hairstyleId, view, file, overlayFolder) {
  const form = new FormData();
  form.append("action", "uploadOverlay");
  form.append("hairstyleID", String(hairstyleId));
  form.append("view", view);
  form.append("file", file);
  if (overlayFolder) {
    form.append("overlayFolder", overlayFolder);
  }
  const response = await fetch(resolveApiUrl("admin_hairstyles.php"), {
    method: "POST",
    body: form,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.error || "Upload failed");
  }
  return data;
}

function renderHaircutVariantsList() {
  const list = document.getElementById("haircut-variants-list");
  if (!list || !state.haircutDetail) return;
  const variants = state.haircutDetail.variants ?? [];
  if (!variants.length) {
    list.innerHTML = '<div class="card empty">No variants yet.</div>';
    return;
  }
  list.innerHTML = variants
    .map(
      (variant) => `
        <div class="card" style="margin-bottom: 8px;">
          <div class="row-wrap" style="justify-content: space-between;">
            <div>
              <strong>${variant.face_shape}</strong> · ${variant.hair_texture}
              <p class="meta">${variant.estimated_minutes} min · confidence ${variant.confidence_score}</p>
            </div>
            <div class="row-wrap">
              <button class="btn secondary btn-variant-edit" data-id="${variant.variant_id}" type="button">Edit</button>
              <button class="btn secondary btn-variant-delete" data-id="${variant.variant_id}" type="button">Delete</button>
            </div>
          </div>
        </div>
      `,
    )
    .join("");
}

function renderHaircutOverlayUploads(hairstyle) {
  const section = document.getElementById("haircut-overlay-section");
  const container = document.getElementById("haircut-overlay-uploads");
  if (!section || !container || !hairstyle) return;

  section.removeAttribute("hidden");
  const folder = hairstyle.overlay_folder || "";
  const views = [
    { key: "front", label: "Front", url: hairstyle.front_view_url },
    { key: "left", label: "Left", url: hairstyle.side_view_url },
    { key: "right", label: "Right", url: hairstyle.back_view_url },
  ];

  container.innerHTML = `
    <label>Overlay folder slug
      <input class="input" id="hc-overlay-folder" value="${folder}" placeholder="e.g. wavy_mod_cut" />
    </label>
    ${views
      .map(
        (view) => `
          <label>${view.label} PNG
            <input class="input" type="file" accept="image/png" data-overlay-view="${view.key}" />
            ${view.url ? `<img src="${overlayPreviewUrl(view.url)}" alt="${view.label}" style="max-width: 120px; margin-top: 6px; border-radius: 8px;" />` : ""}
          </label>
        `,
      )
      .join("")}
  `;

  container.querySelectorAll("input[data-overlay-view]").forEach((input) => {
    input.addEventListener("change", async () => {
      const file = input.files?.[0];
      if (!file || !state.haircutEditor?.hairstyleId) return;
      try {
        const folderInput = document.getElementById("hc-overlay-folder");
        await uploadHaircutOverlay(
          state.haircutEditor.hairstyleId,
          input.getAttribute("data-overlay-view"),
          file,
          folderInput?.value?.trim() || "",
        );
        toast("Overlay uploaded.");
        state.haircutDetail = await fetchHaircutDetail(state.haircutEditor.hairstyleId);
        openHaircutEditor(state.haircutDetail.hairstyle, state.haircutDetail.variants);
        await loadHaircuts();
      } catch (error) {
        toast(error.message || "Upload failed", "error");
      } finally {
        input.value = "";
      }
    });
  });
}

function openHaircutEditor(hairstyle, variants = []) {
  const dialog = document.getElementById("haircut-editor-dialog");
  const title = document.getElementById("haircut-editor-title");
  const form = document.getElementById("haircut-editor-form");
  const variantsSection = document.getElementById("haircut-variants-section");
  if (!(dialog instanceof HTMLDialogElement) || !title || !form) return;

  const isEdit = Boolean(hairstyle);
  state.haircutEditor = {
    mode: isEdit ? "edit" : "create",
    hairstyleId: hairstyle?.hairstyle_id ?? null,
  };
  title.textContent = isEdit ? "Manage haircut" : "Add haircut";
  const active = hairstyle?.is_active === false || hairstyle?.is_active === "f" ? "0" : "1";

  form.innerHTML = `
    <label>Style name
      <input class="input" id="hc-name" value="${hairstyle?.style_name ?? ""}" />
    </label>
    <label>Style code
      <input class="input" id="hc-code" value="${hairstyle?.style_code ?? ""}" placeholder="HC-WAVY-MOD" />
    </label>
    <label>Description
      <input class="input" id="hc-description" value="${hairstyle?.description ?? ""}" />
    </label>
    <label>Gender
      <select class="select" id="hc-gender">
        ${["Male", "Female", "Unisex"]
          .map((g) => `<option value="${g}" ${(hairstyle?.gender ?? "Unisex") === g ? "selected" : ""}>${g}</option>`)
          .join("")}
      </select>
    </label>
    <label>Difficulty
      <select class="select" id="hc-difficulty">
        ${["Easy", "Medium", "Hard"]
          .map((d) => `<option value="${d}" ${(hairstyle?.difficulty ?? "Medium") === d ? "selected" : ""}>${d}</option>`)
          .join("")}
      </select>
    </label>
    <label>Maintenance
      <select class="select" id="hc-maintenance">
        ${["Low", "Medium", "High"]
          .map((m) => `<option value="${m}" ${(hairstyle?.maintenance ?? "Medium") === m ? "selected" : ""}>${m}</option>`)
          .join("")}
      </select>
    </label>
    <label>Active
      <select class="select" id="hc-active">
        <option value="1" ${active === "1" ? "selected" : ""}>Yes</option>
        <option value="0" ${active === "0" ? "selected" : ""}>No</option>
      </select>
    </label>
  `;

  if (isEdit) {
    variantsSection?.removeAttribute("hidden");
    state.haircutDetail = { hairstyle, variants };
    renderHaircutVariantsList();
    renderHaircutOverlayUploads(hairstyle);
  } else {
    variantsSection?.setAttribute("hidden", "");
    document.getElementById("haircut-overlay-section")?.setAttribute("hidden", "");
  }

  dialog.showModal();
}

async function saveHaircutEditor() {
  const dialog = document.getElementById("haircut-editor-dialog");
  if (!(dialog instanceof HTMLDialogElement) || !state.haircutEditor) return;

  const payload = {
    styleName: document.getElementById("hc-name")?.value?.trim() || "",
    styleCode: document.getElementById("hc-code")?.value?.trim() || "",
    description: document.getElementById("hc-description")?.value?.trim() || "",
    gender: document.getElementById("hc-gender")?.value || "Unisex",
    difficulty: document.getElementById("hc-difficulty")?.value || "Medium",
    maintenance: document.getElementById("hc-maintenance")?.value || "Medium",
    isActive: Number(document.getElementById("hc-active")?.value ?? 1) !== 0,
  };

  if (!payload.styleName) {
    toast("Style name is required.");
    return;
  }

  try {
    if (state.haircutEditor.mode === "create") {
      const data = await saveHaircut("create", payload);
      toast("Haircut created.");
      state.haircutEditor.hairstyleId = data.hairstyleID;
      state.haircutDetail = await fetchHaircutDetail(data.hairstyleID);
      openHaircutEditor(state.haircutDetail.hairstyle, state.haircutDetail.variants);
    } else {
      await saveHaircut("update", { hairstyleID: state.haircutEditor.hairstyleId, ...payload });
      toast("Haircut updated.");
    }
    await loadHaircuts();
  } catch (error) {
    toast(error.message || "Save failed", "error");
  }
}

function openVariantEditor(variant) {
  const dialog = document.getElementById("variant-editor-dialog");
  const title = document.getElementById("variant-editor-title");
  const form = document.getElementById("variant-editor-form");
  if (!(dialog instanceof HTMLDialogElement) || !title || !form) return;

  const isEdit = Boolean(variant);
  state.variantEditor = {
    mode: isEdit ? "edit" : "create",
    variantId: variant?.variant_id ?? null,
    hairstyleId: state.haircutEditor?.hairstyleId ?? null,
  };
  title.textContent = isEdit ? "Edit variant" : "Add variant";

  form.innerHTML = `
    <label>Face shape
      <select class="select" id="hv-face">
        ${["Oval", "Round", "Square"]
          .map((f) => `<option value="${f}" ${(variant?.face_shape ?? "Oval") === f ? "selected" : ""}>${f}</option>`)
          .join("")}
      </select>
    </label>
    <label>Hair texture
      <select class="select" id="hv-texture">
        ${["Straight", "Wavy", "Curly"]
          .map((t) => `<option value="${t}" ${(variant?.hair_texture ?? "Straight") === t ? "selected" : ""}>${t}</option>`)
          .join("")}
      </select>
    </label>
    <label>Barber instructions
      <input class="input" id="hv-instructions" value="${variant?.barber_instructions ?? ""}" />
    </label>
    <label>Clipper sizes
      <input class="input" id="hv-clippers" value="${variant?.clipper_sizes ?? ""}" />
    </label>
    <label>Styling products
      <input class="input" id="hv-products" value="${variant?.styling_products ?? ""}" />
    </label>
    <label>Estimated minutes
      <input class="input" id="hv-minutes" type="number" min="10" value="${Number(variant?.estimated_minutes ?? 40)}" />
    </label>
    <label>Confidence (0–1)
      <input class="input" id="hv-confidence" type="number" min="0" max="1" step="0.01" value="${Number(variant?.confidence_score ?? 0.85)}" />
    </label>
  `;

  dialog.showModal();
}

async function saveVariantEditor() {
  const dialog = document.getElementById("variant-editor-dialog");
  if (!(dialog instanceof HTMLDialogElement) || !state.variantEditor) return;

  const payload = {
    faceShape: document.getElementById("hv-face")?.value?.trim() || "Oval",
    hairTexture: document.getElementById("hv-texture")?.value || "Straight",
    barberInstructions: document.getElementById("hv-instructions")?.value?.trim() || "",
    clipperSizes: document.getElementById("hv-clippers")?.value?.trim() || "",
    stylingProducts: document.getElementById("hv-products")?.value?.trim() || "",
    estimatedMinutes: Number(document.getElementById("hv-minutes")?.value ?? 40),
    confidenceScore: Number(document.getElementById("hv-confidence")?.value ?? 0.85),
  };

  try {
    if (state.variantEditor.mode === "create") {
      await saveVariant("createVariant", {
        hairstyleID: state.variantEditor.hairstyleId,
        ...payload,
      });
      toast("Variant created.");
    } else {
      await saveVariant("updateVariant", {
        variantID: state.variantEditor.variantId,
        ...payload,
      });
      toast("Variant updated.");
    }
    if (state.haircutEditor?.hairstyleId) {
      state.haircutDetail = await fetchHaircutDetail(state.haircutEditor.hairstyleId);
      renderHaircutVariantsList();
    }
    dialog.close();
    state.variantEditor = null;
  } catch (error) {
    toast(error.message || "Variant save failed", "error");
  }
}

function renderAudit() {
  const list = document.getElementById("audit-list");
  const query = (document.getElementById("audit-search")?.value || "").trim().toLowerCase();
  const categoryFilter = document.getElementById("audit-category-filter")?.value || "all";
  if (!list) return;

  const categorize = (text) => {
    const source = String(text || "").toLowerCase();
    if (source.includes("appointment")) return "appointments";
    if (source.includes("user") || source.includes("customer") || source.includes("barber") || source.includes("receptionist") || source.includes("admin")) return "users";
    if (source.includes("service")) return "services";
    return "system";
  };

  const filtered = state.audit.filter((event) => {
    const textMatch = !query
      || String(event.title ?? "").toLowerCase().includes(query)
      || String(event.description ?? "").toLowerCase().includes(query);
    if (!textMatch) return false;
    if (categoryFilter === "all") return true;
    return categorize(`${event.title} ${event.description}`) === categoryFilter;
  });

  list.innerHTML = "";
  if (!filtered.length) {
    list.innerHTML = '<div class="card empty">No audit events found.</div>';
    return;
  }

  const paged = paginateRows("audit-list", filtered);

  const grouped = paged.items.reduce((acc, event) => {
    const date = String(event.time || "").slice(0, 10) || "Undated";
    if (!acc[date]) acc[date] = [];
    acc[date].push(event);
    return acc;
  }, {});

  Object.entries(grouped).forEach(([date, events]) => {
    const wrapper = document.createElement("div");
    wrapper.className = "group-section";
    wrapper.innerHTML = `<h4 class="group-title">${date}</h4>`;
    events.forEach((event) => {
      const item = document.createElement("div");
      item.className = "card gradient list-item";
      item.innerHTML = `
        <div class="icon-box">LOG</div>
        <div>
          <h4>${event.title || "Audit Event"}</h4>
          <p>${event.description || ""}</p>
        </div>
        <div class="time">${event.time || ""}</div>
      `;
      wrapper.appendChild(item);
    });
    list.appendChild(wrapper);
  });

  const pager = paginationMarkup("audit-list", paged.currentPage, paged.totalPages);
  if (pager) {
    list.insertAdjacentHTML("beforeend", pager);
  }
}

async function loadAudit() {
  try {
    const response = await fetch(resolveApiUrl("admin_audit.php"));
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    state.audit = data.events ?? [];
  } catch (_) {
    state.audit = [];
  }
  renderAudit();
}

function renderAnalyticsMetrics(metrics) {
  const container = document.getElementById("analytics-metrics");
  if (!container) return;
  container.innerHTML = "";
  if (!metrics) {
    container.innerHTML = '<div class="card empty">No metrics available.</div>';
    return;
  }
  const items = [
    { title: "Total Users", value: metrics.totalUsers ?? 0 },
    { title: "Total Barbers", value: metrics.totalBarbers ?? 0 },
    { title: "Active Services", value: metrics.activeServices ?? 0 },
    { title: "Monthly Revenue", value: `PHP ${Number(metrics.monthlyRevenue ?? 0).toFixed(2)}` },
  ];
  items.forEach((stat) => {
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `<h3>${stat.title}</h3><div class="value">${stat.value}</div>`;
    container.appendChild(card);
  });
}

function destroyAnalyticsCharts() {
  if (state.statusChart) {
    state.statusChart.destroy();
    state.statusChart = null;
  }
  if (state.servicesChart) {
    state.servicesChart.destroy();
    state.servicesChart = null;
  }
}

function renderAnalyticsCharts(metrics) {
  if (typeof Chart === "undefined") {
    return;
  }

  const statusCanvas = document.getElementById("analytics-status-chart");
  const servicesCanvas = document.getElementById("analytics-services-chart");
  if (!(statusCanvas instanceof HTMLCanvasElement) || !(servicesCanvas instanceof HTMLCanvasElement)) {
    return;
  }

  destroyAnalyticsCharts();

  const statusRows = metrics?.appointmentStatusCounts ?? [];
  const statusLabels = statusRows.map((row) => row.status || "Unknown");
  const statusValues = statusRows.map((row) => Number(row.count ?? 0));

  state.statusChart = new Chart(statusCanvas, {
    type: "line",
    data: {
      labels: statusLabels.length ? statusLabels : ["No Data"],
      datasets: [
        {
          label: "Appointments",
          data: statusValues.length ? statusValues : [0],
          borderColor: "#00b0ff",
          backgroundColor: "rgba(0, 176, 255, 0.2)",
          tension: 0.35,
          fill: true,
        },
      ],
    },
    options: {
      maintainAspectRatio: false,
      plugins: { legend: { labels: { color: "#c9c9c9" } } },
      scales: {
        x: { ticks: { color: "#c9c9c9" }, grid: { color: "rgba(255,255,255,0.08)" } },
        y: { ticks: { color: "#c9c9c9", precision: 0 }, grid: { color: "rgba(255,255,255,0.08)" } },
      },
    },
  });

  const serviceRows = metrics?.topServices ?? [];
  const serviceLabels = serviceRows.map((row) => row.service_name || "Service");
  const serviceValues = serviceRows.map((row) => Number(row.count ?? 0));

  state.servicesChart = new Chart(servicesCanvas, {
    type: "bar",
    data: {
      labels: serviceLabels.length ? serviceLabels : ["No Data"],
      datasets: [
        {
          label: "Bookings",
          data: serviceValues.length ? serviceValues : [0],
          backgroundColor: ["#ff4f81", "#00b0ff", "#f7c948", "#00c853", "#ff7043"],
          borderRadius: 8,
        },
      ],
    },
    options: {
      maintainAspectRatio: false,
      plugins: { legend: { labels: { color: "#c9c9c9" } } },
      scales: {
        x: { ticks: { color: "#c9c9c9" }, grid: { color: "rgba(255,255,255,0.08)" } },
        y: { ticks: { color: "#c9c9c9", precision: 0 }, grid: { color: "rgba(255,255,255,0.08)" } },
      },
    },
  });
}

function renderAiBrief(summary, suggestive, predictive) {
  const container = document.getElementById("analytics-ai-brief");
  const summaryEl = document.getElementById("analytics-summary");
  if (!container || !summaryEl) return;

  const shortSummary = String(summary || "No AI summary available.")
    .replace(/\s+/g, " ")
    .trim();
  summaryEl.textContent = shortSummary;

  const topSuggestive = suggestive?.[0] || "No suggestive insight yet.";
  const topPredictive = predictive?.[0] || "No predictive insight yet.";

  container.innerHTML = `
    <div class="ai-brief-item"><strong>Suggest:</strong> ${topSuggestive}</div>
    <div class="ai-brief-item"><strong>Predict:</strong> ${topPredictive}</div>
  `;
}

async function loadAnalytics() {
  try {
    const response = await fetch(resolveApiUrl("admin_analytics.php"));
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    state.analytics = data.metrics ?? null;
    renderAnalyticsCharts(data.metrics ?? null);
    await renderAiInsights(data.metrics ?? null, data.summary ?? "");
  } catch (_) {
    state.analytics = null;
    const summaryEl = document.getElementById("analytics-summary");
    if (summaryEl) summaryEl.textContent = "Failed to load AI summary.";
    const brief = document.getElementById("analytics-ai-brief");
    if (brief) brief.innerHTML = '<div class="ai-brief-item">AI insights are currently unavailable.</div>';
    destroyAnalyticsCharts();
  }
}

function fallbackInsights(metrics) {
  const monthlyRevenue = Number(metrics?.monthlyRevenue ?? 0);
  const activeServices = Number(metrics?.activeServices ?? 0);
  const totalUsers = Number(metrics?.totalUsers ?? 0);
  return {
    suggestive: [
      "Promote your top 3 services during peak hours to increase average ticket size.",
      activeServices < 5
        ? "Add more active services to improve upsell opportunities at the front desk."
        : "Bundle high-demand services into combo offers to improve conversion.",
      "Use receptionist reminders to rebook clients before they leave the shop.",
    ],
    predictive: [
      monthlyRevenue > 0
        ? `If current pace holds, projected monthly revenue remains around PHP ${monthlyRevenue.toFixed(2)}.`
        : "Revenue trend cannot be projected yet because paid transactions are limited.",
      totalUsers > 50
        ? "Customer demand is likely to rise this weekend; prepare additional barber slots."
        : "Customer volume is still building; run targeted promos to increase recurring visits.",
      "Expect morning queue pressure; prioritize quick services in the first two hours.",
    ],
  };
}

function parseInsightJson(text) {
  const clean = String(text || "").trim();
  if (!clean) return null;
  const match = clean.match(/\{[\s\S]*\}/);
  if (!match) return null;
  try {
    const parsed = JSON.parse(match[0]);
    if (!Array.isArray(parsed.suggestive) || !Array.isArray(parsed.predictive)) {
      return null;
    }
    return parsed;
  } catch (_) {
    return null;
  }
}

async function buildGeminiInsights(metrics, summary) {
  const prompt = [
    "You are an analytics strategist for a barbershop.",
    "Using the provided metrics, produce practical recommendations.",
    "Return strict JSON with keys suggestive and predictive.",
    "Each key must contain an array of exactly 3 short strings.",
    "Do not include markdown or extra keys.",
    `Metrics JSON: ${JSON.stringify(metrics || {})}`,
    `Current summary: ${summary || "N/A"}`,
  ].join("\n");

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${CHATBOT_MODEL}:generateContent?key=${CHATBOT_API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.4,
          topP: 0.9,
          maxOutputTokens: 400,
        },
      }),
    }
  );

  if (!response.ok) {
    throw new Error("Gemini request failed");
  }

  const data = await response.json();
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "";
  const parsed = parseInsightJson(text);
  if (!parsed) {
    throw new Error("Gemini response parse failed");
  }
  return {
    suggestive: parsed.suggestive.slice(0, 3),
    predictive: parsed.predictive.slice(0, 3),
  };
}

async function renderAiInsights(metrics, summary) {
  try {
    const insights = await buildGeminiInsights(metrics, summary);
    renderAiBrief(summary, insights.suggestive, insights.predictive);
  } catch (_) {
    const fallback = fallbackInsights(metrics);
    renderAiBrief(summary, fallback.suggestive, fallback.predictive);
  }
}

async function loadSettings() {
  try {
    const response = await fetch(resolveApiUrl("admin_settings.php"));
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    const settings = data.settings ?? {};
    document.getElementById("setting-email").checked = settings.emailNotificationsEnabled === 1;
    document.getElementById("setting-mfa").checked = settings.forceMfa === 1;
    document.getElementById("setting-backup").checked = settings.autoBackupEnabled === 1;
    const fromEmail = document.getElementById("setting-from-email");
    if (fromEmail) {
      fromEmail.value = settings.notificationFromEmail || "noreply@barberyatatis.local";
    }
  } catch (_) {
    // no-op
  }
}

const SCHEDULE_DAY_ORDER = [1, 2, 3, 4, 5, 6, 0];
const SCHEDULE_DAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];

function escapeScheduleText(value) {
  return String(value ?? "").replace(/[&<>"]/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[ch]));
}

async function scheduleApi(payload) {
  const response = await fetch(resolveApiUrl("operating_schedule.php"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.error || "Schedule API error");
  }
  return data;
}

function renderScheduleWeekly() {
  const list = document.getElementById("schedule-weekly");
  if (!list || !state.schedule) return;
  const byDay = new Map(state.schedule.weekly.map((day) => [day.dayOfWeek, day]));
  list.innerHTML = SCHEDULE_DAY_ORDER.map((dow) => {
    const day = byDay.get(dow) || { isClosed: false, openTime: "09:00", closeTime: "20:00" };
    return `
      <div class="row-wrap" data-schedule-day="${dow}" style="gap: 12px;">
        <strong style="width: 110px;">${SCHEDULE_DAY_NAMES[dow]}</strong>
        <label class="meta" style="display: flex; align-items: center; gap: 6px;">
          <input type="checkbox" class="schedule-day-closed" ${day.isClosed ? "checked" : ""} /> Closed
        </label>
        <input class="input schedule-day-open" type="time" value="${day.openTime}" ${day.isClosed ? "disabled" : ""} style="max-width: 130px;" />
        <span class="meta">to</span>
        <input class="input schedule-day-close" type="time" value="${day.closeTime}" ${day.isClosed ? "disabled" : ""} style="max-width: 130px;" />
      </div>`;
  }).join("");

  list.querySelectorAll(".schedule-day-closed").forEach((checkbox) => {
    checkbox.addEventListener("change", () => {
      const row = checkbox.closest("[data-schedule-day]");
      row?.querySelectorAll("input[type=time]").forEach((input) => {
        input.disabled = checkbox.checked;
      });
    });
  });
}

function renderScheduleBreaks() {
  const list = document.getElementById("schedule-breaks");
  if (!list || !state.schedule) return;
  const breaks = state.schedule.breaks || [];
  if (!breaks.length) {
    list.innerHTML = '<div class="meta">No break windows. Slots run straight through opening hours.</div>';
    return;
  }
  list.innerHTML = breaks.map((item, index) => `
    <div class="row-wrap" style="gap: 12px;">
      <strong style="width: 110px;">${escapeScheduleText(item.dayName)}</strong>
      <span>${item.startTime} – ${item.endTime}</span>
      <span class="meta">${escapeScheduleText(item.label)}</span>
      <button class="btn secondary schedule-break-remove" data-index="${index}" type="button">Remove</button>
    </div>`).join("");

  list.querySelectorAll(".schedule-break-remove").forEach((button) => {
    button.addEventListener("click", () => {
      state.schedule.breaks.splice(Number(button.dataset.index), 1);
      renderScheduleBreaks();
    });
  });
}

function renderScheduleClosedDates() {
  const list = document.getElementById("schedule-closed-dates");
  if (!list || !state.schedule) return;
  const dates = state.schedule.closedDates || [];
  if (!dates.length) {
    list.innerHTML = '<div class="meta">No upcoming closed dates.</div>';
    return;
  }
  list.innerHTML = dates.map((item) => `
    <div class="row-wrap" style="gap: 12px;">
      <strong style="width: 110px;">${item.date}</strong>
      <span class="meta">${escapeScheduleText(item.reason) || "—"}</span>
      <button class="btn secondary schedule-closed-remove" data-date="${item.date}" type="button">Remove</button>
    </div>`).join("");

  list.querySelectorAll(".schedule-closed-remove").forEach((button) => {
    button.addEventListener("click", async () => {
      const confirmed = await confirmAction(`Remove closed date ${button.dataset.date}?`, { confirmLabel: "Remove" });
      if (!confirmed) return;
      try {
        const data = await scheduleApi({ action: "removeClosedDate", date: button.dataset.date });
        state.schedule = data.schedule;
        renderSchedule();
        toast("Closed date removed.", "success");
        if (state.scheduleCalendar) {
          loadScheduleCalendar(state.scheduleCalendar.year, state.scheduleCalendar.month);
        }
      } catch (error) {
        toast(error.message, "error");
      }
    });
  });
}

function renderScheduleSettings() {
  if (!state.schedule) return;
  const settings = state.schedule.settings || {};
  const slotInput = document.getElementById("schedule-slot-minutes");
  const walkinInput = document.getElementById("schedule-walkin-minutes");
  const timezoneInput = document.getElementById("schedule-timezone");
  if (slotInput) slotInput.value = settings.appointmentMinutes ?? 60;
  if (walkinInput) walkinInput.value = settings.walkinMinutes ?? 35;
  if (timezoneInput) timezoneInput.value = settings.timezone || "Asia/Manila";
}

function renderSchedule() {
  renderScheduleWeekly();
  renderScheduleBreaks();
  renderScheduleClosedDates();
  renderScheduleSettings();
  renderScheduleCalendar();
}

function renderScheduleCalDayDetail(day) {
  const detail = document.getElementById("schedule-cal-day-detail");
  if (!detail) return;
  if (!day) {
    detail.innerHTML = "Select a day to see hours and closure details.";
    return;
  }
  if (day.status === "open") {
    const booked = Number(day.bookedAppointments || 0);
    const bookedText = booked > 0 ? ` · ${booked} appointment(s) booked` : "";
    detail.innerHTML = `<strong>${day.dayName}, ${day.date}</strong> — Open ${day.openTime}–${day.closeTime}. `
      + `${day.bookableSlotCount} bookable slot(s)${bookedText}.`;
    return;
  }
  detail.innerHTML = `<strong>${day.dayName}, ${day.date}</strong> — Closed. ${escapeScheduleText(day.reason)}`;
}

function renderScheduleCalendar() {
  const grid = document.getElementById("schedule-calendar-grid");
  const label = document.getElementById("schedule-cal-month-label");
  const cal = state.scheduleCalendar;
  if (!grid || !cal) return;

  if (label) label.textContent = cal.monthLabel || "—";

  const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const firstDay = new Date(cal.year, cal.month - 1, 1).getDay();
  const cells = [];

  weekdays.forEach((name) => {
    cells.push(`<div class="cal-weekday">${name}</div>`);
  });
  for (let i = 0; i < firstDay; i++) {
    cells.push('<div class="cal-day cal-empty"></div>');
  }

  (cal.days || []).forEach((day) => {
    const selected = state.scheduleCalSelected === day.date;
    const statusClass = day.isPast ? "cal-past" : `cal-${day.status.replace(/_/g, "-")}`;
    const title = day.status === "open"
      ? `Open ${day.openTime}–${day.closeTime}`
      : day.reason;
    cells.push(
      `<button type="button" class="cal-day ${statusClass}${selected ? " cal-selected" : ""}" `
      + `data-date="${day.date}" title="${escapeScheduleText(title)}">${Number(day.date.slice(-2))}</button>`
    );
  });

  grid.innerHTML = cells.join("");

  grid.querySelectorAll(".cal-day[data-date]").forEach((button) => {
    button.addEventListener("click", () => {
      const date = button.getAttribute("data-date");
      const day = (cal.days || []).find((d) => d.date === date);
      state.scheduleCalSelected = date;
      renderScheduleCalendar();
      renderScheduleCalDayDetail(day);
      const closedInput = document.getElementById("schedule-closed-date");
      if (closedInput && day && day.status === "open" && !day.isPast) {
        closedInput.value = date;
      }
    });
  });

  if (state.scheduleCalSelected) {
    const selectedDay = (cal.days || []).find((d) => d.date === state.scheduleCalSelected);
    renderScheduleCalDayDetail(selectedDay);
  } else {
    renderScheduleCalDayDetail(null);
  }
}

async function loadScheduleCalendar(year, month) {
  const now = new Date();
  const y = year ?? now.getFullYear();
  const m = month ?? now.getMonth() + 1;
  try {
    const data = await scheduleApi({ action: "calendarMonth", year: y, month: m });
    state.scheduleCalendar = data;
    if (!state.scheduleCalSelected) {
      state.scheduleCalSelected = `${y}-${String(m).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
    }
    renderScheduleCalendar();
  } catch (error) {
    toast(error.message, "error");
  }
}

function showScheduleWarnings(warnings) {
  (warnings || []).forEach((warning) => toast(warning, "warning"));
}

async function loadOperatingSchedule() {
  try {
    const response = await fetch(resolveApiUrl("operating_schedule.php"));
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    state.schedule = data.schedule;
    renderSchedule();
    const now = new Date();
    await loadScheduleCalendar(now.getFullYear(), now.getMonth() + 1);
  } catch (_) {
    // no-op
  }
}

async function refreshAll() {
  window.PortalUi?.resetLoading?.();
  await Promise.all([
    loadDashboard(),
    loadUsers(),
    loadAudit(),
    loadAnalytics(),
    loadServices(),
    loadHaircuts(),
    loadSettings(),
    loadOperatingSchedule(),
    loadAiStatus(),
  ]);
  setLastUpdated();
}

document.addEventListener("click", async (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) return;

  if (target.classList.contains("pager-btn")) {
    const key = target.dataset.pageKey;
    const nextPage = Number(target.dataset.page || "1");
    if (key && Number.isFinite(nextPage)) {
      state.pagination[key] = Math.max(1, nextPage);
      rerenderByPaginationKey(key);
    }
    return;
  }

  if (target.classList.contains("btn-edit")) {
    const type = target.dataset.type;
    const id = target.dataset.id;
    if (!type || !id) return;
    openAccountEditor(type, Number(id));
  }

  if (target.classList.contains("btn-delete")) {
    const type = target.dataset.type;
    const id = target.dataset.id;
    if (!type || !id) return;
    await deleteAccount(type, Number(id));
  }

  if (target.classList.contains("btn-service")) {
    const id = target.dataset.id;
    if (!id) return;
    const existing = (state.services || []).find((row) => String(row.service_id) === String(id));
    openServiceEditor(existing);
  }

  if (target.classList.contains("btn-service-delete")) {
    const id = target.dataset.id;
    if (!id) return;
    const ok = await confirmAction("Deactivate this service?", {
      title: "Deactivate service",
      confirmLabel: "Deactivate",
      danger: true,
    });
    if (!ok) return;
    try {
      await saveService("delete", { serviceID: Number(id) });
      toast("Service deactivated.");
      await loadServices();
    } catch (error) {
      toast(error.message || "Delete failed");
    }
  }

  if (target.classList.contains("btn-haircut")) {
    const id = target.dataset.id;
    if (!id) return;
    try {
      const detail = await fetchHaircutDetail(Number(id));
      openHaircutEditor(detail.hairstyle, detail.variants);
    } catch (error) {
      toast(error.message || "Failed to open haircut", "error");
    }
  }

  if (target.classList.contains("btn-haircut-delete")) {
    const id = target.dataset.id;
    if (!id) return;
    const ok = await confirmAction("Deactivate this haircut?", {
      title: "Deactivate haircut",
      confirmLabel: "Deactivate",
      danger: true,
    });
    if (!ok) return;
    try {
      await saveHaircut("delete", { hairstyleID: Number(id) });
      toast("Haircut deactivated.");
      await loadHaircuts();
    } catch (error) {
      toast(error.message || "Delete failed", "error");
    }
  }

  if (target.classList.contains("btn-variant-edit")) {
    const id = target.dataset.id;
    const variant = (state.haircutDetail?.variants ?? []).find(
      (row) => String(row.variant_id) === String(id),
    );
    openVariantEditor(variant);
  }

  if (target.classList.contains("btn-variant-delete")) {
    const id = target.dataset.id;
    if (!id) return;
    const ok = await confirmAction("Delete this variant?", {
      title: "Delete variant",
      confirmLabel: "Delete",
      danger: true,
    });
    if (!ok) return;
    try {
      await saveVariant("deleteVariant", { variantID: Number(id) });
      toast("Variant deleted.");
      if (state.haircutEditor?.hairstyleId) {
        state.haircutDetail = await fetchHaircutDetail(state.haircutEditor.hairstyleId);
        renderHaircutVariantsList();
      }
    } catch (error) {
      toast(error.message || "Delete failed", "error");
    }
  }

});

document.getElementById("users-search")?.addEventListener("input", () => {
  resetPagination(["customers-table", "barbers-table", "receptionists-table", "admins-table"]);
  renderUserTables();
});
document.getElementById("users-role-filter")?.addEventListener("change", () => {
  resetPagination(["customers-table", "barbers-table", "receptionists-table", "admins-table"]);
  renderUserTables();
});
document.getElementById("services-search")?.addEventListener("input", () => {
  resetPagination(["services-table"]);
  renderServices();
});

document.getElementById("services-add")?.addEventListener("click", () => openServiceEditor(null));
document.getElementById("haircuts-add")?.addEventListener("click", () => openHaircutEditor(null));
document.getElementById("haircuts-search")?.addEventListener("input", () => {
  resetPagination(["haircuts-table"]);
  renderHaircuts();
});
document.getElementById("haircut-editor-save")?.addEventListener("click", saveHaircutEditor);
document.getElementById("haircut-editor-cancel")?.addEventListener("click", () => {
  const dialog = document.getElementById("haircut-editor-dialog");
  if (dialog instanceof HTMLDialogElement) dialog.close();
  state.haircutEditor = null;
  state.haircutDetail = null;
});
document.getElementById("haircut-variant-add")?.addEventListener("click", () => openVariantEditor(null));
document.getElementById("variant-editor-save")?.addEventListener("click", saveVariantEditor);
document.getElementById("variant-editor-cancel")?.addEventListener("click", () => {
  const dialog = document.getElementById("variant-editor-dialog");
  if (dialog instanceof HTMLDialogElement) dialog.close();
  state.variantEditor = null;
});
document.getElementById("service-editor-save")?.addEventListener("click", saveServiceEditor);
document.getElementById("service-editor-cancel")?.addEventListener("click", () => {
  const dialog = document.getElementById("service-editor-dialog");
  if (dialog instanceof HTMLDialogElement) dialog.close();
  state.serviceEditor = null;
});
document.getElementById("audit-search")?.addEventListener("input", () => {
  resetPagination(["audit-list"]);
  renderAudit();
});
document.getElementById("activity-category-filter")?.addEventListener("change", () => {
  resetPagination(["activity-list"]);
  renderActivities(state.activities);
});
document.getElementById("audit-category-filter")?.addEventListener("change", () => {
  resetPagination(["audit-list"]);
  renderAudit();
});
document.getElementById("profile-avatar-btn")?.addEventListener("click", openProfileDialog);
document.getElementById("profile-dialog-edit")?.addEventListener("click", () => {
  state.profileEditMode = true;
  renderProfileDialogContent();
});
document.getElementById("profile-dialog-save")?.addEventListener("click", saveProfileEdits);
document.getElementById("profile-dialog-cancel")?.addEventListener("click", () => {
  state.profileEditMode = false;
  renderProfileDialogContent();
});
document.getElementById("profile-dialog-close")?.addEventListener("click", () => {
  const dialog = document.getElementById("profile-dialog");
  if (dialog instanceof HTMLDialogElement) dialog.close();
});
document.getElementById("account-editor-save")?.addEventListener("click", saveAccountEditor);
document.getElementById("users-add-account")?.addEventListener("click", openAccountCreateDialog);
document.getElementById("account-editor-cancel")?.addEventListener("click", () => {
  const dialog = document.getElementById("account-editor-dialog");
  if (dialog instanceof HTMLDialogElement) dialog.close();
  state.accountEditor = null;
});

document.getElementById("audit-export")?.addEventListener("click", () => {
  const filtered = (state.audit || []).map((event) => ({
    title: event.title,
    description: event.description,
    time: event.time,
  }));
  downloadCsv("audit-events.csv", filtered);
});

document.getElementById("settings-save")?.addEventListener("click", async () => {
  try {
    const payload = {
      action: "update",
      emailNotificationsEnabled: document.getElementById("setting-email").checked ? 1 : 0,
      forceMfa: document.getElementById("setting-mfa").checked ? 1 : 0,
      autoBackupEnabled: document.getElementById("setting-backup").checked ? 1 : 0,
      notificationFromEmail: document.getElementById("setting-from-email")?.value?.trim() || "",
    };
    const response = await fetch(resolveApiUrl("admin_settings.php"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    if (!response.ok) {
      const data = await response.json();
      throw new Error(data.error || "Save failed");
    }
    toast("Settings saved.");
  } catch (error) {
    toast(error.message || "Save failed");
  }
});

document.querySelectorAll("[data-export]").forEach((button) => {
  button.addEventListener("click", async () => {
    const table = button.getAttribute("data-export");
    try {
      const response = await fetch(resolveApiUrl("admin_settings.php"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "exportCsv", table }),
      });
      if (!response.ok) throw new Error("Export failed");
      const data = await response.json();
      const blob = new Blob([data.csv || ""], { type: "text/csv" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `${table}.csv`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (error) {
      toast(error.message || "Export failed");
    }
  });
});

document.getElementById("services-import")?.addEventListener("click", async () => {
  const input = document.getElementById("services-csv");
  if (!(input instanceof HTMLInputElement) || !input.files || input.files.length === 0) {
    toast("Select a CSV file first.");
    return;
  }
  const file = input.files[0];
  const text = await file.text();
  try {
    const response = await fetch(resolveApiUrl("admin_settings.php"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "importServicesCsv", csvText: text }),
    });
    if (!response.ok) {
      const data = await response.json();
      throw new Error(data.error || "Import failed");
    }
    toast("Import complete.");
    await loadServices();
  } catch (error) {
    toast(error.message || "Import failed");
  }
});

document.getElementById("settings-test-email")?.addEventListener("click", async () => {
  const email = document.getElementById("setting-test-email")?.value?.trim() || "";
  if (!email) {
    toast("Enter a test email address first.");
    return;
  }
  try {
    const response = await fetch(resolveApiUrl("admin_settings.php"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "sendTestEmail", email }),
    });
    const data = await parseJsonResponse(response);
    if (!response.ok) {
      throw new Error(data.error || data.message || "Test email failed");
    }
    toast(data.message || "Test email sent.");
  } catch (error) {
    toast(error.message || "Test email failed");
  }
});

document.getElementById("settings-process-notifications")?.addEventListener("click", async () => {
  try {
    const response = await fetch(resolveApiUrl("admin_settings.php"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "processNotifications" }),
    });
    const data = await parseJsonResponse(response);
    if (!response.ok) {
      throw new Error(data.error || data.message || "Queue processing failed");
    }
    toast(data.message || "Notifications processed.");
  } catch (error) {
    toast(error.message || "Queue processing failed");
  }
});

document.getElementById("settings-download-backup")?.addEventListener("click", async () => {
  try {
    const response = await fetch(resolveApiUrl("admin_settings.php"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "downloadBackup" }),
    });
    const data = await parseJsonResponse(response);
    if (!response.ok) {
      throw new Error(data.error || "Backup failed");
    }
    const blob = new Blob([JSON.stringify(data.backup ?? {}, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = data.fileName || `tatis_backup_${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);
    toast(data.message || "Backup downloaded.");
  } catch (error) {
    toast(error.message || "Backup failed");
  }
});

document.getElementById("schedule-cal-prev")?.addEventListener("click", () => {
  const cal = state.scheduleCalendar;
  if (!cal) return;
  let y = cal.year;
  let m = cal.month - 1;
  if (m < 1) { m = 12; y -= 1; }
  loadScheduleCalendar(y, m);
});

document.getElementById("schedule-cal-next")?.addEventListener("click", () => {
  const cal = state.scheduleCalendar;
  if (!cal) return;
  let y = cal.year;
  let m = cal.month + 1;
  if (m > 12) { m = 1; y += 1; }
  loadScheduleCalendar(y, m);
});

document.getElementById("schedule-save-weekly")?.addEventListener("click", async () => {
  const rows = document.querySelectorAll("#schedule-weekly [data-schedule-day]");
  const days = Array.from(rows).map((row) => ({
    dayOfWeek: Number(row.getAttribute("data-schedule-day")),
    isClosed: row.querySelector(".schedule-day-closed")?.checked || false,
    openTime: row.querySelector(".schedule-day-open")?.value || "09:00",
    closeTime: row.querySelector(".schedule-day-close")?.value || "20:00",
  }));
  try {
    const data = await scheduleApi({ action: "updateWeekly", days });
    state.schedule = data.schedule;
    renderSchedule();
    toast("Weekly hours saved.", "success");
    showScheduleWarnings(data.warnings);
    if (state.scheduleCalendar) {
      loadScheduleCalendar(state.scheduleCalendar.year, state.scheduleCalendar.month);
    }
  } catch (error) {
    toast(error.message, "error");
  }
});

document.getElementById("schedule-break-add")?.addEventListener("click", () => {
  if (!state.schedule) return;
  const dayRaw = document.getElementById("schedule-break-day")?.value ?? "";
  const startTime = document.getElementById("schedule-break-start")?.value || "";
  const endTime = document.getElementById("schedule-break-end")?.value || "";
  const label = document.getElementById("schedule-break-label")?.value?.trim() || "";
  if (!startTime || !endTime || endTime <= startTime) {
    toast("Enter a valid break window (end after start).", "error");
    return;
  }
  const dayOfWeek = dayRaw === "" ? null : Number(dayRaw);
  state.schedule.breaks.push({
    dayOfWeek,
    dayName: dayOfWeek === null ? "Every day" : SCHEDULE_DAY_NAMES[dayOfWeek],
    startTime,
    endTime,
    label,
  });
  renderScheduleBreaks();
  toast("Break added. Click Save breaks to apply.", "info");
});

document.getElementById("schedule-save-breaks")?.addEventListener("click", async () => {
  if (!state.schedule) return;
  const breaks = (state.schedule.breaks || []).map((item) => ({
    dayOfWeek: item.dayOfWeek,
    startTime: item.startTime,
    endTime: item.endTime,
    label: item.label,
  }));
  try {
    const data = await scheduleApi({ action: "updateBreaks", breaks });
    state.schedule = data.schedule;
    renderSchedule();
    toast("Break windows saved.", "success");
  } catch (error) {
    toast(error.message, "error");
  }
});

document.getElementById("schedule-closed-add")?.addEventListener("click", async () => {
  const date = document.getElementById("schedule-closed-date")?.value || "";
  const reason = document.getElementById("schedule-closed-reason")?.value?.trim() || "";
  if (!date) {
    toast("Pick a date first.", "error");
    return;
  }
  try {
    const data = await scheduleApi({ action: "addClosedDate", date, reason });
    state.schedule = data.schedule;
    renderSchedule();
    toast("Closed date added.", "success");
    showScheduleWarnings(data.warnings);
    if (state.scheduleCalendar) {
      loadScheduleCalendar(state.scheduleCalendar.year, state.scheduleCalendar.month);
    }
  } catch (error) {
    toast(error.message, "error");
  }
});

document.getElementById("schedule-save-slots")?.addEventListener("click", async () => {
  const slotMinutes = Number(document.getElementById("schedule-slot-minutes")?.value || 0);
  const walkinMinutes = Number(document.getElementById("schedule-walkin-minutes")?.value || 0);
  try {
    const data = await scheduleApi({
      action: "updateSlotSettings",
      slotMinutes,
      appointmentMinutes: slotMinutes,
      walkinMinutes,
    });
    state.schedule = data.schedule;
    renderSchedule();
    toast("Slot settings saved.", "success");
  } catch (error) {
    toast(error.message, "error");
  }
});

document.getElementById("schedule-preview-btn")?.addEventListener("click", async () => {
  const date = document.getElementById("schedule-preview-date")?.value || "";
  const result = document.getElementById("schedule-preview-result");
  if (!date || !result) {
    toast("Pick a date to preview.", "error");
    return;
  }
  try {
    const data = await scheduleApi({ action: "previewSlots", date });
    if (data.isClosed) {
      result.innerHTML = `<strong>${data.dayName}, ${data.date}</strong> — Shop is closed.`;
      return;
    }
    const slotLabels = (data.slots || []).map((slot) => slot.label).join(", ") || "No bookable slots.";
    const breakText = (data.breaks || []).map((b) => `${b.startTime}–${b.endTime}`).join(", ") || "None";
    result.innerHTML = `<strong>${data.dayName}, ${data.date}</strong> — Open ${data.openTime}–${data.closeTime} · Breaks: ${breakText}<br />Bookable slots: ${slotLabels}`;
  } catch (error) {
    toast(error.message, "error");
  }
});

document.getElementById("refresh-all")?.addEventListener("click", refreshAll);

document.getElementById("global-search")?.addEventListener("input", (event) => {
  const value = String(event.target.value || "");
  const activeView = document.querySelector(".nav button.active")?.dataset.view || "dashboard";
  if (activeView === "users") {
    const usersSearch = document.getElementById("users-search");
    if (usersSearch) {
      usersSearch.value = value;
      resetPagination(["customers-table", "barbers-table", "receptionists-table", "admins-table"]);
      renderUserTables();
    }
  }
  if (activeView === "audit") {
    const auditSearch = document.getElementById("audit-search");
    if (auditSearch) {
      auditSearch.value = value;
      resetPagination(["audit-list"]);
      renderAudit();
    }
  }
  if (activeView === "services") {
    const servicesSearch = document.getElementById("services-search");
    if (servicesSearch) {
      servicesSearch.value = value;
      resetPagination(["services-table"]);
      renderServices();
    }
  }
  if (activeView === "haircuts") {
    const haircutsSearch = document.getElementById("haircuts-search");
    if (haircutsSearch) {
      haircutsSearch.value = value;
      resetPagination(["haircuts-table"]);
      renderHaircuts();
    }
  }
});

async function init() {
  if (!requireAdmin()) return;
  renderProfileChip();
  await refreshAll();
}

init();
