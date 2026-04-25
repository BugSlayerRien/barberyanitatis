const form = document.getElementById("login-form");
const errorBox = document.getElementById("error");

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  errorBox.textContent = "";

  const email = document.getElementById("email").value.trim();
  const password = document.getElementById("password").value;

  try {
    const response = await fetch("../api/auth.php", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "login", email, password }),
    });

    const data = await response.json();
    if (!response.ok) {
      errorBox.textContent = data.error || "Sign-in failed. Please verify your credentials.";
      return;
    }

    const roles = (data.user?.roles || []).map((role) => role.toLowerCase());
    sessionStorage.setItem("roles", JSON.stringify(roles));
    sessionStorage.setItem("user", JSON.stringify(data.user));

    if (roles.includes("admin")) {
      window.location.href = "./admin/index.html";
      return;
    }

    if (roles.includes("receptionist")) {
      window.location.href = "./receptionist/index.html";
      return;
    }

    errorBox.textContent = "Your account does not have portal access. Please contact the system administrator.";
  } catch (error) {
    errorBox.textContent = "Unable to connect to the server. Please try again.";
  }
});
