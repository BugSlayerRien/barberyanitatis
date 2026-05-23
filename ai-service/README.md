# AI try-on sidecar (Python)

MediaPipe face/hair analysis + Replicate Flux Kontext generation with hair-mask compositing.

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

`face_scan.php` calls this service for `analyzeCaptures` and `generateStylePreviews` when the URL is reachable.

### `analyzeCaptures` outputs (used by PHP recommendations)

| Field | Description |
|-------|-------------|
| `face_shape` | oval, round, square, heart, oblong |
| `hair_texture` | Straight, Wavy, or Curly (from `detect_hair_texture()` on captures) |
| `hair_length` / `hair_length_level` | very short → long |

Flutter passes `faceShape` and `hairTexture` from this response into `ai_scan.php` (`recommendWithInsights`). **Ranking stays in PHP**; Python only supplies vision attributes.

See also: `docs/SCAN_PIPELINE.md`.
