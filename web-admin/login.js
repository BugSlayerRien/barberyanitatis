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

// --- Forgot password (OTP) --------------------------------------------------
//
// Two steps in one form: request a code, then submit it with the new password.
// The code itself is issued and checked by Supabase (see auth.php's
// requestPasswordOtp / resetPasswordWithOtp), so nothing here stores or
// validates it.
const resetForm = document.getElementById("reset-form");
const resetStep2 = document.getElementById("reset-step2");
const resetError = document.getElementById("reset-error");
const resetNotice = document.getElementById("reset-notice");
const resetSubmit = document.getElementById("reset-submit");

function showResetView(show) {
  form.toggleAttribute("hidden", show);
  resetForm?.toggleAttribute("hidden", !show);
  if (show) {
    document.getElementById("reset-email").value = document.getElementById("email").value.trim();
  }
}

document.getElementById("forgot-open")?.addEventListener("click", () => {
  errorBox.textContent = "";
  showResetView(true);
});

document.getElementById("reset-cancel")?.addEventListener("click", () => {
  resetError.textContent = "";
  resetNotice.textContent = "";
  showResetView(false);
});

let codeRequested = false;

resetForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  resetError.textContent = "";

  const email = document.getElementById("reset-email").value.trim();
  if (!email) {
    resetError.textContent = "Enter your work email.";
    return;
  }

  resetSubmit.disabled = true;
  try {
    if (!codeRequested) {
      const response = await fetchWithRetry(resolveApiUrl("auth.php"), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "requestPasswordOtp", email }),
      });
      const data = await parseJsonResponse(response);
      if (!response.ok) {
        resetError.textContent = data.error || "Could not send a code. Please try again.";
        return;
      }
      // Deliberately the same message whether or not the address is
      // registered, matching the API's non-enumerating response.
      resetNotice.textContent = data.message || "If an account exists for that email, a code has been sent.";
      codeRequested = true;
      resetStep2.removeAttribute("hidden");
      resetSubmit.textContent = "Update password";
      return;
    }

    const code = document.getElementById("reset-code").value.trim();
    const newPassword = document.getElementById("reset-password").value;
    if (!code || !newPassword) {
      resetError.textContent = "Enter the code from your email and a new password.";
      return;
    }

    const response = await fetchWithRetry(resolveApiUrl("auth.php"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "resetPasswordWithOtp", email, code, newPassword }),
    });
    const data = await parseJsonResponse(response);
    if (!response.ok) {
      resetError.textContent = data.error || "That code is invalid or has expired.";
      return;
    }

    resetNotice.textContent = "";
    showResetView(false);
    errorBox.textContent = "";
    document.getElementById("password").value = "";
    codeRequested = false;
    resetStep2.setAttribute("hidden", "");
    resetSubmit.textContent = "Send code";
    alert(data.message || "Password updated. You can sign in with your new password.");
  } catch (error) {
    resetError.textContent = error?.message || "Unable to reach the server. Please try again.";
  } finally {
    resetSubmit.disabled = false;
  }
});
