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

loadDashboard();
