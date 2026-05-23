/**
 * Shared UI: loading overlay, toasts, confirm/message dialogs (no browser alert/confirm).
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
          <p class="app-loading-text">Loading…</p>
        </div>
      `;
      document.body.appendChild(overlay);
    }
    loadingCount += 1;
    const textEl = overlay.querySelector(".app-loading-text");
    if (textEl) {
      textEl.textContent = message || "Loading…";
    }
    overlay.hidden = false;
    overlay.setAttribute("aria-hidden", "false");
  }

  function hideLoading() {
    loadingCount = Math.max(0, loadingCount - 1);
    const overlay = document.getElementById("app-loading");
    if (overlay && loadingCount === 0) {
      overlay.hidden = true;
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

  function toast(message, type) {
    const host = ensureToastHost();
    const item = document.createElement("div");
    item.className = `toast toast-${type || "info"}`;
    item.textContent = String(message || "");
    host.appendChild(item);
    window.setTimeout(() => {
      item.classList.add("toast-out");
      window.setTimeout(() => item.remove(), 220);
    }, 3200);
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
    confirmBtn.className = opts.danger ? "btn danger" : "btn";

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
      showLoading(loadingMessage || "Please wait…");
    }

    const controller = new AbortController();
    const timeoutId = window.setTimeout(() => controller.abort(), 45000);

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: controller.signal,
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
        throw new Error("Request timed out. Check your connection and try again.");
      }
      throw error;
    } finally {
      window.clearTimeout(timeoutId);
      if (useLoading) {
        hideLoading();
      }
    }
  }

  global.PortalUi = {
    showLoading,
    hideLoading,
    resetLoading,
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
