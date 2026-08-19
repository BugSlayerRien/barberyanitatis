/**
 * Shared UI: loading overlay, button loading, region loading, toasts, confirm/message dialogs.
 */
(function initPortalUi(global) {
  let loadingCount = 0;

  function ensureToastHost() {
    let host = document.getElementById("toast-host");
    if (!host) {
      host = document.createElement("div");
      host.id = "toast-host";
      host.className = "toast-host";
      host.setAttribute("aria-live", "polite");
      document.body.appendChild(host);
    }
    return host;
  }

  function showLoading(message) {
    let overlay = document.getElementById("app-loading");
    if (!overlay) {
      overlay = document.createElement("div");
      overlay.id = "app-loading";
      overlay.className = "app-loading";
      overlay.hidden = true;
      overlay.innerHTML = `
        <div class="app-loading-card" role="status" aria-live="polite">
          <div class="app-loading-spinner" aria-hidden="true"></div>
          <p class="app-loading-text">Loading...</p>
        </div>
      `;
      document.body.appendChild(overlay);
    }
    loadingCount += 1;
    const textEl = overlay.querySelector(".app-loading-text");
    if (textEl) {
      textEl.textContent = message || "Loading...";
    }
    overlay.hidden = false;
    overlay.setAttribute("aria-hidden", "false");
  }

  function hideLoading() {
    loadingCount = Math.max(0, loadingCount - 1);
    const overlay = document.getElementById("app-loading");
    if (overlay && loadingCount === 0) {
      overlay.hidden = true;
      overlay.setAttribute("aria-hidden", "true");
    }
  }

  /** Force-hide overlay (e.g. after init batch or stuck parallel requests). */
  function resetLoading() {
    loadingCount = 0;
    const overlay = document.getElementById("app-loading");
    if (overlay) {
      overlay.hidden = true;
      overlay.setAttribute("aria-hidden", "true");
    }
  }

  async function runWithLoading(message, fn) {
    showLoading(message || "Please wait...");
    try {
      return await fn();
    } finally {
      hideLoading();
    }
  }

  async function withButtonLoading(button, fn, options) {
    const opts = options || {};
    if (typeof fn !== "function") {
      return undefined;
    }
    if (!(button instanceof HTMLElement)) {
      return fn();
    }
    if (button.dataset.loading === "1") {
      return undefined;
    }

    const originalHtml = button.innerHTML;
    const wasDisabled = button.disabled;
    button.dataset.loading = "1";
    button.disabled = true;
    button.classList.add("is-loading");
    button.setAttribute("aria-busy", "true");
    if (opts.label) {
      button.innerHTML = `<span class="btn-spinner" aria-hidden="true"></span><span>${opts.label}</span>`;
    } else {
      button.insertAdjacentHTML("afterbegin", '<span class="btn-spinner" aria-hidden="true"></span>');
    }

    try {
      return await fn();
    } finally {
      button.dataset.loading = "0";
      button.disabled = wasDisabled;
      button.classList.remove("is-loading");
      button.removeAttribute("aria-busy");
      button.innerHTML = originalHtml;
    }
  }

  function setRegionLoading(element, isLoading, message) {
    if (!(element instanceof HTMLElement)) return;
    let cover = element.querySelector(":scope > .region-loading");
    if (isLoading) {
      element.classList.add("is-region-loading");
      element.setAttribute("aria-busy", "true");
      if (!cover) {
        cover = document.createElement("div");
        cover.className = "region-loading";
        cover.innerHTML = `
          <div class="region-loading-inner" role="status">
            <div class="btn-spinner" aria-hidden="true"></div>
            <span class="region-loading-text"></span>
          </div>
        `;
        if (getComputedStyle(element).position === "static") {
          element.style.position = "relative";
        }
        element.appendChild(cover);
      }
      const textEl = cover.querySelector(".region-loading-text");
      if (textEl) {
        textEl.textContent = message || "Loading...";
      }
      cover.hidden = false;
    } else {
      element.classList.remove("is-region-loading");
      element.removeAttribute("aria-busy");
      if (cover) {
        cover.hidden = true;
      }
    }
  }

  const TOAST_ICONS = { success: "✓", error: "!", info: "i" };

  function toast(message, type) {
    const host = ensureToastHost();
    const tone = type || "info";
    const item = document.createElement("div");
    item.className = `toast toast-${tone}`;
    item.setAttribute("role", tone === "error" ? "alert" : "status");

    const icon = document.createElement("span");
    icon.className = "toast-icon";
    icon.setAttribute("aria-hidden", "true");
    icon.textContent = TOAST_ICONS[tone] || TOAST_ICONS.info;

    const text = document.createElement("span");
    text.className = "toast-text";
    text.textContent = String(message || "");

    item.append(icon, text);
    host.appendChild(item);
    window.setTimeout(() => {
      item.classList.add("toast-out");
      window.setTimeout(() => item.remove(), 220);
    }, tone === "error" ? 5000 : 3200);
  }

  function openDialog(id) {
    const dialog = document.getElementById(id);
    if (dialog instanceof HTMLDialogElement) {
      if (!dialog.open) {
        dialog.showModal();
      }
      return dialog;
    }
    return null;
  }

  function closeDialog(id) {
    const dialog = document.getElementById(id);
    if (dialog instanceof HTMLDialogElement && dialog.open) {
      dialog.close();
    }
  }

  function confirmDialog(options) {
    const opts = options || {};
    const dialog = openDialog("confirm-dialog");
    const titleEl = document.getElementById("confirm-dialog-title");
    const messageEl = document.getElementById("confirm-dialog-message");
    const confirmBtn = document.getElementById("confirm-dialog-confirm");
    const cancelBtn = document.getElementById("confirm-dialog-cancel");

    if (!dialog || !confirmBtn || !cancelBtn) {
      return Promise.resolve(false);
    }

    if (titleEl) titleEl.textContent = opts.title || "Confirm";
    if (messageEl) messageEl.textContent = opts.message || "Are you sure?";
    confirmBtn.textContent = opts.confirmLabel || "Confirm";
    cancelBtn.textContent = opts.cancelLabel || "Cancel";
    confirmBtn.className = opts.danger ? "btn danger" : "btn primary";

    return new Promise((resolve) => {
      const cleanup = () => {
        confirmBtn.removeEventListener("click", onConfirm);
        cancelBtn.removeEventListener("click", onCancel);
        dialog.removeEventListener("cancel", onCancel);
        closeDialog("confirm-dialog");
      };
      const onConfirm = () => {
        cleanup();
        resolve(true);
      };
      const onCancel = () => {
        cleanup();
        resolve(false);
      };
      confirmBtn.addEventListener("click", onConfirm);
      cancelBtn.addEventListener("click", onCancel);
      dialog.addEventListener("cancel", onCancel);
    });
  }

  function messageDialog(options) {
    const opts = options || {};
    const dialog = openDialog("message-dialog");
    const titleEl = document.getElementById("message-dialog-title");
    const messageEl = document.getElementById("message-dialog-message");
    const okBtn = document.getElementById("message-dialog-ok");

    if (!dialog || !okBtn) {
      toast(opts.message || "Done", opts.type || "info");
      return Promise.resolve();
    }

    if (titleEl) titleEl.textContent = opts.title || (opts.type === "error" ? "Error" : "Notice");
    if (messageEl) messageEl.textContent = opts.message || "";
    okBtn.textContent = opts.okLabel || "OK";

    return new Promise((resolve) => {
      const cleanup = () => {
        okBtn.removeEventListener("click", onOk);
        dialog.removeEventListener("cancel", onOk);
        closeDialog("message-dialog");
        resolve();
      };
      const onOk = () => cleanup();
      okBtn.addEventListener("click", onOk);
      dialog.addEventListener("cancel", onOk);
    });
  }

  async function fetchJson(url, payload, loadingMessage) {
    const useLoading = loadingMessage !== false;
    if (useLoading) {
      showLoading(loadingMessage || "Please wait...");
    }

    try {
      const doFetch =
        typeof global.fetchWithRetry === "function" ? global.fetchWithRetry : global.fetch;
      const response = await doFetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const raw = await response.text();
      let data = {};
      if (raw) {
        try {
          data = JSON.parse(raw);
        } catch (_) {
          throw new Error("Invalid server response");
        }
      }
      if (!response.ok) {
        const detail = data.details ? ` (${data.details})` : "";
        throw new Error((data.error || "Request failed") + detail);
      }
      return data;
    } catch (error) {
      if (error && error.name === "AbortError") {
        throw new Error(
          "Request timed out. On free Render the API may be waking up — wait about a minute and try again."
        );
      }
      throw error;
    } finally {
      if (useLoading) {
        hideLoading();
      }
    }
  }

  global.PortalUi = {
    showLoading,
    hideLoading,
    resetLoading,
    runWithLoading,
    withButtonLoading,
    setRegionLoading,
    toast,
    confirmDialog,
    messageDialog,
    fetchJson,
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", resetLoading);
  } else {
    resetLoading();
  }
})(window);
