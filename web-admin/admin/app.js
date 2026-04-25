const views = {
  dashboard: document.getElementById("dashboard-view"),
  users: document.getElementById("users-view"),
  audit: document.getElementById("audit-view"),
  analytics: document.getElementById("analytics-view"),
  services: document.getElementById("services-view"),
  settings: document.getElementById("settings-view"),
};

const state = {
  users: { customers: [], barbers: [], receptionists: [], admins: [] },
  services: [],
  audit: [],
  activities: [],
  currentUser: null,
  profileEditMode: false,
  accountEditor: null,
  analytics: null,
  statusChart: null,
  servicesChart: null,
  autoRefreshTimer: null,
  pagination: {},
};

const CHATBOT_API_KEY = "REMOVED_GEMINI_KEY";
const CHATBOT_MODEL = "gemini-2.5-flash";
const ACTION_CATALOG = [
  {
    action: "open-services",
    label: "Open Services",
    description: "Review and update service offerings, promos, and bundles.",
  },
  {
    action: "open-users",
    label: "Open Users",
    description: "Open customers and staff records for retention or outreach tasks.",
  },
  {
    action: "open-audit",
    label: "Open Audit",
    description: "Inspect recent operational logs and queue-related events.",
  },
  {
    action: "open-analytics",
    label: "Review Analytics",
    description: "Stay in analytics to review trends and KPI movement.",
  },
  {
    action: "refresh-analytics",
    label: "Refresh Analytics",
    description: "Re-run analytics and AI insights with latest available data.",
  },
];

const DEFAULT_PAGE_SIZE = 8;
const PAGE_SIZE_BY_KEY = {
  "activity-list": 6,
  "customers-table": 6,
  "barbers-table": 6,
  "receptionists-table": 6,
  "admins-table": 6,
  "services-table": 6,
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
<<<<<<< Updated upstream
    navButtons.forEach((b) => b.classList.remove("active"));
    button.classList.add("active");
    Object.values(views).forEach((section) => section.setAttribute("hidden", ""));
    if (views[view]) {
      views[view].removeAttribute("hidden");
    }
=======
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
>>>>>>> Stashed changes
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

function toast(message) {
  window.alert(message);
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
    const response = await fetch("../../api/staff_profile.php", {
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
    toast("Profile updated.");
  } catch (error) {
    toast(error.message || "Profile update failed");
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
    const response = await fetch("../../api/ai_status.php");
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
    const response = await fetch("../../api/admin_dashboard.php");
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

<<<<<<< Updated upstream
loadDashboard();
=======
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
      { key: "is_active", label: "Active" },
      { key: "created_at", label: "Created" },
      { key: "actions", label: "Actions" },
    ],
    (roleFilter === "all" || roleFilter === "customers"
      ? data.customers.map((row) => ({
          ...row,
          actions: `<button class="btn btn-edit" data-type="customer" data-id="${row.user_id}">Edit</button>`,
        }))
      : [])
  );

  renderTable(
    "barbers-table",
    [
      { key: "full_name", label: "Name" },
      { key: "specialty", label: "Specialty" },
      { key: "rating", label: "Rating" },
      { key: "is_active", label: "Active" },
      { key: "created_at", label: "Created" },
      { key: "actions", label: "Actions" },
    ],
    (roleFilter === "all" || roleFilter === "barbers"
      ? data.barbers.map((row) => ({
          ...row,
          actions: `<button class="btn btn-edit" data-type="barber" data-id="${row.barber_id}">Edit</button>`,
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
          actions: `<button class="btn btn-edit" data-type="staff" data-id="${row.staff_id}">Edit</button>`,
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
          actions: `<button class="btn btn-edit" data-type="staff" data-id="${row.staff_id}">Edit</button>`,
        }))
      : [])
  );
}

async function loadUsers() {
  try {
    const response = await fetch("../../api/admin_users.php");
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
  const response = await fetch("../../api/admin_users.php", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    const data = await response.json();
    throw new Error(data.error || "Update failed");
  }
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

  state.accountEditor = { type, id: Number(id) };

  if (type === "customer") {
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
  if (!(dialog instanceof HTMLDialogElement) || !state.accountEditor) return;

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
      await updateUser({ action: "update", type, id, fullName, email, phone, isActive: activeValue });
    }

    if (type === "barber") {
      const specialty = document.getElementById("ae-specialty")?.value?.trim() || "";
      const yearsExperience = Number(document.getElementById("ae-years")?.value ?? 0);
      const rating = Number(document.getElementById("ae-rating")?.value ?? 5);
      await updateUser({
        action: "update",
        type,
        id,
        fullName,
        email,
        specialty,
        yearsExperience,
        rating,
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

function renderServices() {
  const query = document.getElementById("services-search")?.value || "";
  const rows = filterRows(state.services, query, ["service_name", "category", "description"]);
  renderTable(
    "services-table",
    [
      { key: "service_name", label: "Service" },
      { key: "category", label: "Category" },
      { key: "base_duration", label: "Duration" },
      { key: "base_price", label: "Price" },
      { key: "is_active", label: "Active" },
      { key: "actions", label: "Actions" },
    ],
    rows.map((row) => ({
      ...row,
      actions: `<button class="btn btn-service" data-id="${row.service_id}">Edit</button>`,
    }))
  );
}

async function loadServices() {
  try {
    const response = await fetch("../../api/admin_services.php");
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    state.services = data.services ?? [];
  } catch (_) {
    state.services = [];
  }
  renderServices();
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
    const response = await fetch("../../api/admin_audit.php");
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

function inferActionFromInsight(text) {
  const source = String(text || "").toLowerCase();
  if (source.includes("promote") || source.includes("bundle") || source.includes("offer")) {
    return { label: "Open Services", action: "open-services" };
  }
  if (source.includes("rebook") || source.includes("reminder")) {
    return { label: "Open Users", action: "open-users" };
  }
  if (source.includes("barber") || source.includes("slots") || source.includes("queue")) {
    return { label: "Open Audit", action: "open-audit" };
  }
  if (source.includes("revenue") || source.includes("transactions")) {
    return { label: "Refresh Analytics", action: "refresh-analytics" };
  }
  return { label: "Review Analytics", action: "open-analytics" };
}

function renderAiActions(insights) {
  const container = document.getElementById("analytics-actions");
  const note = document.getElementById("analytics-action-note");
  if (!container) return;

  const enabled = new Set();
  insights.forEach((line) => {
    const option = inferActionFromInsight(line);
    enabled.add(option.action);
  });

  if (note) {
    note.textContent = enabled.size
      ? `AI recommended ${enabled.size} action${enabled.size > 1 ? "s" : ""}. Enabled buttons are ready to use.`
      : "No action is recommended right now. Buttons remain disabled until AI advises them.";
  }

  container.innerHTML = ACTION_CATALOG
    .map((option) => {
      const isEnabled = enabled.has(option.action);
      return `
        <div class="ai-action-item ${isEnabled ? "" : "is-disabled"}">
          <button class="btn ai-action" data-ai-action="${option.action}" ${isEnabled ? "" : "disabled"}>${option.label}</button>
          <div class="ai-action-desc">${option.description}</div>
        </div>
      `;
    })
    .join("");
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
    const response = await fetch("../../api/admin_analytics.php");
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    state.analytics = data.metrics ?? null;
    renderAnalyticsMetrics(data.metrics ?? null);
    renderAnalyticsCharts(data.metrics ?? null);
    await renderAiInsights(data.metrics ?? null, data.summary ?? "");
  } catch (_) {
    state.analytics = null;
    const summaryEl = document.getElementById("analytics-summary");
    if (summaryEl) summaryEl.textContent = "Failed to load AI summary.";
    const brief = document.getElementById("analytics-ai-brief");
    if (brief) brief.innerHTML = '<div class="ai-brief-item">AI insights are currently unavailable.</div>';
    renderAnalyticsMetrics(null);
    destroyAnalyticsCharts();
    renderAiActions([]);
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
    renderAiActions([...insights.suggestive, ...insights.predictive]);
  } catch (_) {
    const fallback = fallbackInsights(metrics);
    renderAiBrief(summary, fallback.suggestive, fallback.predictive);
    renderAiActions([...fallback.suggestive, ...fallback.predictive]);
  }
}

async function loadSettings() {
  try {
    const response = await fetch("../../api/admin_settings.php");
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    const settings = data.settings ?? {};
    document.getElementById("setting-email").checked = settings.emailNotificationsEnabled === 1;
    document.getElementById("setting-open").value = settings.openTime || "09:00";
    document.getElementById("setting-close").value = settings.closeTime || "18:00";
    document.getElementById("setting-mfa").checked = settings.forceMfa === 1;
    document.getElementById("setting-backup").checked = settings.autoBackupEnabled === 1;
  } catch (_) {
    // no-op
  }
}

async function refreshAll() {
  await Promise.all([
    loadDashboard(),
    loadUsers(),
    loadAudit(),
    loadAnalytics(),
    loadServices(),
    loadSettings(),
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

  if (target.classList.contains("btn-service")) {
    const id = target.dataset.id;
    if (!id) return;
    try {
      const serviceName = prompt("Service name:") ?? "";
      const description = prompt("Description:") ?? "";
      const baseDuration = prompt("Duration (minutes):", "30") ?? "30";
      const basePrice = prompt("Base price:", "0") ?? "0";
      const category = prompt("Category:", "Haircut") ?? "Haircut";
      const isActive = prompt("Active (1/0):", "1") ?? "1";
      const response = await fetch("../../api/admin_services.php", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "update",
          serviceID: Number(id),
          serviceName,
          description,
          baseDuration: Number(baseDuration),
          basePrice: Number(basePrice),
          category,
          isActive: Number(isActive),
        }),
      });
      if (!response.ok) {
        const data = await response.json();
        throw new Error(data.error || "Update failed");
      }
      toast("Service updated.");
      await loadServices();
    } catch (error) {
      toast(error.message || "Update failed");
    }
  }

  if (target.classList.contains("ai-action")) {
    const action = target.dataset.aiAction;
    if (!action) return;
    if (action === "open-services") showView("services");
    if (action === "open-users") showView("users");
    if (action === "open-audit") showView("audit");
    if (action === "open-analytics") showView("analytics");
    if (action === "refresh-analytics") {
      showView("analytics");
      await loadAnalytics();
      setLastUpdated();
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
      openTime: document.getElementById("setting-open").value,
      closeTime: document.getElementById("setting-close").value,
      forceMfa: document.getElementById("setting-mfa").checked ? 1 : 0,
      autoBackupEnabled: document.getElementById("setting-backup").checked ? 1 : 0,
    };
    const response = await fetch("../../api/admin_settings.php", {
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
      const response = await fetch("../../api/admin_settings.php", {
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
    const response = await fetch("../../api/admin_settings.php", {
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

document.getElementById("refresh-all")?.addEventListener("click", refreshAll);

document.getElementById("auto-refresh-toggle")?.addEventListener("change", (event) => {
  const enabled = Boolean(event.target.checked);
  if (state.autoRefreshTimer) {
    clearInterval(state.autoRefreshTimer);
    state.autoRefreshTimer = null;
  }
  if (enabled) {
    state.autoRefreshTimer = window.setInterval(() => {
      refreshAll();
    }, 30000);
  }
});

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
});

async function init() {
  if (!requireAdmin()) return;
  renderProfileChip();
  await refreshAll();
}

init();
>>>>>>> Stashed changes
