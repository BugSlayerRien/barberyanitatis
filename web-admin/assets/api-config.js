/**
 * Resolve API URLs for local XAMPP and production (Vercel → Render).
 *
 * Production default: https://barberyanitatis.onrender.com
 * Override anytime: window.API_BASE_URL = 'https://...'; or localStorage API_BASE_URL
 */
const DEFAULT_PRODUCTION_API_BASE = "https://barberyanitatis.onrender.com";

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

/** Retry transient network failures (Render cold start, connection reset). */
async function fetchWithRetry(url, options = {}, attempts = 3) {
  let lastError = null;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      return await fetch(url, options);
    } catch (error) {
      lastError = error;
      if (attempt < attempts - 1) {
        await new Promise((resolve) => window.setTimeout(resolve, 2000 * (attempt + 1)));
      }
    }
  }
  throw lastError || new Error("Network request failed");
}
