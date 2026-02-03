const views = {
  dashboard: document.getElementById("dashboard-view"),
  users: document.getElementById("users-view"),
  audit: document.getElementById("audit-view"),
  analytics: document.getElementById("analytics-view"),
  services: document.getElementById("services-view"),
  settings: document.getElementById("settings-view"),
};

const navButtons = document.querySelectorAll(".nav button");

navButtons.forEach((button) => {
  button.addEventListener("click", () => {
    const view = button.dataset.view;
    if (view === "logout") {
      sessionStorage.clear();
      window.location.href = "../login.html";
      return;
    }
    navButtons.forEach((b) => b.classList.remove("active"));
    button.classList.add("active");
    Object.values(views).forEach((section) => section.setAttribute("hidden", ""));
    if (views[view]) {
      views[view].removeAttribute("hidden");
    }
  });
});

function requireAdmin() {
  const rolesRaw = sessionStorage.getItem("roles");
  if (!rolesRaw) {
    window.location.href = "../login.html";
    return false;
  }

  const roles = JSON.parse(rolesRaw).map((role) => role.toLowerCase());
  if (!roles.includes("admin")) {
    window.location.href = "../login.html";
    return false;
  }

  return true;
}

function renderStats(stats) {
  const grid = document.getElementById("stats-grid");
  grid.innerHTML = "";
  if (!stats || stats.length === 0) {
    grid.innerHTML = "<div class=\"card\">No stats available.</div>";
    return;
  }
  stats.forEach((stat) => {
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `
      <h3>${stat.title}</h3>
      <div class="value">${stat.value}</div>
      <div class="meta ${stat.changeType}">${stat.change}</div>
    `;
    grid.appendChild(card);
  });
}

function renderActivities(activities) {
  const list = document.getElementById("activity-list");
  list.innerHTML = "";
  if (!activities || activities.length === 0) {
    list.innerHTML = "<div class=\"card\">No recent activity.</div>";
    return;
  }
  activities.forEach((activity) => {
    const item = document.createElement("div");
    item.className = "card gradient list-item";
    item.innerHTML = `
      <div class="icon-box">${activity.icon}</div>
      <div>
        <h4>${activity.title}</h4>
        <p>${activity.description}</p>
      </div>
      <div class="time">${activity.time}</div>
    `;
    list.appendChild(item);
  });
}

async function loadDashboard() {
  if (!requireAdmin()) return;
  try {
    const response = await fetch("../../api/admin_dashboard.php");
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    renderStats(data.stats ?? []);
    renderActivities(data.activities ?? []);
  } catch (error) {
    renderStats([]);
    renderActivities([]);
  }

  const now = new Date();
  const formatted = now.toLocaleString();
  document.getElementById("last-updated").textContent = formatted;
}

function renderTable(containerId, columns, rows) {
  const container = document.getElementById(containerId);
  if (!container) return;
  if (!rows || rows.length === 0) {
    container.innerHTML = "<div class=\"card\">No records found.</div>";
    return;
  }
  const header = `
    <div class="table-row table-header">
      ${columns.map((c) => `<div>${c.label}</div>`).join("")}
    </div>
  `;
  const body = rows
    .map(
      (row) => `
      <div class="table-row">
        ${columns.map((c) => `<div>${row[c.key] ?? "-"}</div>`).join("")}
      </div>
    `
    )
    .join("");
  container.innerHTML = header + body;
}

function renderUserTables(data) {
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
    (data.customers ?? []).map((row) => ({
      ...row,
      actions: `<button class="btn btn-edit" data-type="customer" data-id="${row.user_id}">Edit</button>`,
    }))
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
    (data.barbers ?? []).map((row) => ({
      ...row,
      actions: `<button class="btn btn-edit" data-type="barber" data-id="${row.barber_id}">Edit</button>`,
    }))
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
    (data.receptionists ?? []).map((row) => ({
      ...row,
      actions: `<button class="btn btn-edit" data-type="staff" data-id="${row.staff_id}">Edit</button>`,
    }))
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
    (data.admins ?? []).map((row) => ({
      ...row,
      actions: `<button class="btn btn-edit" data-type="staff" data-id="${row.staff_id}">Edit</button>`,
    }))
  );
}

async function loadUsers() {
  try {
    const response = await fetch("../../api/admin_users.php");
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    renderUserTables(data);
  } catch (error) {
    renderTable("customers-table", [], []);
    renderTable("barbers-table", [], []);
    renderTable("receptionists-table", [], []);
    renderTable("admins-table", [], []);
  }
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

document.addEventListener("click", async (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) return;
  if (!target.classList.contains("btn-edit")) return;

  const type = target.dataset.type;
  const id = target.dataset.id;
  if (!type || !id) return;

  try {
    if (type === "customer") {
      const fullName = prompt("Full name:") ?? "";
      const email = prompt("Email:") ?? "";
      const phone = prompt("Phone:") ?? "";
      const isActive = prompt("Active (1/0):", "1") ?? "1";
      await updateUser({ action: "update", type, id: Number(id), fullName, email, phone, isActive: Number(isActive) });
    }

    if (type === "barber") {
      const fullName = prompt("Full name:") ?? "";
      const email = prompt("Email:") ?? "";
      const specialty = prompt("Specialty:") ?? "";
      const yearsExperience = prompt("Years experience:", "0") ?? "0";
      const rating = prompt("Rating:", "5") ?? "5";
      const isActive = prompt("Active (1/0):", "1") ?? "1";
      await updateUser({
        action: "update",
        type,
        id: Number(id),
        fullName,
        email,
        specialty,
        yearsExperience: Number(yearsExperience),
        rating: Number(rating),
        isActive: Number(isActive),
      });
    }

    if (type === "staff") {
      const fullName = prompt("Full name:") ?? "";
      const email = prompt("Email:") ?? "";
      const role = prompt("Role (Admin/Receptionist):", "Receptionist") ?? "Receptionist";
      const isActive = prompt("Active (1/0):", "1") ?? "1";
      await updateUser({ action: "update", type, id: Number(id), fullName, email, role, isActive: Number(isActive) });
    }

    loadUsers();
  } catch (error) {
    alert(error.message || "Update failed");
  }
});

function renderServices(services) {
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
    (services ?? []).map((row) => ({
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
    renderServices(data.services ?? []);
  } catch (_) {
    renderServices([]);
  }
}

document.addEventListener("click", async (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) return;
  if (!target.classList.contains("btn-service")) return;
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
    loadServices();
  } catch (error) {
    alert(error.message || "Update failed");
  }
});

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
    // ignore
  }
}

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
    alert("Settings saved");
  } catch (error) {
    alert(error.message || "Save failed");
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
      alert(error.message || "Export failed");
    }
  });
});

document.getElementById("services-import")?.addEventListener("click", async () => {
  const input = document.getElementById("services-csv");
  if (!(input instanceof HTMLInputElement) || !input.files || input.files.length === 0) {
    alert("Select a CSV file first");
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
    alert("Import complete");
    loadServices();
  } catch (error) {
    alert(error.message || "Import failed");
  }
});

function renderAudit(events) {
  const list = document.getElementById("audit-list");
  if (!list) return;
  list.innerHTML = "";
  if (!events || events.length === 0) {
    list.innerHTML = '<div class="card">No audit events yet.</div>';
    return;
  }
  events.forEach((event) => {
    const item = document.createElement("div");
    item.className = "card gradient list-item";
    item.innerHTML = `
      <div class="icon-box">🧾</div>
      <div>
        <h4>${event.title}</h4>
        <p>${event.description}</p>
      </div>
      <div class="time">${event.time}</div>
    `;
    list.appendChild(item);
  });
}

async function loadAudit() {
  try {
    const response = await fetch("../../api/admin_audit.php");
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    renderAudit(data.events ?? []);
  } catch (error) {
    renderAudit([]);
  }
}

function renderAnalyticsMetrics(metrics) {
  const container = document.getElementById("analytics-metrics");
  if (!container) return;
  container.innerHTML = "";
  if (!metrics) {
    container.innerHTML = '<div class="card">No metrics available.</div>';
    return;
  }
  const items = [
    { title: "Total Users", value: metrics.totalUsers ?? 0 },
    { title: "Total Barbers", value: metrics.totalBarbers ?? 0 },
    { title: "Active Services", value: metrics.activeServices ?? 0 },
    { title: "Monthly Revenue", value: `₱${(metrics.monthlyRevenue ?? 0).toFixed(2)}` },
  ];
  items.forEach((stat) => {
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `
      <h3>${stat.title}</h3>
      <div class="value">${stat.value}</div>
    `;
    container.appendChild(card);
  });
}

async function loadAnalytics() {
  try {
    const response = await fetch("../../api/admin_analytics.php");
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    const summaryEl = document.getElementById("analytics-summary");
    if (summaryEl) summaryEl.textContent = data.summary ?? "No summary.";
    renderAnalyticsMetrics(data.metrics ?? null);
  } catch (error) {
    const summaryEl = document.getElementById("analytics-summary");
    if (summaryEl) summaryEl.textContent = "Failed to load AI summary.";
    renderAnalyticsMetrics(null);
  }
}

loadDashboard();
loadUsers();
loadAudit();
loadAnalytics();
loadServices();
loadSettings();
