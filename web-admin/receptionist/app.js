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
  pagination: {},
  leaveCalendar: null,
  scheduleCalendar: null,
  leaveCalSelected: null,
  leaveCalBarberId: "",
};

const DEFAULT_PAGE_SIZE = 5;
const PAGE_SIZE_BY_KEY = {
  "appointments-table": 5,
  "walkins-table": 5,
  "tracking-regular-list": 5,
  "tracking-exclusive-list": 5,
  "barbers-regular-list": 9,
  "barbers-exclusive-list": 9,
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

const ui = () => window.PortalUi;
const toast = (message, type = "info") => ui()?.toast(message, type);
const confirmAction = (message, options = {}) =>
  ui()?.confirmDialog({
    title: options.title || "Confirm",
    message,
    confirmLabel: options.confirmLabel || "Confirm",
    cancelLabel: options.cancelLabel || "Cancel",
    danger: Boolean(options.danger),
  }) ?? Promise.resolve(false);

async function runWithLoading(message, fn) {
  if (ui()?.runWithLoading) return ui().runWithLoading(message, fn);
  return fn();
}

async function withButtonLoading(button, fn, options = {}) {
  if (ui()?.withButtonLoading) return ui().withButtonLoading(button, fn, options);
  return fn();
}

function setRegionLoading(element, isLoading, message) {
  ui()?.setRegionLoading?.(element, isLoading, message);
}

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
    if (view === "barbers") {
      loadBarberUnavailabilityRequests();
    }
  });
});

function formatCurrency(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) return "-";
  return `PHP ${Number(value).toFixed(2)}`;
}

function localTodayYmd() {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, "0");
  const d = String(now.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

async function postJson(url, payload, loadingMessage = false) {
  if (ui()?.fetchJson) {
    return ui().fetchJson(url, payload, loadingMessage);
  }
  const doFetch = typeof fetchWithRetry === "function" ? fetchWithRetry : fetch;
  const response = await doFetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const raw = await response.text();
  const data = raw ? JSON.parse(raw) : {};
  if (!response.ok) {
    const detail = data.details ? ` (${data.details})` : "";
    throw new Error((data.error || "Request failed") + detail);
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
    toast("Name and email are required.", "error");
    return;
  }

  const profile = state.currentUser || getStoredUser();
  const saveBtn = document.getElementById("profile-dialog-save");
  await withButtonLoading(saveBtn, async () => {
    try {
      const data = await postJson(
        apiUrl("staff_profile.php"),
        {
          action: "updateProfile",
          staffID: Number(profile.id),
          fullName,
          email,
          role: String(profile.role || "receptionist").toLowerCase(),
        },
        "Saving profile...",
      );

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
  }, { label: "Saving..." });
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
  if (value === "appointment" || value === "appointments" || value === "exclusive") {
    return "appointment";
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

function parsePersistedTimestamp(raw) {
  if (!raw) return null;
  const normalized = String(raw).trim().replace(" ", "T");
  if (!normalized) return null;
  const parsed = new Date(normalized);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function estimatedMinutesOf(item, fallbackMinutes) {
  const n = Number(item.estimated_minutes);
  if (Number.isFinite(n) && n > 0) return n;
  const fromDuration = parseInt(String(item.duration || ""), 10);
  if (Number.isFinite(fromDuration) && fromDuration > 0) return fromDuration;
  return fallbackMinutes;
}

function estimatedTimeProgress(start, estimatedMinutes, now) {
  const totalSeconds = Math.max(1, estimatedMinutes) * 60;
  const elapsedSeconds = Math.max(0, (now.getTime() - start.getTime()) / 1000);
  const ratio = elapsedSeconds / totalSeconds;
  const overtime = ratio >= 1;
  const remainingMins = Math.max(0, Math.ceil((totalSeconds - elapsedSeconds) / 60));
  return {
    progress: Math.min(1, Math.max(0, ratio)),
    overtime,
    timeRemaining: overtime ? "Auto-completing" : `${remainingMins} min remaining`,
  };
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
        rawStatus: status,
        progress: 0.12,
        timeRemaining: "Awaiting payment",
        color: "#FF9800",
      });
      return;
    }

    let displayStatus = "WAITING";
    let progress = 0;
    let timeRemaining = status === "CheckedIn" ? "Checked in" : "Upcoming";
    let color = "#2196F3";

    if (status === "InProgress") {
      const start = parsePersistedTimestamp(item.checkin_time);
      const estimatedMinutes = estimatedMinutesOf(item, 60);
      displayStatus = "IN PROGRESS";
      color = "#4CAF50";
      if (start) {
        const timed = estimatedTimeProgress(start, estimatedMinutes, now);
        progress = timed.progress;
        timeRemaining = timed.timeRemaining;
        if (timed.overtime) {
          displayStatus = "COMPLETING";
          color = "#FF9800";
        }
      } else {
        timeRemaining = "In service";
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
      rawStatus: status,
      progress,
      timeRemaining,
      color,
    });
  });

  (walkins || []).forEach((item) => {
    const status = String(item.status || "Waiting");
    if (status === "Cancelled" || status === "Completed") {
      return;
    }

    let displayStatus = "WAITING";
    let progress = 0;
    let timeRemaining = item.waitTime || "Waiting";
    let color = "#2196F3";

    if (status === "InProgress") {
      displayStatus = "IN PROGRESS";
      color = "#4CAF50";
      const serviceStart = parsePersistedTimestamp(item.actual_start);
      const estimatedMinutes = estimatedMinutesOf(item, 35);
      if (serviceStart) {
        const timed = estimatedTimeProgress(serviceStart, estimatedMinutes, now);
        progress = timed.progress;
        timeRemaining = timed.timeRemaining;
        if (timed.overtime) {
          displayStatus = "COMPLETING";
          color = "#FF9800";
        }
      } else {
        timeRemaining = "In service";
      }
    } else if (status === "Assigned") {
      displayStatus = "READY";
      timeRemaining = "Ready — starts automatically";
    }

    const queueLabel = item.queue_number ? String(item.queue_number) : "";
    const waitLabel = item.waitTime || "Waiting";

    items.push({
      kind: "walkin",
      queueId: item.queue_id,
      queueNumber: queueLabel,
      rawStatus: status,
      name: item.name,
      service: item.service || "Walk-in",
      barber: item.barber || "",
      schedule: queueLabel
        ? `Queue ${queueLabel} • ${waitLabel}`
        : `Walk-in • ${waitLabel}`,
      status: displayStatus,
      progress,
      timeRemaining,
      color,
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

function renderAppointments(appointments) {
  const table = document.getElementById("appointments-table");
  if (!table) return;
  const q = (appointmentsSearch?.value || "").trim().toLowerCase();
  const statusFilter = appointmentsStatusFilter?.value || "all";
  const today = localTodayYmd();
  const filtered = (appointments || []).filter((item) => {
    const dateStr = String(item.appointment_date || "").slice(0, 10);
    if (dateStr !== today) return false;
    const textMatch = !q
      || String(item.name).toLowerCase().includes(q)
      || String(item.service).toLowerCase().includes(q)
      || String(item.barber).toLowerCase().includes(q);
    const statusMatch = statusFilter === "all" || item.status === statusFilter;
    return textMatch && statusMatch;
  });

  if (!filtered.length) {
    table.innerHTML = "<tr><td colspan=\"7\">No appointments for today.</td></tr>";
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
        <th>Queue</th>
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
              <td>${item.queue_number || "—"}</td>
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
    const canCancel = item.status !== "COMPLETED";
    const canComplete = item.status !== "COMPLETED" && item.status !== "PENDING PAYMENT";
    const canStartWalkin =
      item.kind === "walkin" &&
      item.queueId > 0 &&
      (item.rawStatus === "Waiting" || item.rawStatus === "Assigned");
    card.innerHTML = `
      <div class="row-wrap" style="justify-content: space-between; align-items: flex-start;">
        <div>
          <h4 style="margin: 0 0 4px;">${item.name}${item.isGroup ? ` <span class="tag info" style="margin-left:6px;">Group · ${item.peopleCount}</span>` : ""}${item.queueNumber ? ` <span class="tag info" style="margin-left:6px;">${item.queueNumber}</span>` : ""}</h4>
          <p style="margin: 0 0 4px;">${item.service}</p>
          <p class="meta" style="margin: 0 0 4px; color: #c9b46a;">${item.schedule || ""}</p>
          ${item.barber ? `<p class="meta" style="margin: 0;">Barber: ${item.barber}</p>` : ""}
        </div>
        <span class="tag ${
          item.status === "WAITING"
            ? "info"
            : item.status === "IN PROGRESS"
              ? "success"
              : item.status === "COMPLETING"
                ? "warning"
              : item.status === "PENDING PAYMENT"
                ? "warning"
                : "warning"
        }">${item.status}</span>
      </div>
      <div class="progress" style="margin-top: 10px; height: 8px;">
        <span style="width: ${pct}%; background: ${item.color};"></span>
      </div>
      <div class="row-wrap" style="margin-top: 6px; justify-content: space-between; align-items: center;">
        <span class="meta">${item.timeRemaining}${item.status === "IN PROGRESS" && pct > 0 ? ` • ${pct}%` : ""}${item.status === "COMPLETING" ? " • Auto-completing shortly" : ""}</span>
        ${canCancel || canComplete ? `
          <div class="row-wrap" style="gap: 6px;">
            ${canStartWalkin ? `<button type="button" class="btn primary tracking-start" title="Start service"
              data-kind="${item.kind}" data-queue-id="${item.queueId || ""}" data-name="${item.name}">▶ Start</button>` : ""}
            ${canComplete ? `<button type="button" class="btn secondary tracking-complete" title="Mark completed"
              data-kind="${item.kind}" data-appointment-id="${item.appointmentId || ""}" data-queue-id="${item.queueId || ""}" data-name="${item.name}">✓ Complete</button>` : ""}
            ${canCancel ? `<button type="button" class="btn secondary tracking-cancel" title="Cancel / remove"
              data-kind="${item.kind}" data-appointment-id="${item.appointmentId || ""}" data-queue-id="${item.queueId || ""}" data-name="${item.name}">✕ Cancel</button>` : ""}
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

function renderAutomationFeed(automation) {
  const wrap = document.getElementById("tracking-automation-feed");
  const list = document.getElementById("tracking-automation-list");
  if (!wrap || !list) return;

  const events = automation?.events ?? [];
  if (!events.length) {
    wrap.style.display = "none";
    list.innerHTML = "";
    return;
  }

  wrap.style.display = "block";
  list.innerHTML = events
    .map(
      (event) => `
        <div class="card" style="padding: 10px 12px; margin-bottom: 8px; border-color: #4CAF50;">
          <span class="meta" style="color: #9ad49a;">${event.action === "started" ? "▶" : "✓"} ${event.label || "Queue updated"}</span>
        </div>
      `,
    )
    .join("");
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
    card.className = "card gradient barber-card";
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
    const [servicesResponse, walkInBarbersResponse, allBarbersResponse] = await Promise.all([
      postJson(apiUrl("services.php"), { action: "list", channel: "walk_in" }),
      postJson(apiUrl("barbers.php"), { action: "list", channel: "walk_in" }),
      postJson(apiUrl("barbers.php"), { action: "list", channel: "all" }),
    ]);

    const services = servicesResponse.services ?? [];
    const walkInBarbers = walkInBarbersResponse.barbers ?? [];
    const barbers = allBarbersResponse.barbers ?? [];

    if (walkinServices) {
      walkinServices.innerHTML = services
        .map((service) => `<option value="${service.service_id}">${service.service_name}</option>`)
        .join("");
    }

    if (walkinBarber) {
      const currentValue = walkinBarber.value;
      walkinBarber.innerHTML = '<option value="">Unassigned</option>';
      walkinBarber.innerHTML += walkInBarbers
        .map((barber) => `<option value="${barber.barber_id}">${barber.full_name}</option>`)
        .join("");
      if (currentValue) {
        walkinBarber.value = currentValue;
      }
    }

    window.__barbersCache = barbers;
    populateLeaveBarberFilter(barbers);
    renderSplitBarbers(barbers);
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
      list.innerHTML = '<div class="time-off-card"><p class="meta" style="margin:0;">No pending time-off requests.</p></div>';
      return;
    }

    list.innerHTML = "";
    rows.forEach((row) => {
      const card = document.createElement("div");
      card.className = "time-off-card";
      card.innerHTML = `
        <h4>${row.barber_name ?? "Barber"}</h4>
        <p><strong>Date:</strong> ${row.request_date}</p>
        <p>${row.note ? `<strong>Note:</strong> ${row.note}` : "No note provided."}</p>
        <div class="row-wrap" style="margin-top: 8px;">
          <button class="btn gold" data-approve="${row.request_id}" type="button">Approve</button>
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
        if (state.leaveCalendar) {
          await loadBarberLeaveCalendar(state.leaveCalendar.year, state.leaveCalendar.month);
        }
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
    list.innerHTML = '<div class="time-off-card"><p class="meta" style="margin:0;">Could not load time-off requests.</p></div>';
  }
}

function escapeLeaveText(value) {
  return String(value ?? "").replace(/[&<>"]/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[ch]));
}

function scheduleDayByDate(date) {
  const days = state.scheduleCalendar?.days || [];
  return days.find((day) => day.date === date) || null;
}

function isBusyScheduleDay(day) {
  if (!day || day.status !== "open") return false;
  const booked = Number(day.bookedAppointments || 0);
  const capacity = Number(day.bookableSlotCount || 0);
  if (booked >= 8) return true;
  if (capacity > 0 && booked / capacity >= 0.6) return true;
  return false;
}

function renderLeaveCalDayDetail(date, byDate) {
  const detail = document.getElementById("leave-cal-day-detail");
  if (!detail) return;
  if (!date) {
    detail.innerHTML = "Select a day to see closures, leave, and booking activity.";
    return;
  }

  const scheduleDay = scheduleDayByDate(date);
  const leaveEntries = (byDate && byDate[date]) || [];
  const parts = [`<strong>${date}</strong>`];

  if (scheduleDay && scheduleDay.status !== "open") {
    parts.push(`Shop closed. ${escapeLeaveText(scheduleDay.reason || "Closed.")}`);
  } else if (scheduleDay) {
    const booked = Number(scheduleDay.bookedAppointments || 0);
    parts.push(
      `Open ${escapeLeaveText(scheduleDay.openTime)}–${escapeLeaveText(scheduleDay.closeTime)}`
      + ` · ${booked} appointment(s) booked`
      + (isBusyScheduleDay(scheduleDay) ? " (busy day)" : ""),
    );
  }

  if (leaveEntries.length) {
    const rows = leaveEntries
      .map((entry) => `<li><strong>${escapeLeaveText(entry.barberName)}</strong>${entry.note ? ` — ${escapeLeaveText(entry.note)}` : ""}</li>`)
      .join("");
    parts.push(`Barbers on leave:<ul style="margin: 8px 0 0; padding-left: 18px;">${rows}</ul>`);
  } else {
    parts.push("No approved leave on this day.");
  }

  detail.innerHTML = parts.join("<br />");
}

function renderBarberLeaveCalendar() {
  const grid = document.getElementById("leave-calendar-grid");
  const label = document.getElementById("leave-cal-month-label");
  const cal = state.leaveCalendar;
  if (!grid || !cal) return;

  if (label) label.textContent = cal.monthLabel || "—";

  const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const firstDay = new Date(cal.year, cal.month - 1, 1).getDay();
  const byDate = cal.byDate || {};
  const cells = [];

  weekdays.forEach((name) => {
    cells.push(`<div class="cal-weekday">${name}</div>`);
  });
  for (let i = 0; i < firstDay; i++) {
    cells.push('<div class="cal-day cal-empty"></div>');
  }

  const daysInMonth = new Date(cal.year, cal.month, 0).getDate();
  for (let day = 1; day <= daysInMonth; day++) {
    const date = `${cal.year}-${String(cal.month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
    const entries = byDate[date] || [];
    const hasLeave = entries.length > 0;
    const selected = state.leaveCalSelected === date;
    const scheduleDay = scheduleDayByDate(date);
    const busy = isBusyScheduleDay(scheduleDay);

    let statusClass = "cal-open";
    if (scheduleDay?.isPast) {
      statusClass = "cal-past";
    } else if (scheduleDay?.status === "closed_holiday") {
      statusClass = "cal-closed-holiday";
    } else if (scheduleDay?.status === "closed_weekly") {
      statusClass = "cal-closed-weekly";
    }

    const extra = [
      hasLeave ? "cal-has-leave" : "",
      busy ? "cal-busy" : "",
      selected ? "cal-selected" : "",
    ].filter(Boolean).join(" ");

    const titleParts = [];
    if (scheduleDay && scheduleDay.status !== "open") {
      titleParts.push(scheduleDay.reason || "Closed");
    } else if (scheduleDay) {
      titleParts.push(`Open ${scheduleDay.openTime}–${scheduleDay.closeTime}`);
      if (Number(scheduleDay.bookedAppointments || 0) > 0) {
        titleParts.push(`${scheduleDay.bookedAppointments} booked`);
      }
    }
    if (hasLeave) titleParts.push(`${entries.length} on leave`);

    const badge = hasLeave ? `<span class="meta" style="font-size:9px;display:block;">${entries.length}</span>` : "";
    cells.push(
      `<button type="button" class="cal-day ${statusClass}${extra ? ` ${extra}` : ""}" `
      + `data-date="${date}" title="${escapeLeaveText(titleParts.join(" · "))}">${day}${badge}</button>`
    );
  }

  grid.innerHTML = cells.join("");

  grid.querySelectorAll(".cal-day[data-date]").forEach((button) => {
    button.addEventListener("click", () => {
      state.leaveCalSelected = button.getAttribute("data-date");
      renderBarberLeaveCalendar();
      renderLeaveCalDayDetail(state.leaveCalSelected, byDate);
    });
  });

  if (state.leaveCalSelected) {
    renderLeaveCalDayDetail(state.leaveCalSelected, byDate);
  } else {
    renderLeaveCalDayDetail(null, byDate);
  }
}

async function loadShopScheduleCalendar(year, month) {
  try {
    const data = await postJson(apiUrl("operating_schedule.php"), {
      action: "calendarMonth",
      year,
      month,
    });
    state.scheduleCalendar = data;
  } catch (_) {
    state.scheduleCalendar = null;
  }
}

async function loadBarberLeaveCalendar(year, month) {
  const now = new Date();
  const y = year ?? now.getFullYear();
  const m = month ?? now.getMonth() + 1;
  const payload = { action: "listApprovedLeaveMonth", year: y, month: m };
  if (state.leaveCalBarberId) {
    payload.barberID = Number(state.leaveCalBarberId);
  }
  const grid = document.getElementById("leave-calendar-grid");
  setRegionLoading(grid, true, "Loading calendar...");
  try {
    const [data] = await Promise.all([
      postJson(apiUrl("barber_schedule.php"), payload, false),
      loadShopScheduleCalendar(y, m),
    ]);
    state.leaveCalendar = data;
    renderBarberLeaveCalendar();
  } catch (_) {
    if (grid) grid.innerHTML = '<div class="meta">Could not load leave calendar.</div>';
  } finally {
    setRegionLoading(grid, false);
  }
}

function populateLeaveBarberFilter(barbers) {
  const select = document.getElementById("leave-cal-barber-filter");
  if (!select) return;
  const current = state.leaveCalBarberId || "";
  select.innerHTML = '<option value="">All barbers</option>';
  (barbers || []).forEach((barber) => {
    const id = barber.barber_id ?? barber.barberID;
    const name = barber.full_name ?? barber.fullName ?? "Barber";
    if (!id) return;
    const option = document.createElement("option");
    option.value = String(id);
    option.textContent = name;
    select.appendChild(option);
  });
  select.value = current;
}

async function loadDashboard(showOverlay = false) {
  if (!requireReceptionist()) return;
  try {
    const data = await postJson(
      apiUrl("receptionist.php"),
      { action: "dashboard" },
      showOverlay ? "Loading dashboard..." : false,
    );
    state.appointments = data.appointments ?? [];
    state.walkins = data.walkins ?? [];
    state.automation = data.automation ?? { events: [], counts: {} };
    renderStats(data.stats ?? []);
    renderAppointments(state.appointments);
    renderWalkins(state.walkins);
    renderAutomationFeed(state.automation);
    renderSplitTracking(state.appointments, state.walkins);
    if (state.automation?.events?.length) {
      const labels = state.automation.events.map((e) => e.label).join(" · ");
      toast(labels, "success");
    }
  } catch (error) {
    state.appointments = [];
    state.walkins = [];
    renderStats([]);
    renderAppointments([]);
    renderWalkins([]);
    renderSplitTracking([], []);
    toast(error.message || "Failed to load dashboard", "error");
  }

  document.getElementById("last-updated").textContent = new Date().toLocaleString();
  adjustTrackingRefreshInterval();
}

function trackingHasCompleting() {
  const tracking = buildTracking(state.appointments ?? [], state.walkins ?? []);
  return tracking.some((item) => item.status === "COMPLETING");
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

async function refreshAll(button) {
  const updated = document.getElementById("last-updated");
  if (updated) updated.textContent = "Updating…";
  const run = async () => {
    await loadDashboard(false);
    const now = new Date();
    await loadBarberLeaveCalendar(now.getFullYear(), now.getMonth() + 1);
  };
  if (button) {
    await withButtonLoading(button, () => runWithLoading("Refreshing desk...", run), { label: "Refreshing..." });
  } else {
    await runWithLoading("Refreshing desk...", run);
  }
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

  if (target.classList.contains("tracking-start")) {
    const name = target.dataset.name || "this client";
    const queueId = Number(target.dataset.queueId || "0");
    const ok = await confirmAction(`Start service for ${name}?`, { confirmLabel: "Start" });
    if (!ok) return;
    await withButtonLoading(target, async () => {
      try {
        if (queueId > 0) {
          await postJson(
            apiUrl("receptionist.php"),
            { action: "updateWalkinStatus", queueID: queueId, status: "InProgress" },
            "Starting service...",
          );
        }
        toast("Walk-in started.", "success");
        await loadDashboard(false);
      } catch (error) {
        toast(error.message || "Unable to start walk-in", "error");
      }
    }, { label: "Starting..." });
    return;
  }

  if (target.classList.contains("tracking-complete")) {
    const name = target.dataset.name || "this client";
    const kind = target.dataset.kind || "appointment";
    const appointmentId = Number(target.dataset.appointmentId || "0");
    const queueId = Number(target.dataset.queueId || "0");
    const ok = await confirmAction(`Mark ${name} as completed?`, { confirmLabel: "Complete" });
    if (!ok) return;
    await withButtonLoading(target, async () => {
      try {
        if (kind === "walkin" && queueId > 0) {
          await postJson(
            apiUrl("receptionist.php"),
            { action: "updateWalkinStatus", queueID: queueId, status: "Completed" },
            "Completing…",
          );
        } else if (appointmentId > 0) {
          await postJson(
            apiUrl("receptionist.php"),
            { action: "updateAppointmentStatus", appointmentID: appointmentId, status: "Completed" },
            "Completing…",
          );
        }
        toast("Marked as completed.", "success");
        await loadDashboard(false);
      } catch (error) {
        toast(error.message || "Unable to complete", "error");
      }
    }, { label: "Completing..." });
    return;
  }

  if (target.classList.contains("tracking-cancel")) {
    const name = target.dataset.name || "this client";
    const kind = target.dataset.kind || "appointment";
    const appointmentId = Number(target.dataset.appointmentId || "0");
    const queueId = Number(target.dataset.queueId || "0");
    const ok = await confirmAction(`Cancel ${name} and remove from tracking?`, {
      confirmLabel: "Cancel entry",
      danger: true,
    });
    if (!ok) return;
    await withButtonLoading(target, async () => {
      try {
        if (kind === "walkin" && queueId > 0) {
          await postJson(
            apiUrl("receptionist.php"),
            { action: "updateWalkinStatus", queueID: queueId, status: "Cancelled" },
            "Cancelling…",
          );
        } else if (appointmentId > 0) {
          await postJson(
            apiUrl("receptionist.php"),
            { action: "updateAppointmentStatus", appointmentID: appointmentId, status: "Cancelled" },
            "Cancelling…",
          );
        }
        toast("Removed from tracking.", "success");
        await loadDashboard(false);
      } catch (error) {
        toast(error.message || "Unable to cancel", "error");
      }
    }, { label: "Cancelling..." });
    return;
  }

  const appointmentId = target.dataset.appointmentId;
  const appointmentStatus = target.dataset.status;
  if (appointmentId && appointmentStatus) {
    await withButtonLoading(target, async () => {
      try {
        await postJson(
          apiUrl("receptionist.php"),
          {
            action: "updateAppointmentStatus",
            appointmentID: Number(appointmentId),
            status: appointmentStatus,
          },
          "Updating appointment...",
        );
        toast(`Appointment marked ${appointmentStatus}.`, "success");
        await loadDashboard(false);
      } catch (error) {
        toast(error.message || "Unable to update appointment", "error");
      }
    }, { label: "Updating..." });
    return;
  }

  const walkinId = target.dataset.walkinId;
  const walkinStatus = target.dataset.walkinStatus;
  const walkinAction = target.dataset.walkinAction;
  if (walkinId && (walkinStatus || walkinAction)) {
    await withButtonLoading(target, async () => {
      try {
        let status = walkinStatus;
        let barberID = 0;
        if (walkinAction === "assign") {
          const select = document.querySelector(`[data-walkin-barber="${walkinId}"]`);
          barberID = select ? Number(select.value) : 0;
          status = barberID > 0 ? "Assigned" : "Waiting";
        }

        await postJson(
          apiUrl("receptionist.php"),
          {
            action: "updateWalkinStatus",
            queueID: Number(walkinId),
            status,
            barberID,
          },
          "Updating walk-in...",
        );
        toast("Walk-in updated.", "success");
        await loadDashboard(false);
      } catch (error) {
        toast(error.message || "Unable to update walk-in", "error");
      }
    }, { label: "Updating..." });
  }
});

walkinForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  walkinError.textContent = "";

  const serviceIDs = Array.from(walkinServices.selectedOptions).map((option) => option.value);
  const barberID = walkinBarber.value ? Number(walkinBarber.value) : 0;
  const submitBtn = walkinForm.querySelector('button[type="submit"]');

  await withButtonLoading(submitBtn, async () => {
    try {
      await postJson(
        apiUrl("receptionist.php"),
        { action: "createWalkin", serviceIDs, barberID },
        "Adding walk-in...",
      );
      walkinForm.reset();
      toast("Walk-in added.", "success");
      await loadDashboard(false);
    } catch (error) {
      walkinError.textContent = error.message || "Unable to add walk-in.";
      toast(error.message || "Unable to add walk-in.", "error");
    }
  }, { label: "Adding..." });
});

refreshButton?.addEventListener("click", (event) => refreshAll(event.currentTarget));

document.getElementById("leave-cal-prev")?.addEventListener("click", async (event) => {
  const cal = state.leaveCalendar;
  if (!cal) return;
  let y = cal.year;
  let m = cal.month - 1;
  if (m < 1) { m = 12; y -= 1; }
  await withButtonLoading(event.currentTarget, () => loadBarberLeaveCalendar(y, m));
});

document.getElementById("leave-cal-next")?.addEventListener("click", async (event) => {
  const cal = state.leaveCalendar;
  if (!cal) return;
  let y = cal.year;
  let m = cal.month + 1;
  if (m > 12) { m = 1; y += 1; }
  await withButtonLoading(event.currentTarget, () => loadBarberLeaveCalendar(y, m));
});

document.getElementById("leave-cal-barber-filter")?.addEventListener("change", (event) => {
  state.leaveCalBarberId = event.target.value || "";
  const cal = state.leaveCalendar;
  if (cal) {
    loadBarberLeaveCalendar(cal.year, cal.month);
  } else {
    const now = new Date();
    loadBarberLeaveCalendar(now.getFullYear(), now.getMonth() + 1);
  }
});

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

let trackingRefreshTimer = null;
let trackingProgressTimer = null;
const TRACKING_REFRESH_MS_DEFAULT = 45000;
const TRACKING_REFRESH_MS_COMPLETING = 10000;
const TRACKING_PROGRESS_TICK_MS = 1000;

function refreshTrackingProgressUi() {
  const trackingView = document.getElementById("tracking-view");
  if (!trackingView || trackingView.hidden) {
    return;
  }
  const hasQueue = (state.walkins?.length ?? 0) > 0 || (state.appointments?.length ?? 0) > 0;
  if (!hasQueue) {
    return;
  }
  renderSplitTracking(state.appointments ?? [], state.walkins ?? []);
}

function startTrackingProgressTicker() {
  if (trackingProgressTimer) {
    clearInterval(trackingProgressTimer);
  }
  trackingProgressTimer = setInterval(refreshTrackingProgressUi, TRACKING_PROGRESS_TICK_MS);
}

function adjustTrackingRefreshInterval() {
  if (trackingRefreshTimer) {
    clearInterval(trackingRefreshTimer);
    trackingRefreshTimer = null;
  }
  const ms = trackingHasCompleting()
    ? TRACKING_REFRESH_MS_COMPLETING
    : TRACKING_REFRESH_MS_DEFAULT;
  trackingRefreshTimer = setInterval(() => {
    const trackingView = document.getElementById("tracking-view");
    if (trackingView && !trackingView.hidden) {
      loadDashboard(false);
    }
  }, ms);
}

function startTrackingAutoRefresh() {
  adjustTrackingRefreshInterval();
}

async function init() {
  if (!requireReceptionist()) return;
  ui()?.resetLoading?.();
  showView("dashboard");
  renderProfileChip();
  await runWithLoading("Loading receptionist desk...", async () => {
    await loadOptions();
    await loadDashboard(false);
    const now = new Date();
    await loadBarberLeaveCalendar(now.getFullYear(), now.getMonth() + 1);
  });
  startTrackingAutoRefresh();
  startTrackingProgressTicker();
}

init();
