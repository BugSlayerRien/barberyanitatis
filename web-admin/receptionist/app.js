const views = {
  dashboard: document.getElementById("dashboard-view"),
  tracking: document.getElementById("tracking-view"),
  barbers: document.getElementById("barbers-view"),
};

const state = {
  appointments: [],
  walkins: [],
  currentUser: null,
  profileEditMode: false,
  autoRefreshTimer: null,
  pagination: {},
};

const DEFAULT_PAGE_SIZE = 8;
const PAGE_SIZE_BY_KEY = {
  "appointments-table": 8,
  "walkins-table": 8,
  "tracking-regular-list": 6,
  "tracking-exclusive-list": 6,
  "barbers-regular-list": 6,
  "barbers-exclusive-list": 6,
};

const navButtons = document.querySelectorAll(".nav button");
function apiUrl(fileName) {
  return resolveApiUrl(fileName);
}
const refreshButton = document.getElementById("refresh-dashboard");
const walkinForm = document.getElementById("walkin-form");
const walkinError = document.getElementById("walkin-error");
const walkinServices = document.getElementById("walkin-services");
const walkinBarber = document.getElementById("walkin-barber");
const appointmentsSearch = document.getElementById("appointments-search");
const appointmentsStatusFilter = document.getElementById("appointments-status-filter");
const walkinsSearch = document.getElementById("walkins-search");
const autoRefreshToggle = document.getElementById("auto-refresh-toggle");

function showView(view) {
  navButtons.forEach((button) => button.classList.toggle("active", button.dataset.view === view));
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

function formatCurrency(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) return "-";
  return `PHP ${Number(value).toFixed(2)}`;
}

async function postJson(url, payload) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error || "Request failed");
  }
  return data;
}

function requireReceptionist() {
  const rolesRaw = sessionStorage.getItem("roles");
  if (!rolesRaw) {
    window.location.href = "../login.html";
    return false;
  }

  const roles = JSON.parse(rolesRaw).map((role) => role.toLowerCase());
  if (!roles.includes("receptionist") && !roles.includes("admin")) {
    window.location.href = "../login.html";
    return false;
  }

  return true;
}

function getStoredUser() {
  try {
    const userRaw = sessionStorage.getItem("user");
    const rolesRaw = sessionStorage.getItem("roles");
    const user = userRaw ? JSON.parse(userRaw) : {};
    const roles = rolesRaw ? JSON.parse(rolesRaw) : [];
    const fullName = user.fullName || user.full_name || user.name || "Receptionist";
    const email = user.email || "-";
    const role = roles.length ? String(roles[0]) : "Receptionist";
    const id = user.userID || user.user_id || user.staff_id || "-";
    return { fullName, email, role, id };
  } catch (_) {
    return { fullName: "Receptionist", email: "-", role: "Receptionist", id: "-" };
  }
}

function renderProfileChip() {
  state.currentUser = getStoredUser();
  const initialEl = document.getElementById("profile-avatar-initial");
  const nameEl = document.getElementById("profile-avatar-name");
  if (initialEl) {
    initialEl.textContent = String(state.currentUser.fullName || "R").trim().charAt(0).toUpperCase() || "R";
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
    alert("Name and email are required.");
    return;
  }

  const profile = state.currentUser || getStoredUser();
  try {
    const data = await postJson(apiUrl("staff_profile.php"), {
      action: "updateProfile",
      staffID: Number(profile.id),
      fullName,
      email,
      role: String(profile.role || "receptionist").toLowerCase(),
    });

    if (data?.user) {
      sessionStorage.setItem("user", JSON.stringify(data.user));
      if (Array.isArray(data.user.roles)) {
        sessionStorage.setItem("roles", JSON.stringify(data.user.roles));
      }
    }

    renderProfileChip();
    state.profileEditMode = false;
    renderProfileDialogContent();
    alert("Profile updated.");
  } catch (error) {
    alert(error.message || "Profile update failed");
  }
}

function renderStats(stats) {
  const grid = document.getElementById("analytics-stats");
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
      <div class="meta ${stat.changeType ?? ""}">${stat.change}</div>
    `;
    grid.appendChild(card);
  });
}

function renderSummary(stats, appointments, walkins) {
  const summaryEl = document.getElementById("summary-text");
  if (!summaryEl) return;
  if (!stats || stats.length === 0) {
    summaryEl.textContent = "No summary available.";
    return;
  }
  const statMap = Object.fromEntries(stats.map((item) => [item.title, item.value]));
  const totalAppointments = appointments?.length ?? 0;
  const totalWalkins = walkins?.length ?? 0;
  summaryEl.textContent = `Walk-ins: ${statMap["Walk-ins"] ?? totalWalkins} • Appointments: ${statMap["Appointments"] ?? totalAppointments} • In Progress: ${statMap["In Progress"] ?? 0} • Available Barbers: ${statMap["Available Barbers"] ?? 0}`;
}

function statusTag(status) {
  const lower = String(status).toLowerCase();
  if (["completed"].includes(lower)) return "success";
  if (["inprogress"].includes(lower)) return "warning";
  if (["checkedin", "scheduled", "assigned", "waiting"].includes(lower)) return "info";
  if (["cancelled", "noshow"].includes(lower)) return "warning";
  return "info";
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

function paginationMarkup(key, currentPage, totalPages, colspan) {
  if (totalPages <= 1) {
    return "";
  }

  const numbers = getVisiblePages(currentPage, totalPages)
    .map((page) => `
      <button
        class="btn secondary pager-btn${page === currentPage ? " is-active" : ""}"
        data-page-key="${key}"
        data-page="${page}"
        ${page === currentPage ? "disabled" : ""}
      >${page}</button>
    `)
    .join("");

  const pager = `
    <div class="pager">
      <button class="btn secondary pager-btn" data-page-key="${key}" data-page="${currentPage - 1}" ${currentPage <= 1 ? "disabled" : ""}>Previous</button>
      <div class="pager-numbers">${numbers}</div>
      <button class="btn secondary pager-btn" data-page-key="${key}" data-page="${currentPage + 1}" ${currentPage >= totalPages ? "disabled" : ""}>Next</button>
    </div>
  `;

  if (typeof colspan === "number" && colspan > 0) {
    return `
      <tfoot>
        <tr>
          <td colspan="${colspan}">${pager}</td>
        </tr>
      </tfoot>
    `;
  }

  return pager;
}

function rerenderByPaginationKey(key) {
  if (key === "appointments-table") {
    renderAppointments(state.appointments);
    return;
  }
  if (key === "walkins-table") {
    renderWalkins(state.walkins);
    return;
  }
  if (key === "tracking-regular-list" || key === "tracking-exclusive-list") {
    renderSplitTracking(state.appointments, state.walkins);
    return;
  }
  if (key === "barbers-regular-list" || key === "barbers-exclusive-list") {
    renderSplitBarbers(window.__barbersCache || []);
  }
}

function normalizeBarberChannel(channel) {
  const value = String(channel || "appointment").toLowerCase();
  if (value === "walk_in" || value === "walkin" || value === "regular") {
    return "walk_in";
  }
  return "appointment";
}

function mapBarberCards(barbers, channel) {
  return (barbers || [])
    .filter((barber) => normalizeBarberChannel(barber.barber_channel) === channel)
    .map((barber) => ({
      name: barber.full_name,
      specialty: barber.specialty ?? "N/A",
      rating: barber.rating ?? "-",
      experience: barber.years_experience ? `${barber.years_experience} yrs` : "N/A",
      channelLabel: channel === "walk_in" ? "Regular" : "Exclusive",
    }));
}

function parseAppointmentDateTime(item) {
  const date = String(item.appointment_date || "").trim();
  const time = String(item.time || item.start_time || "").trim();
  if (!date || !time) return null;
  const normalized = time.length === 5 ? `${time}:00` : time;
  const parsed = new Date(`${date}T${normalized}`);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function buildTracking(appointments, walkins) {
  const now = new Date();
  const items = [];

  (appointments || []).forEach((item) => {
    const status = String(item.status || "Scheduled");
    if (["Cancelled", "NoShow", "Completed"].includes(status)) {
      return;
    }

    if (status === "PendingPayment") {
      const displaySchedule = item.time_range
        ? `${formatScheduleLabel(item.appointment_date, "")} • ${item.time_range}`
        : formatScheduleLabel(item.appointment_date, item.time);
      items.push({
        kind: "appointment",
        appointmentId: item.appointment_id,
        name: item.name,
        memberLabel: item.member_label || item.name,
        isGroup: item.is_group === true,
        peopleCount: item.people_count || 1,
        service: item.service,
        barber: item.barber || "",
        schedule: displaySchedule,
        status: "PENDING PAYMENT",
        progress: 0.12,
        timeRemaining: "Awaiting payment",
        color: "#FF9800",
      });
      return;
    }

    const start = parseAppointmentDateTime(item);
    let displayStatus = "WAITING";
    let progress = 0;
    let timeRemaining = "Upcoming";

    if (status === "InProgress" || status === "CheckedIn") {
      displayStatus = "IN PROGRESS";
      progress = status === "InProgress" ? 0.75 : 0.35;
      timeRemaining = "In service";
    } else if (start) {
      const end = new Date(start.getTime() + 60 * 60 * 1000);
      if (now >= start && now < end) {
        displayStatus = "IN PROGRESS";
        progress = Math.min(0.95, (now - start) / (60 * 60 * 1000));
        const mins = Math.max(0, Math.ceil((end - now) / 60000));
        timeRemaining = `${mins} min remaining`;
      } else if (now >= end) {
        displayStatus = "COMPLETING";
        progress = 1;
        timeRemaining = "Auto-completing";
      }
    }

    const schedule = item.time_range
      ? `${formatScheduleLabel(item.appointment_date, "")} • ${item.time_range}`
      : formatScheduleLabel(item.appointment_date, item.time);
    items.push({
      kind: "appointment",
      appointmentId: item.appointment_id,
      name: item.name,
      memberLabel: item.member_label || item.name,
      isGroup: item.is_group === true,
      peopleCount: item.people_count || 1,
      service: item.service,
      barber: item.barber || "",
      schedule,
      status: displayStatus,
      progress,
      timeRemaining,
      color: displayStatus === "IN PROGRESS" ? "#4CAF50" : "#2196F3",
    });
  });

  (walkins || []).forEach((item) => {
    const status = String(item.status || "Waiting");
    let displayStatus = "WAITING";
    let progress = 0;
    if (status === "InProgress") {
      displayStatus = "IN PROGRESS";
      progress = 0.65;
    } else if (status === "Completed") {
      displayStatus = "COMPLETED";
      progress = 1;
    }

    items.push({
      kind: "walkin",
      queueId: item.queue_id,
      name: item.name,
      service: item.service || "Walk-in",
      barber: item.barber || "",
      schedule: `Walk-in • ${item.waitTime || "Today"}`,
      status: displayStatus,
      progress,
      timeRemaining: status === "Completed" ? "Completed" : item.waitTime || "Waiting",
      color: displayStatus === "IN PROGRESS" ? "#4CAF50" : "#2196F3",
    });
  });

  return items;
}

function formatScheduleLabel(dateValue, timeValue) {
  const date = String(dateValue || "").trim();
  const time = String(timeValue || "").trim();
  if (!date) {
    return time ? formatTime12(time) : "Schedule TBD";
  }
  const parsed = new Date(`${date}T00:00:00`);
  const dateLabel = Number.isNaN(parsed.getTime())
    ? date
    : `${parsed.getMonth() + 1}/${parsed.getDate()}/${parsed.getFullYear()}`;
  return time ? `${dateLabel} • ${formatTime12(time)}` : dateLabel;
}

function formatTime12(timeValue) {
  const parts = String(timeValue).split(":");
  if (parts.length < 2) {
    return timeValue;
  }
  const hour = Number(parts[0]);
  const minute = Number(parts[1]);
  if (!Number.isFinite(hour) || !Number.isFinite(minute)) {
    return timeValue;
  }
  const suffix = hour >= 12 ? "PM" : "AM";
  const hour12 = hour % 12 === 0 ? 12 : hour % 12;
  return `${hour12}:${String(minute).padStart(2, "0")} ${suffix}`;
}

async function confirmAction(message) {
  return window.confirm(message);
}

function renderAppointments(appointments) {
  const table = document.getElementById("appointments-table");
  if (!table) return;
  const q = (appointmentsSearch?.value || "").trim().toLowerCase();
  const statusFilter = appointmentsStatusFilter?.value || "all";
  const filtered = (appointments || []).filter((item) => {
    const textMatch = !q
      || String(item.name).toLowerCase().includes(q)
      || String(item.service).toLowerCase().includes(q)
      || String(item.barber).toLowerCase().includes(q);
    const statusMatch = statusFilter === "all" || item.status === statusFilter;
    return textMatch && statusMatch;
  });

  if (!filtered.length) {
    table.innerHTML = "<tr><td>No appointments today.</td></tr>";
    return;
  }

  const paged = paginateRows("appointments-table", filtered);

  table.innerHTML = `
    <thead>
      <tr>
        <th>Client</th>
        <th>Service</th>
        <th>Time</th>
        <th>Duration</th>
        <th>Price</th>
        <th>Status</th>
        <th>Barber</th>
      </tr>
    </thead>
    <tbody>
      ${paged.items
        .map(
          (item) => `
            <tr>
              <td>${item.name}${item.is_group ? ` <span class="tag info">Group · ${item.people_count || 1}</span>` : ""}</td>
              <td>${item.service}</td>
              <td>${item.time_range || item.time}</td>
              <td>${item.duration}</td>
              <td>${item.price}</td>
              <td><span class="tag ${item.status === "Completed" ? "success" : item.status === "Scheduled" ? "info" : "warning"}">${item.status}</span></td>
              <td>${item.barber}</td>
            </tr>
          `,
        )
        .join("")}
    </tbody>
    ${paginationMarkup("appointments-table", paged.currentPage, paged.totalPages, 8)}
  `;
}

function renderWalkins(walkins) {
  const table = document.getElementById("walkins-table");
  if (!table) return;
  const q = (walkinsSearch?.value || "").trim().toLowerCase();
  const filtered = (walkins || []).filter((item) => {
    if (!q) return true;
    return (
      String(item.name).toLowerCase().includes(q)
      || String(item.service).toLowerCase().includes(q)
      || String(item.status).toLowerCase().includes(q)
      || String(item.queue_number || "").toLowerCase().includes(q)
    );
  });

  if (!filtered.length) {
    table.innerHTML = "<tr><td>No walk-ins yet.</td></tr>";
    return;
  }

  const paged = paginateRows("walkins-table", filtered);

  table.innerHTML = `
    <thead>
      <tr>
        <th>Client</th>
        <th>Service</th>
        <th>Wait Time</th>
        <th>Status</th>
      </tr>
    </thead>
    <tbody>
      ${paged.items
        .map(
          (item) => `
            <tr>
              <td>${item.name}</td>
              <td>${item.service}</td>
              <td>${item.waitTime}</td>
              <td><span class="tag ${item.status === "Completed" ? "success" : item.status === "InService" ? "warning" : "info"}">${item.status}</span></td>
            </tr>
          `,
        )
        .join("")}
    </tbody>
    ${paginationMarkup("walkins-table", paged.currentPage, paged.totalPages, 6)}
  `;
}

function renderTracking(items, listId) {
  const list = document.getElementById(listId);
  if (!list) return;
  list.innerHTML = "";
  if (!items || !items.length) {
    list.innerHTML = '<div class="card">No clients in this queue.</div>';
    return;
  }

  const paged = paginateRows(listId, items);
  paged.items.forEach((item) => {
    const card = document.createElement("div");
    card.className = "card";
    const pct = Math.round((item.progress || 0) * 100);
    const canAct = item.status !== "COMPLETED";
    card.innerHTML = `
      <div class="row-wrap" style="justify-content: space-between; align-items: flex-start;">
        <div>
          <h4 style="margin: 0 0 4px;">${item.name}${item.isGroup ? ` <span class="tag info" style="margin-left:6px;">Group · ${item.peopleCount}</span>` : ""}</h4>
          <p style="margin: 0 0 4px;">${item.service}</p>
          <p class="meta" style="margin: 0 0 4px; color: #c9b46a;">${item.schedule || ""}</p>
          ${item.barber ? `<p class="meta" style="margin: 0;">Barber: ${item.barber}</p>` : ""}
        </div>
        <span class="tag ${
          item.status === "WAITING"
            ? "info"
            : item.status === "IN PROGRESS"
              ? "success"
              : item.status === "PENDING PAYMENT"
                ? "warning"
                : "warning"
        }">${item.status}</span>
      </div>
      <div class="progress" style="margin-top: 10px; height: 8px;">
        <span style="width: ${pct}%; background: ${item.color};"></span>
      </div>
      <div class="row-wrap" style="margin-top: 6px; justify-content: space-between; align-items: center;">
        <span class="meta">${item.timeRemaining}${item.status === "IN PROGRESS" && pct > 0 ? ` • ${pct}%` : ""}</span>
        ${canAct ? `
          <div class="row-wrap" style="gap: 6px;">
            <button type="button" class="btn secondary tracking-complete" title="Mark completed"
              data-kind="${item.kind}" data-appointment-id="${item.appointmentId || ""}" data-queue-id="${item.queueId || ""}" data-name="${item.name}">✓ Complete</button>
            <button type="button" class="btn secondary tracking-cancel" title="Cancel / remove"
              data-kind="${item.kind}" data-appointment-id="${item.appointmentId || ""}" data-queue-id="${item.queueId || ""}" data-name="${item.name}">✕ Cancel</button>
          </div>
        ` : ""}
      </div>
    `;
    list.appendChild(card);
  });

  const pager = paginationMarkup(listId, paged.currentPage, paged.totalPages);
  if (pager) {
    list.insertAdjacentHTML("beforeend", pager);
  }
}

function renderSplitTracking(appointments, walkins) {
  const tracking = buildTracking(appointments, walkins);
  renderTracking(tracking.filter((item) => item.kind === "walkin"), "tracking-regular-list");
  renderTracking(tracking.filter((item) => item.kind === "appointment"), "tracking-exclusive-list");
}

function renderBarbers(items, listId) {
  const list = document.getElementById(listId);
  if (!list) return;
  list.innerHTML = "";
  if (!items || !items.length) {
    list.innerHTML = "<div class=\"card\">No barbers in this group.</div>";
    return;
  }

  const paged = paginateRows(listId, items);
  paged.items.forEach((item) => {
    const card = document.createElement("div");
    card.className = "card gradient";
    card.innerHTML = `
      <h4>${item.name}</h4>
      <p>${item.specialty}</p>
      <div class="meta">${item.channelLabel || ""}</div>
      <div class="meta">Rating: ${item.rating}</div>
      <div class="meta">Experience: ${item.experience}</div>
    `;
    list.appendChild(card);
  });

  const pager = paginationMarkup(listId, paged.currentPage, paged.totalPages);
  if (pager) {
    list.insertAdjacentHTML("beforeend", pager);
  }
}

function renderSplitBarbers(barbers) {
  renderBarbers(mapBarberCards(barbers, "walk_in"), "barbers-regular-list");
  renderBarbers(mapBarberCards(barbers, "appointment"), "barbers-exclusive-list");
}

async function loadOptions() {
  try {
    const [servicesResponse, barbersResponse] = await Promise.all([
      postJson(apiUrl("services.php"), { action: "list", channel: "walk_in" }),
      postJson(apiUrl("barbers.php"), { action: "list", channel: "all" }),
    ]);

    const services = servicesResponse.services ?? [];
    const barbers = barbersResponse.barbers ?? [];

    if (walkinServices) {
      walkinServices.innerHTML = services
        .map((service) => `<option value="${service.service_id}">${service.service_name}</option>`)
        .join("");
    }

    if (walkinBarber) {
      const currentValue = walkinBarber.value;
      walkinBarber.innerHTML = '<option value="">Unassigned</option>';
      walkinBarber.innerHTML += barbers
        .map((barber) => `<option value="${barber.barber_id}">${barber.full_name}</option>`)
        .join("");
      if (currentValue) {
        walkinBarber.value = currentValue;
      }
    }

    window.__barbersCache = barbers;
    renderSplitBarbers(barbers);
    await loadBarberUnavailabilityRequests();
  } catch (error) {
    window.__barbersCache = [];
    renderSplitBarbers([]);
  }
}

async function loadBarberUnavailabilityRequests() {
  const list = document.getElementById("barber-unavailability-list");
  if (!list) return;

  try {
    const data = await postJson(apiUrl("barber_schedule.php"), { action: "listRequests", status: "Pending" });
    const rows = data.requests ?? [];
    if (!rows.length) {
      list.innerHTML = '<div class="card">No pending requests.</div>';
      return;
    }

    list.innerHTML = "";
    rows.forEach((row) => {
      const card = document.createElement("div");
      card.className = "card";
      card.innerHTML = `
        <h4>${row.barber_name ?? "Barber"}</h4>
        <p>Date: ${row.request_date}</p>
        <p>${row.note ?? ""}</p>
        <div class="row-wrap">
          <button class="btn" data-approve="${row.request_id}" type="button">Approve</button>
          <button class="btn secondary" data-reject="${row.request_id}" type="button">Reject</button>
        </div>
      `;
      list.appendChild(card);
    });

    list.querySelectorAll("[data-approve]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = Number(btn.getAttribute("data-approve"));
        await postJson(apiUrl("barber_schedule.php"), { action: "reviewRequest", requestID: id, decision: "Approved" });
        await loadBarberUnavailabilityRequests();
      });
    });
    list.querySelectorAll("[data-reject]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = Number(btn.getAttribute("data-reject"));
        await postJson(apiUrl("barber_schedule.php"), { action: "reviewRequest", requestID: id, decision: "Rejected" });
        await loadBarberUnavailabilityRequests();
      });
    });
  } catch (error) {
    list.innerHTML = '<div class="card">Could not load time-off requests.</div>';
  }
}

async function loadDashboard() {
  if (!requireReceptionist()) return;
  try {
    const data = await postJson(apiUrl("receptionist.php"), { action: "dashboard" });
    state.appointments = data.appointments ?? [];
    state.walkins = data.walkins ?? [];
    renderStats(data.stats ?? []);
    renderAppointments(state.appointments);
    renderWalkins(state.walkins);
    renderSplitTracking(state.appointments, state.walkins);
    renderSummary(data.stats ?? [], state.appointments, state.walkins);
  } catch (error) {
    state.appointments = [];
    state.walkins = [];
    renderStats([]);
    renderAppointments([]);
    renderWalkins([]);
    renderSplitTracking([], []);
    renderSplitBarbers([]);
  }

  document.getElementById("last-updated").textContent = new Date().toLocaleString();
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

function exportAppointmentsCsv() {
  const exportRows = state.appointments.map((item) => ({
    client: item.name,
    service: item.service,
    time: item.time,
    duration: item.duration,
    price: item.price,
    status: item.status,
    barber: item.barber,
  }));
  const blob = new Blob([toCsv(exportRows)], { type: "text/csv" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "appointments-today.csv";
  a.click();
  URL.revokeObjectURL(url);
}

async function refreshAll() {
  await loadDashboard();
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

  if (target.id === "profile-dialog-edit") {
    state.profileEditMode = true;
    renderProfileDialogContent();
    return;
  }

  if (target.id === "profile-dialog-save") {
    await saveProfileEdits();
    return;
  }

  if (target.id === "profile-dialog-cancel") {
    state.profileEditMode = false;
    renderProfileDialogContent();
    return;
  }

  if (target.classList.contains("tracking-complete")) {
    const name = target.dataset.name || "this client";
    const kind = target.dataset.kind || "appointment";
    const appointmentId = Number(target.dataset.appointmentId || "0");
    const queueId = Number(target.dataset.queueId || "0");
    const ok = await confirmAction(`Mark ${name} as completed?`);
    if (!ok) return;
    try {
      if (kind === "walkin" && queueId > 0) {
        await postJson(apiUrl("receptionist.php"), {
          action: "updateWalkinStatus",
          queueID: queueId,
          status: "Completed",
        });
      } else if (appointmentId > 0) {
        await postJson(apiUrl("receptionist.php"), {
          action: "updateAppointmentStatus",
          appointmentID: appointmentId,
          status: "Completed",
        });
      }
      loadDashboard();
    } catch (error) {
      alert(error.message || "Unable to complete");
    }
    return;
  }

  if (target.classList.contains("tracking-cancel")) {
    const name = target.dataset.name || "this client";
    const kind = target.dataset.kind || "appointment";
    const appointmentId = Number(target.dataset.appointmentId || "0");
    const queueId = Number(target.dataset.queueId || "0");
    const ok = await confirmAction(`Cancel ${name} and remove from tracking?`);
    if (!ok) return;
    try {
      if (kind === "walkin" && queueId > 0) {
        await postJson(apiUrl("receptionist.php"), {
          action: "updateWalkinStatus",
          queueID: queueId,
          status: "Cancelled",
        });
      } else if (appointmentId > 0) {
        await postJson(apiUrl("receptionist.php"), {
          action: "updateAppointmentStatus",
          appointmentID: appointmentId,
          status: "Cancelled",
        });
      }
      loadDashboard();
    } catch (error) {
      alert(error.message || "Unable to cancel");
    }
    return;
  }

  const appointmentId = target.dataset.appointmentId;
  const appointmentStatus = target.dataset.status;
  if (appointmentId && appointmentStatus) {
    try {
      await postJson(apiUrl("receptionist.php"), {
        action: "updateAppointmentStatus",
        appointmentID: Number(appointmentId),
        status: appointmentStatus,
      });
      loadDashboard();
    } catch (error) {
      alert(error.message || "Unable to update appointment");
    }
    return;
  }

  const walkinId = target.dataset.walkinId;
  const walkinStatus = target.dataset.walkinStatus;
  const walkinAction = target.dataset.walkinAction;
  if (walkinId && (walkinStatus || walkinAction)) {
    try {
      let status = walkinStatus;
      let barberID = 0;
      if (walkinAction === "assign") {
        const select = document.querySelector(`[data-walkin-barber="${walkinId}"]`);
        barberID = select ? Number(select.value) : 0;
        status = barberID > 0 ? "Assigned" : "Waiting";
      }

      await postJson(apiUrl("receptionist.php"), {
        action: "updateWalkinStatus",
        queueID: Number(walkinId),
        status,
        barberID,
      });
      loadDashboard();
    } catch (error) {
      alert(error.message || "Unable to update walk-in");
    }
  }
});

walkinForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  walkinError.textContent = "";

  const serviceIDs = Array.from(walkinServices.selectedOptions).map((option) => option.value);
  const barberID = walkinBarber.value ? Number(walkinBarber.value) : 0;

  try {
    await postJson(apiUrl("receptionist.php"), {
      action: "createWalkin",
      serviceIDs,
      barberID,
    });
    walkinForm.reset();
    loadDashboard();
  } catch (error) {
    walkinError.textContent = error.message || "Unable to add walk-in.";
  }
});

refreshButton?.addEventListener("click", () => refreshAll());

appointmentsSearch?.addEventListener("input", () => {
  resetPagination(["appointments-table"]);
  renderAppointments(state.appointments);
});
appointmentsStatusFilter?.addEventListener("change", () => {
  resetPagination(["appointments-table"]);
  renderAppointments(state.appointments);
});
walkinsSearch?.addEventListener("input", () => {
  resetPagination(["walkins-table"]);
  renderWalkins(state.walkins);
});

document.getElementById("appointments-export")?.addEventListener("click", exportAppointmentsCsv);
document.getElementById("profile-avatar-btn")?.addEventListener("click", openProfileDialog);
document.getElementById("profile-dialog-close")?.addEventListener("click", () => {
  const dialog = document.getElementById("profile-dialog");
  if (dialog instanceof HTMLDialogElement) dialog.close();
});

autoRefreshToggle?.addEventListener("change", (event) => {
  const enabled = Boolean(event.target.checked);
  if (state.autoRefreshTimer) {
    clearInterval(state.autoRefreshTimer);
    state.autoRefreshTimer = null;
  }
  if (enabled) {
    state.autoRefreshTimer = window.setInterval(refreshAll, 30000);
  }
});

async function init() {
  if (!requireReceptionist()) return;
  showView("dashboard");
  renderProfileChip();
  await loadOptions();
  await refreshAll();
}

init();
