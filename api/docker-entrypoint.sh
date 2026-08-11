#!/bin/bash
set -euo pipefail

# Render injects PORT; Apache images default to 80.
PORT="${PORT:-80}"

sed -i "s/Listen 80/Listen ${PORT}/" /etc/apache2/ports.conf
sed -i "s/:80>/:${PORT}>/" /etc/apache2/sites-available/000-default.conf

# Mirror Render env into /var/www/.env for load_project_env()
# (http.php looks one directory above the API docroot).
ENV_FILE="/var/www/.env"
{
  echo "# Generated at container start — do not commit"
  for key in \
    DB_URL DB_DSN DB_HOST DB_NAME DB_USER DB_PASS \
    GEMINI_API_KEY AI_API_KEY GEMINI_MODEL GEMINI_IMAGE_API_KEY GEMINI_IMAGE_MODEL \
    XAI_API_KEY GROK_IMAGE_API_KEY GROK_IMAGE_MODEL \
    AI_TRYON_PROVIDER AI_TRYON_ALLOW_FALLBACK AI_TRYON_STYLE_LIMIT AI_TRYON_UNLIMITED \
    REPLICATE_API_TOKEN REPLICATE_FLUX_MODEL REPLICATE_TRYON_VERSION \
    AI_SERVICE_URL AI_SERVICE_INSECURE_SSL API_INSECURE_SSL \
    BOOKING_WINDOW_DAYS \
    GOOGLE_ALLOWED_CLIENT_IDS \
    PASSWORD_RESET_BASE_URL PASSWORD_RESET_MAIL_FROM PASSWORD_RESET_DEBUG_TOKEN \
    APP_DEBUG APP_ENV
  do
    val="$(printenv "$key" 2>/dev/null || true)"
    if [ -n "${val}" ]; then
      esc="${val//\"/\\\"}"
      echo "${key}=\"${esc}\""
    fi
  done
} > "${ENV_FILE}"

chown www-data:www-data "${ENV_FILE}" 2>/dev/null || true
chmod 640 "${ENV_FILE}" 2>/dev/null || true

exec "$@"
