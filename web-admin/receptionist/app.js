const views = {
  analytics: document.getElementById("analytics-view"),
  appointments: document.getElementById("appointments-view"),
  walkins: document.getElementById("walkins-view"),
  tracking: document.getElementById("tracking-view"),
  barbers: document.getElementById("barbers-view"),
};

const navButtons = document.querySelectorAll(".nav button");
const apiBase = "../../api";
const refreshButton = document.getElementById("refresh-dashboard");
const walkinForm = document.getElementById("walkin-form");
const walkinError = document.getElementById("walkin-error");
const walkinServices = document.getElementById("walkin-services");
const walkinBarber = document.getElementById("walkin-barber");

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

function formatCurrency(value) {
  if (value === null || value === undefined || Number.isNaN(Number(value))) return "-";
  return `₱${Number(value).toFixed(2)}`;
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

function renderAppointments(appointments) {
  const table = document.getElementById("appointments-table");
  if (!appointments || !appointments.length) {
    table.innerHTML = "<tr><td>No appointments today.</td></tr>";
    return;
  }

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
        <th>Actions</th>
      </tr>
    </thead>
    <tbody>
      ${appointments
        .map(
          (item) => `
            <tr>
              <td>${item.name}</td>
              <td>${item.service}</td>
              <td>${item.time}</td>
              <td>${item.duration}</td>
              <td>${formatCurrency(item.price)}</td>
              <td><span class="tag ${statusTag(item.status)}">${item.status}</span></td>
              <td>${item.barber}</td>
              <td>${renderAppointmentActions(item)}</td>
            </tr>
          `,
        )
        .join("")}
    </tbody>
  `;
}

function renderAppointmentActions(item) {
  const id = item.appointment_id;
  switch (item.status) {
    case "Scheduled":
      return `
        <button class="btn secondary" data-appointment-id="${id}" data-status="CheckedIn">Check-in</button>
        <button class="btn secondary" data-appointment-id="${id}" data-status="Cancelled">Cancel</button>
        <button class="btn secondary" data-appointment-id="${id}" data-status="NoShow">No-show</button>
      `;
    case "CheckedIn":
      return `
        <button class="btn secondary" data-appointment-id="${id}" data-status="InProgress">Start</button>
        <button class="btn secondary" data-appointment-id="${id}" data-status="Cancelled">Cancel</button>
        <button class="btn secondary" data-appointment-id="${id}" data-status="NoShow">No-show</button>
      `;
    case "InProgress":
      return `
        <button class="btn secondary" data-appointment-id="${id}" data-status="Completed">Complete</button>
        <button class="btn secondary" data-appointment-id="${id}" data-status="Cancelled">Cancel</button>
      `;
    default:
      return "-";
  }
}

function renderWalkins(walkins) {
  const table = document.getElementById("walkins-table");
  if (!walkins || !walkins.length) {
    table.innerHTML = "<tr><td>No walk-ins yet.</td></tr>";
    return;
  }

  table.innerHTML = `
    <thead>
      <tr>
        <th>Client</th>
        <th>Service</th>
        <th>Wait Time</th>
        <th>Status</th>
        <th>Barber</th>
        <th>Actions</th>
      </tr>
    </thead>
    <tbody>
      ${walkins
        .map(
          (item) => `
            <tr>
              <td>${item.name}</td>
              <td>${item.service}</td>
              <td>${item.waitTime}</td>
              <td><span class="tag ${statusTag(item.status)}">${item.status}</span></td>
              <td>${renderWalkinBarber(item)}</td>
              <td>${renderWalkinActions(item)}</td>
            </tr>
          `,
        )
        .join("")}
    </tbody>
  `;
}

function renderWalkinBarber(item) {
  const options = window.__barbersCache || [];
  const selected = item.barber_id ?? "";
  return `
    <select class="select" data-walkin-barber="${item.queue_id}">
      <option value="">Unassigned</option>
      ${options
        .map(
          (barber) =>
            `<option value="${barber.barber_id}" ${String(barber.barber_id) === String(selected) ? "selected" : ""}>${barber.full_name}</option>`
        )
        .join("")}
    </select>
  `;
}

function renderWalkinActions(item) {
  const id = item.queue_id;
  switch (item.status) {
    case "Waiting":
      return `
        <button class="btn secondary" data-walkin-id="${id}" data-walkin-action="assign">Assign</button>
        <button class="btn secondary" data-walkin-id="${id}" data-walkin-status="Cancelled">Cancel</button>
      `;
    case "Assigned":
      return `
        <button class="btn secondary" data-walkin-id="${id}" data-walkin-status="InProgress">Start</button>
        <button class="btn secondary" data-walkin-id="${id}" data-walkin-status="Cancelled">Cancel</button>
      `;
    case "InProgress":
      return `<button class="btn secondary" data-walkin-id="${id}" data-walkin-status="Completed">Complete</button>`;
    default:
      return "-";
  }
}

function renderTracking(items) {
  const list = document.getElementById("tracking-list");
  list.innerHTML = "";
  if (!items || !items.length) {
    list.innerHTML = "<div class=\"card\">No tracking data.</div>";
    return;
  }
  items.forEach((item) => {
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `
      <h4>${item.name}</h4>
      <p>${item.service}</p>
      <div class="tag ${item.status === "Waiting" ? "info" : item.status === "InProgress" ? "success" : "warning"}">${item.status}</div>
      <div class="progress" style="margin-top: 8px;">
        <span style="width: ${item.progress * 100}%; background: ${item.color};"></span>
      </div>
      <div class="meta" style="margin-top: 6px;">${item.timeRemaining}</div>
    `;
    list.appendChild(card);
  });
}

function renderBarbers(items) {
  const list = document.getElementById("barbers-list");
  list.innerHTML = "";
  if (!items || !items.length) {
    list.innerHTML = "<div class=\"card\">No barbers available.</div>";
    return;
  }
  items.forEach((item) => {
    const card = document.createElement("div");
    card.className = "card gradient";
    card.innerHTML = `
      <h4>${item.name}</h4>
      <p>${item.specialty}</p>
      <div class="meta">Rating: ${item.rating}</div>
      <div class="meta">Experience: ${item.experience}</div>
    `;
    list.appendChild(card);
  });
}

function buildTracking(appointments, walkins) {
  const items = [];
  (appointments ?? []).forEach((appointment) => {
    if (!["CheckedIn", "InProgress"].includes(appointment.status)) return;
    items.push({
      name: appointment.name,
      service: appointment.service,
      status: appointment.status,
      progress: appointment.status === "CheckedIn" ? 0.35 : 0.7,
      color: appointment.status === "CheckedIn" ? "#2196f3" : "#4caf50",
      timeRemaining: appointment.status === "CheckedIn" ? "Awaiting start" : "In progress",
    });
  });

  (walkins ?? []).forEach((walkin) => {
    if (!["Waiting", "Assigned", "InProgress"].includes(walkin.status)) return;
    const progressMap = { Waiting: 0.2, Assigned: 0.45, InProgress: 0.75 };
    items.push({
      name: walkin.name,
      service: walkin.service,
      status: walkin.status,
      progress: progressMap[walkin.status] ?? 0.2,
      color: walkin.status === "InProgress" ? "#4caf50" : "#ff9800",
      timeRemaining: walkin.status === "Waiting" ? "Waiting in queue" : "Service in progress",
    });
  });

  return items;
}

async function loadOptions() {
  const [servicesData, barbersData] = await Promise.all([
    postJson(`${apiBase}/services.php`, { action: "list" }),
    postJson(`${apiBase}/barbers.php`, { action: "list" }),
  ]);

  const services = servicesData.services ?? [];
  const barbers = barbersData.barbers ?? [];
  window.__barbersCache = barbers;

  walkinServices.innerHTML = services
    .map((service) => `<option value="${service.service_id}">${service.service_name}</option>`)
    .join("");

  walkinBarber.innerHTML = [
    '<option value="">Unassigned</option>',
    ...barbers.map((barber) => `<option value="${barber.barber_id}">${barber.full_name}</option>`),
  ].join("");

  renderBarbers(
    barbers.map((barber) => ({
      name: barber.full_name,
      specialty: barber.specialty ?? "N/A",
      rating: barber.rating ?? "-",
      experience: barber.years_experience ? `${barber.years_experience} yrs` : "N/A",
    }))
  );
}

async function loadDashboard() {
  if (!requireReceptionist()) return;
  try {
    const data = await postJson(`${apiBase}/receptionist.php`, { action: "dashboard" });
    renderStats(data.stats ?? []);
    renderAppointments(data.appointments ?? []);
    renderWalkins(data.walkins ?? []);
    renderTracking(buildTracking(data.appointments ?? [], data.walkins ?? []));
    renderSummary(data.stats ?? [], data.appointments ?? [], data.walkins ?? []);
  } catch (error) {
    renderStats([]);
    renderAppointments([]);
    renderWalkins([]);
    renderTracking([]);
    renderSummary([], [], []);
  }

  document.getElementById("last-updated").textContent = new Date().toLocaleString();
}

document.addEventListener("click", async (event) => {
  const target = event.target;
  if (!(target instanceof HTMLElement)) return;

  const appointmentId = target.dataset.appointmentId;
  const appointmentStatus = target.dataset.status;
  if (appointmentId && appointmentStatus) {
    try {
      await postJson(`${apiBase}/receptionist.php`, {
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

      await postJson(`${apiBase}/receptionist.php`, {
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
    await postJson(`${apiBase}/receptionist.php`, {
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

refreshButton?.addEventListener("click", () => loadDashboard());

async function init() {
  if (!requireReceptionist()) return;
  await loadOptions();
  await loadDashboard();
}

init();
