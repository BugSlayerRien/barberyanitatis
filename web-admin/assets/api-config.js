/**
 * Resolve API URLs regardless of whether the portal is served from /web-admin/ or project root.
 */
function resolveApiUrl(fileName) {
  const normalizedPath = window.location.pathname.replace(/\\/g, "/");
  const marker = "/web-admin/";
  const markerIndex = normalizedPath.indexOf(marker);

  if (markerIndex >= 0) {
    const projectRoot = normalizedPath.slice(0, markerIndex);
    return `${projectRoot}/api/${fileName}`;
  }

  return `../api/${fileName}`;
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
      `Server returned invalid JSON (HTTP ${response.status}). Check that Apache/PHP is running and the API path is correct.`
    );
  }
}
