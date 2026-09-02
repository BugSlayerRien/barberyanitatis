const form = document.getElementById("login-form");
const errorBox = document.getElementById("error");
const passwordInput = document.getElementById("password");
const passwordToggle = document.getElementById("password-toggle");

/**
 * A signed-in admin/receptionist must not be able to reach Sign In via
 * browser Back/Forward. Runs on normal load and again on every bfcache
 * restore (pageshow with persisted=true) — a back/forward navigation into
 * this page does not otherwise re-execute this script.
 */
function redirectIfAlreadySignedIn() {
  const home = portalHomePathForRoles(portalRolesFromSession());
  if (home) {
    window.location.replace(`./${home}`);
    return true;
  }
  return false;
}

redirectIfAlreadySignedIn();
window.addEventListener("pageshow", (event) => {
  if (event.persisted) {
    redirectIfAlreadySignedIn();
  }
});

passwordToggle?.addEventListener("click", () => {
  if (!(passwordInput instanceof HTMLInputElement)) return;
  const show = passwordInput.type === "password";
  passwordInput.type = show ? "text" : "password";
  passwordToggle.setAttribute("aria-pressed", show ? "true" : "false");
  passwordToggle.setAttribute("aria-label", show ? "Hide password" : "Show password");
  const eye = passwordToggle.querySelector(".password-toggle-show");
  const eyeOff = passwordToggle.querySelector(".password-toggle-hide");
  if (eye instanceof Element) eye.toggleAttribute("hidden", show);
  if (eyeOff instanceof Element) eyeOff.toggleAttribute("hidden", !show);
});

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  errorBox.textContent = "";

  const email = document.getElementById("email").value.trim();
  const password = document.getElementById("password").value;
  const submitBtn = form.querySelector('button[type="submit"]');
  if (submitBtn) {
    submitBtn.disabled = true;
  }

  try {
    const response = await fetchWithRetry(resolveApiUrl("auth.php"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "login", email, password }),
    });

    const data = await parseJsonResponse(response);
    if (!response.ok) {
      errorBox.textContent = data.error || "Sign-in failed. Please verify your credentials.";
      return;
    }

    const roles = (data.user?.roles || []).map((role) => role.toLowerCase());
    sessionStorage.setItem("roles", JSON.stringify(roles));
    sessionStorage.setItem("user", JSON.stringify(data.user));
    if (typeof storePortalSession === "function") {
      storePortalSession(data);
    }

    if (roles.includes("admin")) {
      window.location.href = "./admin/index.html";
      return;
    }

    if (roles.includes("receptionist")) {
      window.location.href = "./receptionist/index.html";
      return;
    }

    errorBox.textContent =
      "Your account does not have portal access. Please contact the system administrator.";
  } catch (error) {
    errorBox.textContent =
      error?.message ||
      "Unable to connect to the server. If this is the live portal, wait a minute and try again (the API may be waking up). Locally, open http://localhost/.../web-admin/login.html (not as a file:// URL).";
  } finally {
    if (submitBtn) {
      submitBtn.disabled = false;
    }
  }
});
