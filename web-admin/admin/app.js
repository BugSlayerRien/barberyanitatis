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
    { title: "Total Users", value: "1,247", change: "+12% from last month", changeType: "success" },
    { title: "Active Services", value: "12", change: "2 new this week", changeType: "success" },
    { title: "Monthly Revenue", value: "₱45,680", change: "+8% from last month", changeType: "success" },
    { title: "Pending Appointments", value: "23", change: "Requires attention", changeType: "warning" },
  ],
  activities: [
    {
      icon: "👤",
      title: "New user registration",
      description: "Jessica Martinez registered 5 minutes ago",
      time: "JUST NOW",
    },
    {
      icon: "₱",
      title: "Payment received",
      description: "₱750 payment for luxury treatment",
      time: "15 min ago",
    },
    {
      icon: "📅",
      title: "Service booking",
      description: "Color transformation booked for tomorrow",
      time: "1 hour ago",
    },
  ],
};

function renderStats(stats) {
  const grid = document.getElementById("stats-grid");
  grid.innerHTML = "";
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
  try {
    const response = await fetch("../../api/admin_dashboard.php");
    if (!response.ok) throw new Error("API error");
    const data = await response.json();
    renderStats(data.stats ?? fallbackData.stats);
    renderActivities(data.activities ?? fallbackData.activities);
  } catch (error) {
    renderStats(fallbackData.stats);
    renderActivities(fallbackData.activities);
  }

  const now = new Date();
  const formatted = now.toLocaleString();
  document.getElementById("last-updated").textContent = formatted;
}

loadDashboard();
