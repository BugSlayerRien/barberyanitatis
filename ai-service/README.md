# AI try-on sidecar (Python)

MediaPipe face/hair analysis + Replicate Flux Kontext generation with **hair-only compositing** (face and background pixels are restored from the original capture; the AI haircut shape is kept in the hair mask region).

Previews aim for a full **haircut replacement** (same person, face, and background — only hair changes). If a preview looks too subtle, the service retries Replicate with a stronger prompt and blends more of the AI output in the hair region.

## Setup

```bash
cd ai-service
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env
# Edit .env — set REPLICATE_API_TOKEN (same token as tatis_barbershop/.env)
```

## Run

```bash
uvicorn api:app --host 127.0.0.1 --port 8000
```

On first request, the service downloads `models/face_landmarker.task` (~3 MB) automatically.

Health check: `http://127.0.0.1:8000/health`

**Note:** Use Python 3.10–3.13. MediaPipe `0.10.14` has no wheels for 3.13; this project pins `mediapipe>=0.10.30`.

## PHP integration

In project root `.env`:

```env
AI_SERVICE_URL=http://127.0.0.1:8000
```

`face_scan.php` calls this service for `analyzeCaptures` and `generateStylePreviews` when the URL is reachable. **Always run this sidecar for previews** — the PHP-only Replicate fallback does not composite and may change the face/background.

### `analyzeCaptures` outputs (used by PHP recommendations)

| Field | Description |
|-------|-------------|
| `face_shape` | oval, round, square |
| `hair_texture` | Straight, Wavy, or Curly (from `detect_hair_texture()` on captures) |
| `hair_length` / `hair_length_level` | very short → long |

Flutter passes `faceShape` and `hairTexture` from this response into `ai_scan.php` (`recommendWithInsights`). **Ranking stays in PHP**; Python only supplies vision attributes.

See also: `docs/SCAN_PIPELINE.md`.

## Preview compositing

| Env | Default | Description |
|-----|---------|-------------|
| `HAIR_COMPOSITE_MODE` | `full` | `full` replaces whole-head hair from AI; `face_lock` is softer; `off` is dev-only |
| `REPLICATE_FLUX_MODEL` | `black-forest-labs/flux-kontext-pro` | Replicate model id |

`/generate` accepts `style_code`, `style_name`, and legacy `style`. Prefer sending the DB `style_code` (e.g. `wavy_mod_cut`) so prompts map to the correct haircut.

Response includes `preview_diagnostics` per view (`compositeDiff`, `maskMax`, `faceDrift`, `usedRawOutput`).
