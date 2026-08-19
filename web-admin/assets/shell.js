/**
 * Portal shell: presentation-only chrome shared by the Admin and Receptionist
 * portals. Handles the responsive sidebar drawer and keeps the top bar
 * breadcrumb in sync with the active navigation item.
 *
 * This file never touches data, API calls or view logic.
 */
(function initPortalShell() {
  const MOBILE_QUERY = "(max-width: 1024px)";

  function app() {
    return document.querySelector(".app");
  }

  function isDrawerLayout() {
    return window.matchMedia(MOBILE_QUERY).matches;
  }

  function setDrawer(open) {
    const shell = app();
    const toggle = document.getElementById("sidebar-toggle");
    if (!shell) return;
    shell.classList.toggle("nav-open", open);
    if (toggle) {
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
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

  document.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target : null;
    if (!target) return;

    if (target.closest("#sidebar-toggle")) {
      setDrawer(!app()?.classList.contains("nav-open"));
      return;
    }

    if (target.closest("#sidebar-scrim")) {
      setDrawer(false);
      return;
    }

    const navButton = target.closest(".nav button");
    if (navButton) {
      // App scripts update `.active` on their own click handler first.
      window.requestAnimationFrame(syncBreadcrumb);
      if (isDrawerLayout()) {
        setDrawer(false);
      }
    }
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && app()?.classList.contains("nav-open")) {
      setDrawer(false);
    }
  });

  window.addEventListener("resize", () => {
    if (!isDrawerLayout()) {
      setDrawer(false);
    }
  });

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", syncBreadcrumb);
  } else {
    syncBreadcrumb();
  }
})();
