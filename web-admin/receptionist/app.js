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

const fallbackData = {
  stats: [
    { title: "Walk-ins", value: "0", change: "No walk-ins yet", changeType: "info" },
    { title: "Appointments", value: "3", change: "3 scheduled today", changeType: "success" },
    { title: "In Progress", value: "1", change: "Active services", changeType: "warning" },
    { title: "Available Barbers", value: "2", change: "On shift", changeType: "success" },
  ],
  appointments: [
    {
      name: "Jessica Davis",
      service: "Precision Cut & Style",
      time: "10:00 AM",
      duration: "90 min",
      price: "₱100",
      status: "CONFIRMED",
      barber: "Mike Chen",
    },
    {
      name: "Maria Rodriguez",
      service: "Color Transformation",
      time: "2:00 PM",
      duration: "180 min",
      price: "₱150",
      status: "PENDING",
      barber: "Sarah Johnson",
    },
    {
      name: "Sarah Johnson",
      service: "Luxury Treatment",
      time: "5:00 PM",
      duration: "120 min",
      price: "₱200",
      status: "CONFIRMED",
      barber: "Emma Rodriguez",
    },
  ],
  walkins: [],
  tracking: [
    {
      name: "Alex Brown",
      service: "Haircut & Styling",
      status: "IN PROGRESS",
      progress: 0.65,
      timeRemaining: "15 min remaining",
      color: "#4caf50",
    },
    {
      name: "Jessica White",
      service: "Color Treatment",
      status: "WAITING",
      progress: 0,
      timeRemaining: "Waiting",
      color: "#2196f3",
    },
    {
      name: "Michael Johnson",
      service: "Beard Trim",
      status: "COMPLETED",
      progress: 1,
      timeRemaining: "Completed",
      color: "#9e9e9e",
    },
  ],
  barbers: [
    { name: "Mike Chen", specialty: "Precision Cuts", rating: 4.9, experience: "8 years" },
    { name: "Sarah Johnson", specialty: "Color Expert", rating: 4.8, experience: "6 years" },
    { name: "Emma Rodriguez", specialty: "Styling Specialist", rating: 4.7, experience: "5 years" },
  ],
};

function renderStats(stats) {
  const grid = document.getElementById("analytics-stats");
  grid.innerHTML = "";
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
  if (!appointments.length) {
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
              <td><span class="tag ${item.status === "CONFIRMED" ? "success" : "warning"}">${item.status}</span></td>
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
  if (!walkins.length) {
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
              <td><span class="tag info">${item.status}</span></td>
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
  items.forEach((item) => {
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = `
      <h4>${item.name}</h4>
      <p>${item.service}</p>
      <div class="tag ${item.status === "WAITING" ? "info" : item.status === "IN PROGRESS" ? "success" : "warning"}">${item.status}</div>
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
  try {
    const response = await fetch("../../api/receptionist_dashboard.php");
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    renderStats(data.stats ?? fallbackData.stats);
    renderAppointments(data.appointments ?? fallbackData.appointments);
    renderWalkins(data.walkins ?? fallbackData.walkins);
    renderTracking(data.tracking ?? fallbackData.tracking);
    renderBarbers(data.barbers ?? fallbackData.barbers);
  } catch (error) {
    renderStats(fallbackData.stats);
    renderAppointments(fallbackData.appointments);
    renderWalkins(fallbackData.walkins);
    renderTracking(fallbackData.tracking);
    renderBarbers(fallbackData.barbers);
  }

  document.getElementById("last-updated").textContent = new Date().toLocaleString();
}

loadDashboard();
