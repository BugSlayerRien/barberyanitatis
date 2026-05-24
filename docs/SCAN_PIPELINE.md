# AI scan pipeline (staging vs live preview)

## Overview

| Step | Where | Technology |
|------|--------|------------|
| Real-time face tracking | Device camera | ML Kit (mobile) / MediaPipe (web) |
| 3-angle capture | `AiFaceScanPage` staging | Flutter |
| Vision analysis | `face_scan.php` → `analyzeCaptures` | **Python** `ai-service` (face shape, hair length, **hair texture**, mask coverage / bald hint, **hair color**) |
| Catalog ranking | `FaceScanResultsPage` | **PHP** `variant_ranking.php` + `ai_scan.php` (`rankByFeatures`, `recommendWithInsights`; optional Python style boost / prior-scan de-dupe) |
| Generative try-on (optional) | Results page | Replicate Flux via `face_scan.php` |
| Live overlay | `AiFaceScanPage` (`livePreviewOnly: true`) | PNG overlay only — **no ranking** |

## Required services

1. **Apache + PHP API** (`AI_SERVICE_URL` in `.env`)
2. **Python ai-service** for accurate recommendations:
   ```bash
   cd ai-service
   uvicorn api:app --host 127.0.0.1 --port 8000
   ```
3. **`REPLICATE_API_TOKEN`** (optional) for AI preview images on the results page

If `ai-service` is not running, `analyzeCaptures` fails and the app may fall back to profile hair texture or `Wavy` — recommendations will be less accurate.

## Data flow

```
Staging capture → uploadCaptures (PHP)
               → analyzeCaptures (Python: faceShape, hairTexture, hairLength)
               → FaceScanResultsPage (PHP: recommendWithInsights using analyzed attributes)
               → optional livePreviewOnly (overlay only, same selected style)
```

## What not to use for final recommendations

- Live scanner `rankByFeatures` auto-fetch (disabled)
- Heuristic `Detected face: Round` chips on the live overlay screen
- Stale `UserSession.lastScan` from a previous visit (results page uses widget params from the current analysis)
