const views = {
  analytics: document.getElementById("analytics-view"),
  appointments: document.getElementById("appointments-view"),
  walkins: document.getElementById("walkins-view"),
  tracking: document.getElementById("tracking-view"),
  barbers: document.getElementById("barbers-view"),
};

const navButtons = document.querySelectorAll(".nav button");

navButtons.forEach((button) => {
  button.addEventListener("click", () => {
    const view = button.dataset.view;
    navButtons.forEach((b) => b.classList.remove("active"));
    button.classList.add("active");
    Object.values(views).forEach((section) => section.setAttribute("hidden", ""));
    if (views[view]) {
      views[view].removeAttribute("hidden");
    }
  });
});

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
              <td>${item.price}</td>
              <td><span class="tag ${item.status === "Completed" ? "success" : item.status === "Scheduled" ? "info" : "warning"}">${item.status}</span></td>
              <td>${item.barber}</td>
            </tr>
          `,
        )
        .join("")}
    </tbody>
  `;
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
              <td><span class="tag ${item.status === "Completed" ? "success" : item.status === "InProgress" ? "warning" : "info"}">${item.status}</span></td>
            </tr>
          `,
        )
        .join("")}
    </tbody>
  `;
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

async function loadDashboard() {
  if (!requireReceptionist()) return;
  try {
    const response = await fetch("../../api/receptionist_dashboard.php");
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    renderStats(data.stats ?? []);
    renderAppointments(data.appointments ?? []);
    renderWalkins(data.walkins ?? []);
    renderTracking(data.tracking ?? []);
    renderBarbers(data.barbers ?? []);
  } catch (error) {
    renderStats([]);
    renderAppointments([]);
    renderWalkins([]);
    renderTracking([]);
    renderBarbers([]);
  }

  document.getElementById("last-updated").textContent = new Date().toLocaleString();
}

loadDashboard();
