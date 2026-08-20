/**
 * Portal shell: presentation-only chrome shared by the Admin and Receptionist
 * portals. Handles the sidebar drawer (mobile) / collapse (desktop) and keeps
 * the top bar breadcrumb in sync with the active navigation item.
 *
 * This file never touches data, API calls or view logic.
 */
(function initPortalShell() {
  const MOBILE_QUERY = "(max-width: 1024px)";

  function app() {
    return document.querySelector(".app");
  }

  function toggle() {
    return document.getElementById("sidebar-toggle");
  }

  function isDrawerLayout() {
    return window.matchMedia(MOBILE_QUERY).matches;
  }

  function isNavShown() {
    const shell = app();
    if (!shell) return false;
    if (isDrawerLayout()) {
      return shell.classList.contains("nav-open");
    }
    return !shell.classList.contains("nav-collapsed");
  }

  function setNavShown(open) {
    const shell = app();
    const button = toggle();
    if (!shell) return;
    if (isDrawerLayout()) {
      shell.classList.toggle("nav-open", open);
      shell.classList.remove("nav-collapsed");
    } else {
      shell.classList.toggle("nav-collapsed", !open);
      shell.classList.remove("nav-open");
    }
    if (button) {
      button.setAttribute("aria-expanded", open ? "true" : "false");
    }
  }

  function syncBreadcrumb() {
    const crumb = document.getElementById("crumb-current");
    if (!crumb) return;
    const activeLabel = document.querySelector(".nav button.active .nav-label");
    if (activeLabel) {
      crumb.textContent = activeLabel.textContent.trim();
    }
  }

  function bindToggle() {
    const button = toggle();
    if (!button || button.dataset.shellBound === "1") return;
    button.dataset.shellBound = "1";
    button.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      setNavShown(!isNavShown());
    });
  }

  document.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    if (!target) return;

    if (target.closest("#sidebar-scrim")) {
      setNavShown(false);
      return;
    }

    const navButton = target.closest(".nav button");
    if (navButton) {
      window.requestAnimationFrame(syncBreadcrumb);
      if (isDrawerLayout()) {
        setNavShown(false);
      }
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && app()?.classList.contains("nav-open")) {
      setNavShown(false);
    }
  });

  window.addEventListener("resize", () => {
    const shell = app();
    if (!shell) return;
    if (isDrawerLayout()) {
      shell.classList.remove("nav-collapsed");
    } else {
      shell.classList.remove("nav-open");
    }
    const button = toggle();
    if (button) {
      button.setAttribute("aria-expanded", isNavShown() ? "true" : "false");
    }
  });

  function boot() {
    bindToggle();
    syncBreadcrumb();
    const button = toggle();
    if (button) {
      button.setAttribute("aria-expanded", isNavShown() ? "true" : "false");
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
