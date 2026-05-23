"""
Tati's Barbershop — AI try-on sidecar (Replicate Flux + MediaPipe analysis/compositing).
Run: uvicorn api:app --host 127.0.0.1 --port 8000
"""

import asyncio
import base64
import hashlib
import logging
import os
import shutil
import ssl
from pathlib import Path

import certifi

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

from dotenv import load_dotenv

_service_dir = Path(__file__).resolve().parent
load_dotenv(_service_dir / ".env")
load_dotenv(_service_dir.parent / ".env")

import cv2
import httpx
import mediapipe as mp
import numpy as np
import uvicorn
from mediapipe.tasks import python as mp_tasks
from mediapipe.tasks.python import vision
from fastapi import FastAPI, File, Form, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_DIR = Path(__file__).resolve().parent / "temp_uploads"
UPLOAD_DIR.mkdir(exist_ok=True)

MODEL_DIR = Path(__file__).resolve().parent / "models"
MODEL_PATH = MODEL_DIR / "face_landmarker.task"
MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/face_landmarker/"
    "face_landmarker/float16/1/face_landmarker.task"
)

_face_landmarker: vision.FaceLandmarker | None = None

REPLICATE_API_TOKEN = os.environ.get("REPLICATE_API_TOKEN", "")


def httpx_ssl_verify() -> ssl.SSLContext | bool:
    """TLS verify settings for outbound HTTPS (Replicate, model download)."""
    if os.environ.get("AI_SERVICE_INSECURE_SSL", "").strip().lower() in (
        "1",
        "true",
        "yes",
    ):
        logger.warning(
            "AI_SERVICE_INSECURE_SSL is enabled — TLS certificate verification is OFF (local dev only)"
        )
        return False
    return ssl.create_default_context(cafile=certifi.where())

STYLE_PROMPTS = {
    "buzz_cut": "buzz cut hairstyle, very short uniform hair, clean fade",
    "french_crop": "french crop hairstyle, short textured top, faded sides",
    "low_fade": "low fade hairstyle, gradual fade on sides, natural top",
    "blowout_taper": "blowout taper hairstyle, voluminous top, tapered sides",
    "two_block": "two block hairstyle, long top short sides korean style",
    "barbers_cut": "classic barbers cut, neat professional hairstyle",
    "modern_mullet": "modern mullet hairstyle, short sides long back",
    "edgar_cut": "edgar cut hairstyle, straight fringe sharp line",
    "caesar_cut": "caesar cut hairstyle, short horizontal fringe",
    "textured_crop": "textured crop wavy hairstyle, messy natural waves",
    "messy_quiff": "messy quiff wavy hairstyle, voluminous front",
    "modern_curtains": "modern curtains hairstyle, middle part wavy",
    "wavy_mod_cut": "wavy mod cut hairstyle, bowl shape with waves",
    "wavy_fringe": "wavy fringe hairstyle, wavy hair with fringe",
    "wavy_burst_fade": "wavy burst fade hairstyle, waves on top fade sides",
    "wavy_side_sweep": "wavy side sweep hairstyle, swept to one side",
    "wavy_messy_top": "wavy messy top hairstyle, natural messy waves",
    "curly_taper": "curly taper hairstyle, curly top tapered sides",
    "curly_modern_mullet": "curly modern mullet, curly long back short sides",
    "curly_burst_fade": "curly burst fade, curly afro burst fade sides",
    "curly_mid_fade": "curly mid fade hairstyle, curls on top mid fade",
    "curly_drop_fade": "curly drop fade hairstyle, curly top drop fade",
    "curly_short_crop": "curly short crop hairstyle, short tight curls",
    "curly_crew_cut": "curly crew cut hairstyle, short curly uniform",
    "curly_edgar": "curly edgar hairstyle, curly hair straight fringe",
}

FACE_SHAPE_STYLES = {
    "oval": ["buzz_cut", "french_crop", "two_block", "messy_quiff", "curly_taper"],
    "round": ["edgar_cut", "low_fade", "french_crop", "blowout_taper", "curly_mid_fade"],
    "square": ["two_block", "messy_quiff", "modern_curtains", "wavy_side_sweep", "curly_modern_mullet"],
    "heart": ["textured_crop", "wavy_side_sweep", "curly_short_crop", "caesar_cut", "wavy_fringe"],
    "oblong": ["blowout_taper", "wavy_burst_fade", "curly_mid_fade", "modern_curtains", "wavy_messy_top"],
}

STYLE_MIN_LENGTH = {
    "buzz_cut": 0,
    "french_crop": 0,
    "caesar_cut": 0,
    "low_fade": 0,
    "edgar_cut": 0,
    "barbers_cut": 0,
    "curly_crew_cut": 0,
    "curly_short_crop": 0,
    "curly_edgar": 0,
    "blowout_taper": 1,
    "textured_crop": 1,
    "messy_quiff": 1,
    "wavy_fringe": 1,
    "wavy_burst_fade": 1,
    "wavy_side_sweep": 1,
    "wavy_messy_top": 1,
    "curly_taper": 1,
    "curly_burst_fade": 1,
    "curly_mid_fade": 1,
    "curly_drop_fade": 1,
    "two_block": 2,
    "modern_curtains": 2,
    "wavy_mod_cut": 2,
    "modern_mullet": 2,
    "curly_modern_mullet": 3,
}

HAIR_LENGTH_LABELS = {0: "very short", 1: "short", 2: "medium", 3: "long"}

LENGTH_STYLE_HINTS = {
    0: "Keep the result very short (buzz/crop length). Do not add visible length.",
    1: "Keep hair short; do not extend past the ears or add long layers.",
    2: "Keep medium length; restyle only, do not add shoulder-length hair.",
    3: "You may reshape or shorten slightly, but do not remove all length if the style needs volume.",
}

STYLE_NAMES = {
    "buzz_cut": "Buzz Cut",
    "french_crop": "French Crop",
    "low_fade": "Low Fade",
    "blowout_taper": "Blowout Taper",
    "two_block": "Two Block",
    "barbers_cut": "Barbers Cut",
    "modern_mullet": "Modern Mullet",
    "edgar_cut": "Edgar Cut",
    "caesar_cut": "Caesar Cut",
    "textured_crop": "Textured Crop",
    "messy_quiff": "Messy Quiff",
    "modern_curtains": "Modern Curtains",
    "wavy_mod_cut": "Wavy Mod Cut",
    "wavy_fringe": "Wavy Fringe",
    "wavy_burst_fade": "Wavy Burst Fade",
    "wavy_side_sweep": "Wavy Side Sweep",
    "wavy_messy_top": "Wavy Messy Top",
    "curly_taper": "Curly Taper",
    "curly_modern_mullet": "Curly Modern Mullet",
    "curly_burst_fade": "Curly Burst Fade",
    "curly_mid_fade": "Curly Mid Fade",
    "curly_drop_fade": "Curly Drop Fade",
    "curly_short_crop": "Curly Short Crop",
    "curly_crew_cut": "Curly Crew Cut",
    "curly_edgar": "Curly Edgar",
}

def ensure_face_landmarker_model() -> Path:
    MODEL_DIR.mkdir(exist_ok=True)
    if MODEL_PATH.exists():
        return MODEL_PATH

    logger.info("Downloading face_landmarker.task (one-time, ~3 MB)...")
    last_error: Exception | None = None
    try:
        import certifi
        import ssl
        import urllib.request

        ctx = ssl.create_default_context(cafile=certifi.where())
        with urllib.request.urlopen(MODEL_URL, context=ctx, timeout=120) as response:
            MODEL_PATH.write_bytes(response.read())
        return MODEL_PATH
    except Exception as exc:
        last_error = exc

    try:
        with httpx.Client(
            timeout=120, follow_redirects=True, verify=httpx_ssl_verify()
        ) as client:
            response = client.get(MODEL_URL)
            response.raise_for_status()
            MODEL_PATH.write_bytes(response.content)
        return MODEL_PATH
    except Exception as exc:
        last_error = exc

    if os.name == "nt":
        try:
            import subprocess

            curl_args = ["curl.exe", "-fsSL", "-o", str(MODEL_PATH), MODEL_URL]
            # Windows schannel revocation check often fails on dev machines.
            curl_args.insert(1, "--ssl-no-revoke")
            subprocess.run(curl_args, check=True, timeout=180)
            if MODEL_PATH.exists() and MODEL_PATH.stat().st_size > 1000:
                return MODEL_PATH
        except Exception as exc:
            last_error = exc

    raise RuntimeError(
        "Could not download face_landmarker.task. "
        f"Save it manually to {MODEL_PATH} from {MODEL_URL}. "
        f"Last error: {last_error}"
    ) from last_error


def get_face_landmarker() -> vision.FaceLandmarker:
    global _face_landmarker
    if _face_landmarker is None:
        model_path = ensure_face_landmarker_model()
        options = vision.FaceLandmarkerOptions(
            base_options=mp_tasks.BaseOptions(model_asset_path=str(model_path)),
            running_mode=vision.RunningMode.IMAGE,
            num_faces=1,
            min_face_detection_confidence=0.5,
            min_face_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        _face_landmarker = vision.FaceLandmarker.create_from_options(options)
    return _face_landmarker


def detect_face_landmarks(rgb: np.ndarray):
    """Return normalized face landmarks for the first face, or None."""
    if not rgb.flags["C_CONTIGUOUS"]:
        rgb = np.ascontiguousarray(rgb)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
    result = get_face_landmarker().detect(mp_image)
    if not result.face_landmarks:
        return None
    return result.face_landmarks[0]


VIEW_ANGLE_HINTS = {
    "front": "Front view: keep the subject looking straight at the camera.",
    "left": "This run uses your LEFT-profile photo only.",
    "right": "This run uses your RIGHT-profile photo only (different head turn than the left photo).",
}

REPLICATE_MODEL = os.environ.get("REPLICATE_FLUX_MODEL", "black-forest-labs/flux-kontext-pro")

HAIR_OUTLINE_INDICES = [
    10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365,
    379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93,
    234, 127, 162, 21, 54, 103, 67, 109,
]
EYEBROW_INDICES = [
    70, 63, 105, 66, 107, 55, 65, 52, 53, 46,
    300, 293, 334, 296, 336, 285, 295, 282, 283, 276,
]


def normalize_style_key(raw: str) -> str:
    import re

    key = raw.strip().lower()
    key = re.sub(r"[^a-z0-9]+", "_", key).strip("_")
    return key


def resolve_style_key(style_name: str, style_code: str = "") -> str:
    if style_code:
        code_key = normalize_style_key(style_code)
        if code_key in STYLE_PROMPTS:
            return code_key
    name_key = normalize_style_key(style_name)
    if name_key in STYLE_PROMPTS:
        return name_key
    name_lower = style_name.lower()
    for key in STYLE_PROMPTS:
        if key.replace("_", " ") in name_lower:
            return key
    return "barbers_cut"


def profile_pose_lock_sentence(image_path: Path) -> str:
    img = cv2.imread(str(image_path))
    if img is None:
        return "Preserve the exact head pose and camera framing from this input image."

    h, w = img.shape[:2]
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    landmarks = detect_face_landmarks(rgb)
    if landmarks is None:
        return "Preserve the exact head pose and camera framing from this input image."

    nose_x = landmarks[1].x * w
    ear_left = landmarks[234].x * w
    ear_right = landmarks[454].x * w
    mid = 0.5 * (ear_left + ear_right)
    offset = nose_x - mid
    thresh = 0.025 * max(w, 1)

    if offset > thresh:
        return (
            "PHOTO GEOMETRY LOCK: The nose points toward the RIGHT side of this image. "
            "Keep this exact LEFT-profile head turn — do not rotate toward the camera, "
            "do not mirror the image, and do not output the opposite profile."
        )
    if offset < -thresh:
        return (
            "PHOTO GEOMETRY LOCK: The nose points toward the LEFT side of this image. "
            "Keep this exact RIGHT-profile head turn — do not rotate toward the camera, "
            "do not mirror the image, and do not output the opposite profile."
        )

    return (
        "PHOTO GEOMETRY LOCK: Face is roughly forward; keep the exact head pose and framing from this input."
    )


def build_hair_only_prompt(style_description: str, hair_length_level: int = 1) -> str:
    length_hint = LENGTH_STYLE_HINTS.get(hair_length_level, LENGTH_STYLE_HINTS[1])
    current_label = HAIR_LENGTH_LABELS.get(hair_length_level, "short")
    return (
        f"Change ONLY the hair to: {style_description}. "
        f"The person's current hair length is {current_label}. {length_hint} "
        "Keep the exact same person, face, facial features, skin, expression, "
        "eyes, eyebrows shape position, nose, mouth, ears, neck, clothing, pose, "
        "background, room, lighting, shadows, and camera angle. "
        "Do not change or replace the background. Do not retouch the face or body. "
        "Do not add extra hair volume, height, or bulk above the natural hairline or crown. "
        "Keep the hairline position realistic, not a flat block on top of the head. "
        "Hair modification only, everything else pixel-identical."
    )


def styles_for_length(length_level: int) -> list[str]:
    return [key for key in STYLE_PROMPTS if STYLE_MIN_LENGTH.get(key, 1) <= length_level]


def recommend_styles(face_shape: str, length_level: int, limit: int = 5) -> list[str]:
    achievable = set(styles_for_length(length_level))
    ranked: list[str] = []
    for key in FACE_SHAPE_STYLES.get(face_shape, FACE_SHAPE_STYLES["oval"]):
        if key in achievable and key not in ranked:
            ranked.append(key)
    for key in sorted(achievable):
        if key not in ranked:
            ranked.append(key)
    return ranked[:limit]


async def save_upload(upload: UploadFile, path: Path) -> None:
    with open(path, "wb") as f:
        shutil.copyfileobj(upload.file, f)


def prepare_image_bytes(image_path: Path, max_side: int = 1280) -> bytes:
    img = cv2.imread(str(image_path))
    if img is None:
        raise ValueError(f"Could not read image: {image_path}")

    h, w = img.shape[:2]
    if max(h, w) > max_side:
        scale = max_side / max(h, w)
        img = cv2.resize(img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)

    success, encoded = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 90])
    if not success:
        raise ValueError(f"Could not encode image: {image_path}")
    return encoded.tobytes()


def create_hair_mask(image_path: Path) -> np.ndarray | None:
    img = cv2.imread(str(image_path))
    if img is None:
        return None

    h, w = img.shape[:2]
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    landmarks = detect_face_landmarks(rgb)
    if landmarks is None:
        return None

    def point(idx: int) -> np.ndarray:
        return np.array([landmarks[idx].x * w, landmarks[idx].y * h], dtype=np.float32)

    outline = np.array([point(i) for i in HAIR_OUTLINE_INDICES], dtype=np.int32)
    eyebrow_y = float(np.mean([point(i)[1] for i in EYEBROW_INDICES]))
    chin_y = float(point(152)[1])
    face_height = max(chin_y - float(point(10)[1]), 1.0)

    clipped = outline.copy().astype(np.float32)
    for i in range(len(clipped)):
        if clipped[i][1] > eyebrow_y:
            clipped[i][1] = eyebrow_y

    forehead_top = float(point(10)[1])
    top_y = float(np.min(clipped[:, 1]))
    temple_left_x = float(point(234)[0])
    temple_right_x = float(point(454)[0])
    head_center_x = (temple_left_x + temple_right_x) / 2.0
    head_half_width = max((temple_right_x - temple_left_x) / 2.0, w * 0.08)

    extend = int(face_height * 0.10)
    cap_y = max(0.0, min(top_y, forehead_top) - extend)
    extra = []
    for x_frac in np.linspace(0.35, 0.65, 5):
        x = head_center_x + (x_frac - 0.5) * 2 * head_half_width * 0.85
        extra.append([np.clip(x, 0, w - 1), cap_y])
    clipped = np.vstack([clipped, np.array(extra, dtype=np.float32)])

    mask = np.zeros((h, w), dtype=np.uint8)
    hull = cv2.convexHull(clipped.astype(np.int32))
    cv2.fillConvexPoly(mask, hull, 255)

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))
    mask = cv2.erode(mask, kernel, iterations=2)

    blur_size = int(face_height * 0.06) | 1
    blur_size = max(blur_size, 11)
    if blur_size % 2 == 0:
        blur_size += 1
    mask = cv2.GaussianBlur(mask, (blur_size, blur_size), 0)

    mask_f = mask.astype(np.float32) / 255.0
    hairline_y = int(np.clip(forehead_top, 0, h - 1))
    crown_y = int(np.clip(cap_y, 0, hairline_y))
    if hairline_y > crown_y:
        for row in range(crown_y):
            mask_f[row, :] = 0.0
        for row in range(crown_y, hairline_y):
            t = (row - crown_y) / max(hairline_y - crown_y, 1)
            mask_f[row, :] *= float(t)

    return np.clip(mask_f, 0.0, 1.0)


def composite_hair_only(original_bgr: np.ndarray, edited_bgr: np.ndarray, mask: np.ndarray) -> np.ndarray:
    if edited_bgr.shape[:2] != original_bgr.shape[:2]:
        edited_bgr = cv2.resize(edited_bgr, (original_bgr.shape[1], original_bgr.shape[0]))

    if mask.shape[:2] != original_bgr.shape[:2]:
        mask = cv2.resize(mask, (original_bgr.shape[1], original_bgr.shape[0]))

    mask = np.clip(mask.astype(np.float32), 0.0, 1.0)
    mask_3 = np.stack([mask, mask, mask], axis=-1)
    blended = edited_bgr.astype(np.float32) * mask_3 + original_bgr.astype(np.float32) * (1.0 - mask_3)
    return np.clip(blended, 0, 255).astype(np.uint8)


def detect_face_shape(image_path: Path) -> tuple[str, list[str]]:
    try:
        img = cv2.imread(str(image_path))
        if img is None:
            return "oval", FACE_SHAPE_STYLES["oval"]

        h, w = img.shape[:2]
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        landmarks = detect_face_landmarks(rgb)
        if landmarks is None:
            return "oval", FACE_SHAPE_STYLES["oval"]

        def get_point(idx: int) -> np.ndarray:
            return np.array([landmarks[idx].x * w, landmarks[idx].y * h])

        face_width = np.linalg.norm(get_point(234) - get_point(454))
        face_length = np.linalg.norm(get_point(10) - get_point(152))
        jaw_width = np.linalg.norm(get_point(172) - get_point(397))
        forehead_width = np.linalg.norm(get_point(67) - get_point(297))
        cheekbone_width = np.linalg.norm(get_point(123) - get_point(352))

        ratio = face_length / face_width if face_width > 0 else 1.0
        jaw_ratio = jaw_width / cheekbone_width if cheekbone_width > 0 else 1.0
        forehead_ratio = forehead_width / cheekbone_width if cheekbone_width > 0 else 1.0

        if ratio > 1.75:
            shape = "oblong"
        elif jaw_ratio > 0.9 and forehead_ratio > 0.9:
            shape = "square"
        elif forehead_ratio > 1.1 and jaw_ratio < 0.85:
            shape = "heart"
        elif ratio < 1.2:
            shape = "round"
        else:
            shape = "oval"

        return shape, FACE_SHAPE_STYLES[shape]

    except Exception:
        return "oval", FACE_SHAPE_STYLES["oval"]


def detect_hair_length(image_path: Path) -> tuple[int, str, float]:
    img = cv2.imread(str(image_path))
    if img is None:
        return 1, HAIR_LENGTH_LABELS[1], 0.0

    h, w = img.shape[:2]
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    landmarks = detect_face_landmarks(rgb)
    if landmarks is None:
        return 1, HAIR_LENGTH_LABELS[1], 0.0

    def point(idx: int) -> np.ndarray:
        return np.array([landmarks[idx].x * w, landmarks[idx].y * h], dtype=np.float32)

    top_y = float(point(10)[1])
    eyebrow_y = float(np.mean([point(i)[1] for i in EYEBROW_INDICES]))
    chin_y = float(point(152)[1])
    left_ear_x = float(point(234)[0])
    right_ear_x = float(point(454)[0])
    face_height = max(chin_y - top_y, 1.0)

    mask = create_hair_mask(image_path)
    if mask is None:
        return 1, HAIR_LENGTH_LABELS[1], 0.0

    hair_pixels = mask > 0.25
    rows = np.where(np.any(hair_pixels, axis=1))[0]
    if len(rows) == 0:
        return 0, HAIR_LENGTH_LABELS[0], 0.0

    bottom_y = float(rows[-1])
    vertical_extent = (bottom_y - top_y) / face_height

    side_band = hair_pixels[
        int(max(0, top_y)) : int(min(h, eyebrow_y + face_height * 0.15)),
        :,
    ]
    cols_left = np.where(np.any(side_band[:, : int(left_ear_x)], axis=0))[0]
    cols_right = np.where(np.any(side_band[:, int(right_ear_x) :], axis=0))[0]
    side_cover = 0.0
    if len(cols_left):
        side_cover = max(side_cover, (left_ear_x - cols_left[0]) / face_height)
    if len(cols_right):
        side_cover = max(side_cover, (cols_right[-1] + int(right_ear_x) - right_ear_x) / face_height)

    hair_zone = mask > 0.2
    below_brow = hair_zone[int(eyebrow_y) : int(min(h, eyebrow_y + face_height * 0.35)), :]
    below_brow_ratio = float(np.mean(below_brow)) if below_brow.size else 0.0

    score = vertical_extent * 0.5 + side_cover * 0.25 + below_brow_ratio * 0.25

    if score < 0.14 or vertical_extent < 0.10:
        level = 0
    elif score < 0.24 or vertical_extent < 0.18:
        level = 1
    elif score < 0.38 or vertical_extent < 0.30:
        level = 2
    else:
        level = 3

    return level, HAIR_LENGTH_LABELS[level], round(score, 3)


def combined_hair_length(image_paths: list[Path]) -> tuple[int, str, float]:
    if not image_paths:
        return 1, HAIR_LENGTH_LABELS[1], 0.0

    levels: list[int] = []
    scores: list[float] = []
    for path in image_paths:
        level, _, score = detect_hair_length(path)
        levels.append(level)
        scores.append(score)

    max_level = max(levels)
    return max_level, HAIR_LENGTH_LABELS[max_level], round(max(scores), 3)


def _hair_region_texture_energy(image_path: Path) -> float | None:
    """Laplacian variance inside the hair mask — higher for curly/coily hair."""
    img = cv2.imread(str(image_path))
    mask = create_hair_mask(image_path)
    if img is None or mask is None:
        return None

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    hair = mask > 0.25
    if not np.any(hair):
        return None

    lap = cv2.Laplacian(gray, cv2.CV_64F)
    return float(np.var(lap[hair]))


def detect_hair_texture(image_paths: list[Path]) -> tuple[str, float]:
    """
    Classify visible hair texture from capture photos.
    Returns Straight, Wavy, or Curly (Coily grouped with Curly for catalog matching).
    """
    energies: list[float] = []
    for path in image_paths:
        energy = _hair_region_texture_energy(path)
        if energy is not None:
            energies.append(energy)

    if not energies:
        return "Wavy", 0.0

    # Median is more stable than mean when one angle has poor mask coverage.
    energy = float(np.median(energies))

    # Thresholds from laplacian variance on hair-mask pixels (tune with shop lighting).
    if energy < 95.0:
        return "Straight", round(energy, 2)
    if energy < 220.0:
        return "Wavy", round(energy, 2)
    return "Curly", round(energy, 2)


async def _poll_replicate_prediction(
    client: httpx.AsyncClient, prediction_id: str
) -> tuple[bytes | None, str | None]:
    for _ in range(120):
        await asyncio.sleep(2)
        poll = await client.get(
            f"https://api.replicate.com/v1/predictions/{prediction_id}",
            headers={"Authorization": f"Bearer {REPLICATE_API_TOKEN}"},
        )
        result = poll.json()
        status = result.get("status")

        if status == "succeeded":
            output_url = result["output"]
            if isinstance(output_url, list):
                output_url = output_url[0]
            img_response = await client.get(output_url)
            return img_response.content, None

        if status in ("failed", "canceled"):
            err = result.get("error") or result.get("logs") or status
            return None, f"Replicate job {status}: {err}"

    return None, "Replicate timed out waiting for the result"


async def generate_view_hairstyle(
    client: httpx.AsyncClient,
    image_path: Path,
    base_prompt: str,
    view_key: str,
    extra: str = "",
) -> tuple[str | None, str | None]:
    try:
        image_bytes = prepare_image_bytes(image_path)
        image_b64 = base64.b64encode(image_bytes).decode()
        data_uri = f"data:image/jpeg;base64,{image_b64}"

        pose_lock = profile_pose_lock_sentence(image_path)
        view_prompt = f"{base_prompt} {pose_lock} {VIEW_ANGLE_HINTS[view_key]}{extra}"
        logger.info("Starting Replicate for %s view", view_key)

        response = await client.post(
            f"https://api.replicate.com/v1/models/{REPLICATE_MODEL}/predictions",
            headers={
                "Authorization": f"Bearer {REPLICATE_API_TOKEN}",
                "Content-Type": "application/json",
            },
            json={
                "input": {
                    "prompt": view_prompt,
                    "input_image": data_uri,
                    "aspect_ratio": "match_input_image",
                    "prompt_upsampling": False,
                    "output_format": "png",
                }
            },
        )

        if response.status_code >= 400:
            body = response.text[:500]
            logger.error("Replicate HTTP %s for %s: %s", response.status_code, view_key, body)
            return None, f"Replicate error ({response.status_code}): {body}"

        prediction = response.json()
        prediction_id = prediction.get("id")
        if not prediction_id:
            detail = prediction.get("detail") or prediction
            return None, f"Replicate did not start ({view_key}): {detail}"

        status = prediction.get("status")
        if status == "succeeded" and prediction.get("output"):
            output_url = prediction["output"]
            if isinstance(output_url, list):
                output_url = output_url[0]
            raw_bytes = (await client.get(output_url)).content
            poll_error = None
        else:
            raw_bytes, poll_error = await _poll_replicate_prediction(client, prediction_id)

        if poll_error:
            return None, f"{view_key} view: {poll_error}"
        if raw_bytes is None:
            return None, f"{view_key} view: no image returned from Replicate"

        edited_arr = np.frombuffer(raw_bytes, dtype=np.uint8)
        edited_bgr = cv2.imdecode(edited_arr, cv2.IMREAD_COLOR)
        original_bgr = cv2.imread(str(image_path))
        hair_mask = create_hair_mask(image_path)

        if original_bgr is not None and edited_bgr is not None and hair_mask is not None:
            final_bgr = composite_hair_only(original_bgr, edited_bgr, hair_mask)
        elif original_bgr is not None and edited_bgr is not None:
            final_bgr = edited_bgr
        else:
            return None, f"{view_key} view: could not composite the result image"

        _, encoded = cv2.imencode(".jpg", final_bgr, [cv2.IMWRITE_JPEG_QUALITY, 95])
        logger.info("Finished %s view", view_key)
        return base64.b64encode(encoded.tobytes()).decode(), None

    except Exception as exc:
        logger.exception("generate_view_hairstyle failed for %s", view_key)
        return None, f"{view_key} view: {exc}"


@app.get("/")
def root():
    return {"status": "Tatis AI try-on sidecar running", "model": REPLICATE_MODEL}


@app.get("/health")
def health():
    return {
        "ok": True,
        "replicate_configured": bool(REPLICATE_API_TOKEN),
        "model": REPLICATE_MODEL,
    }


@app.post("/analyze-face")
async def analyze_face(
    face_image: UploadFile = File(...),
    left_image: UploadFile = File(...),
    right_image: UploadFile = File(...),
):
    try:
        front_path = UPLOAD_DIR / "analyze_front.jpg"
        left_path = UPLOAD_DIR / "analyze_left.jpg"
        right_path = UPLOAD_DIR / "analyze_right.jpg"
        await save_upload(face_image, front_path)
        await save_upload(left_image, left_path)
        await save_upload(right_image, right_path)

        shape, _ = detect_face_shape(front_path)
        paths = [front_path, left_path, right_path]
        length_level, length_label, length_score = combined_hair_length(paths)
        hair_texture, hair_texture_score = detect_hair_texture(paths)
        achievable = styles_for_length(length_level)
        top_styles = recommend_styles(shape, length_level)

        return {
            "face_shape": shape,
            "hair_texture": hair_texture,
            "hair_texture_score": hair_texture_score,
            "hair_length": length_label,
            "hair_length_level": length_level,
            "hair_length_score": length_score,
            "achievable_styles": achievable,
            "top_styles": [{"key": s, "name": STYLE_NAMES.get(s, s)} for s in top_styles],
            "profiles_received": ["front", "left", "right"],
        }
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})


@app.post("/generate")
async def generate_hairstyle(
    face_image: UploadFile = File(...),
    left_image: UploadFile = File(...),
    right_image: UploadFile = File(...),
    style: str = Form(...),
    hair_length_level: int = Form(1),
):
    if not REPLICATE_API_TOKEN:
        return JSONResponse(
            status_code=500,
            content={"error": "REPLICATE_API_TOKEN is not set in ai-service/.env"},
        )

    try:
        views = {
            "front": UPLOAD_DIR / "face.jpg",
            "left": UPLOAD_DIR / "face_left.jpg",
            "right": UPLOAD_DIR / "face_right.jpg",
        }
        await save_upload(face_image, views["front"])
        await save_upload(left_image, views["left"])
        await save_upload(right_image, views["right"])

        length_level = max(0, min(3, int(hair_length_level)))
        style_key = resolve_style_key(style, style)
        style_desc = STYLE_PROMPTS.get(style_key, f"{style} hairstyle")
        achievable = set(styles_for_length(length_level))
        feasible_today = style_key in achievable
        length_note = None
        if not feasible_today:
            length_note = (
                "Hair too short — cannot be done today. "
                "Preview shows how you could look with more length."
            )

        profile_note = (
            " Use the same haircut design on all three photos, but each output must keep "
            "that photo's original head turn and camera angle — do not make every frame face the camera."
        )

        if feasible_today:
            base_prompt = build_hair_only_prompt(style_desc, length_level) + profile_note
        else:
            base_prompt = (
                f"Change ONLY the hair to an aspirational preview of: {style_desc}. "
                "Show how this person could look with enough hair length for this style. "
                "Keep the exact same face, expression, skin, eyes, clothing, pose, "
                "background, and lighting. Do not change the background or face. "
                f"Hair-only edit.{profile_note}"
            )

        replicate_timeout = httpx.Timeout(600.0, connect=60.0)
        result_images: dict[str, str] = {}

        async with httpx.AsyncClient(
            timeout=replicate_timeout, verify=httpx_ssl_verify()
        ) as client:
            for view_key, path in views.items():
                view_b64, err = await generate_view_hairstyle(
                    client, path, base_prompt, view_key
                )
                if err or view_b64 is None:
                    return JSONResponse(
                        status_code=500,
                        content={"error": err or f"Failed to generate {view_key} view"},
                    )
                result_images[view_key] = view_b64

            left_h = hashlib.sha256(result_images["left"].encode()).digest()
            right_h = hashlib.sha256(result_images["right"].encode()).digest()
            if left_h == right_h:
                logger.warning("Left/right identical — retrying right view")
                retry_extra = (
                    " CRITICAL: The right-profile output must NOT match the left-profile output. "
                    "This input is RIGHT profile only: nose must stay toward the LEFT side of the frame."
                )
                view_b64, err = await generate_view_hairstyle(
                    client, views["right"], base_prompt, "right", extra=retry_extra
                )
                if err or view_b64 is None:
                    return JSONResponse(
                        status_code=500,
                        content={
                            "error": (
                                "The AI returned the same image for left and right profiles. "
                                "Try again, or retake the right photo with a clearer head turn."
                            ),
                        },
                    )
                result_images["right"] = view_b64

        return {
            "result_images": result_images,
            "result_image": result_images["front"],
            "style": style_key,
            "feasible_today": feasible_today,
            "length_note": length_note,
        }

    except httpx.TimeoutException:
        logger.exception("Generate request timed out")
        return JSONResponse(
            status_code=500,
            content={
                "error": (
                    "Generation timed out. All 3 views can take several minutes — "
                    "try again or use smaller photos."
                )
            },
        )
    except Exception as e:
        logger.exception("Generate failed")
        return JSONResponse(status_code=500, content={"error": str(e)})


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("AI_SERVICE_PORT", "8000")))
