/**
 * Resolve API URLs for local XAMPP and production (Vercel → Render).
 *
 * Production default: https://barberyanitatis.onrender.com
 * Override anytime: window.API_BASE_URL = 'https://...'; or localStorage API_BASE_URL
 *
 * Cold start (plain English): free Render servers sleep after idle time.
 * The first request wakes them (often 30–90s). During wake-up the browser
 * may show "Failed to fetch". Retrying after a short wait usually works.
 */
const DEFAULT_PRODUCTION_API_BASE = "https://barberyanitatis.onrender.com";
const API_FETCH_TIMEOUT_MS = 90000;
const API_RETRY_ATTEMPTS = 3;

function getApiBaseUrl() {
  const fromWindow =
    typeof window !== "undefined" && typeof window.API_BASE_URL === "string"
      ? window.API_BASE_URL.trim()
      : "";
  const fromStorage =
    typeof localStorage !== "undefined"
      ? (localStorage.getItem("API_BASE_URL") || "").trim()
      : "";
  const configured = (fromWindow || fromStorage).replace(/\/$/, "");
  if (configured) {
    return configured;
  }

  const host =
    typeof window !== "undefined" && window.location
      ? window.location.hostname
      : "";

  // Local XAMPP: keep same-origin relative /api paths
  if (host === "localhost" || host === "127.0.0.1") {
    return "";
  }

  return DEFAULT_PRODUCTION_API_BASE;
}

function resolveApiUrl(fileName) {
  const clean = String(fileName || "").replace(/^\//, "");
  const absoluteBase = getApiBaseUrl();
  if (absoluteBase) {
    return `${absoluteBase}/${clean}`;
  }

  const normalizedPath = window.location.pathname.replace(/\\/g, "/");
  const marker = "/web-admin/";
  const markerIndex = normalizedPath.indexOf(marker);

  if (markerIndex >= 0) {
    const projectRoot = normalizedPath.slice(0, markerIndex);
    return `${projectRoot}/api/${clean}`;
  }

  return `../api/${clean}`;
}

function friendlyNetworkError(error) {
  const name = error && error.name ? String(error.name) : "";
  const message = error && error.message ? String(error.message) : "";
  if (name === "AbortError") {
    return "The API took too long to respond. On free Render it may be waking up — wait about a minute and try again.";
  }
  if (/failed to fetch|networkerror|load failed|network request failed/i.test(message)) {
    return "Could not reach the API. If you just opened the portal, wait ~30–60s (server waking up) then retry.";
  }
  return message || "Network request failed";
}

async function parseJsonResponse(response) {
  const raw = await response.text();
  if (!raw) {
    return {};
  }

  try {
    return JSON.parse(raw);
  } catch (error) {
    throw new Error(
      `Server returned invalid JSON (HTTP ${response.status}). Check that the API is running and API_BASE_URL is correct.`
    );
  }
}

/**
 * fetch with timeout + retries for Render cold starts / dropped connections.
 */
function portalAuthHeaders() {
  try {
    const token =
      (typeof sessionStorage !== "undefined" && sessionStorage.getItem("portalToken")) || "";
    if (!token) return {};
    return {
      Authorization: `Bearer ${token}`,
      "X-Portal-Token": token,
    };
  } catch (_) {
    return {};
  }
}

function storePortalSession(data) {
  const token = data?.portalToken || data?.user?.portalToken || "";
  if (token) {
    sessionStorage.setItem("portalToken", token);
  }
}

async function fetchWithRetry(url, options = {}, attempts = API_RETRY_ATTEMPTS) {
  let lastError = null;

  for (let attempt = 0; attempt < attempts; attempt += 1) {
    const controller = new AbortController();
    const externalSignal = options.signal;
    const onExternalAbort = () => controller.abort();
    if (externalSignal) {
      if (externalSignal.aborted) {
        controller.abort();
      } else {
        externalSignal.addEventListener("abort", onExternalAbort, { once: true });
      }
    }

    const timeoutId = window.setTimeout(() => controller.abort(), API_FETCH_TIMEOUT_MS);

    try {
      const response = await fetch(url, {
        ...options,
        headers: {
          ...portalAuthHeaders(),
          ...(options.headers || {}),
        },
        signal: controller.signal,
      });
      return response;
    } catch (error) {
      lastError = error;
      if (attempt < attempts - 1) {
        await new Promise((resolve) => window.setTimeout(resolve, 2500 * (attempt + 1)));
      }
    } finally {
      window.clearTimeout(timeoutId);
      if (externalSignal) {
        externalSignal.removeEventListener("abort", onExternalAbort);
      }
    }
  }

  throw new Error(friendlyNetworkError(lastError));
}

/** Fire-and-forget wake so the first real click is less likely to fail. */
function wakeApiServer() {
  const base = getApiBaseUrl();
  if (!base) {
    return;
  }
  fetchWithRetry(`${base}/ai_status.php`, { method: "GET", cache: "no-store" }, 2).catch(() => {});
}

if (typeof window !== "undefined") {
  window.addEventListener("DOMContentLoaded", () => {
    wakeApiServer();
  });
}
