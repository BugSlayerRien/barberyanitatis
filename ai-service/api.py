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

# Headless Render has no GPU. Set these before importing MediaPipe so it does
# not try to dlopen libGLESv2.so.2 at task-graph init.
os.environ.setdefault("MEDIAPIPE_DISABLE_GPU", "1")
os.environ.setdefault("LIBGL_ALWAYS_SOFTWARE", "1")

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
_face_landmarker_unusable = False

# Pixel-level hair segmentation. The previous mask was a convex hull of face
# landmarks plus a 19x19 dilation, which had no idea where hair actually ended:
# on a busy background it swallowed walls and furniture, and every downstream
# measurement (texture energy, colour, coverage, length) then described the
# background instead of the hair. This model gives a real per-pixel hair mask.
HAIR_MODEL_PATH = MODEL_DIR / "hair_segmenter.tflite"
HAIR_MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/image_segmenter/"
    "hair_segmenter/float32/latest/hair_segmenter.tflite"
)
# Category index for hair in the MediaPipe hair segmenter (0 = background).
HAIR_SEGMENT_INDEX = 1

_hair_segmenter: "vision.ImageSegmenter | None" = None
_hair_segmenter_failures = 0
# Unlike the landmarker's permanent latch, retry a few times: a single transient
# failure (cold start, slow model read) should not degrade the process for its
# whole lifetime.
HAIR_SEGMENTER_MAX_FAILURES = 3

# Short-range face detector. FaceLandmarker needs a fairly frontal face and
# returns nothing on a hard profile -- exactly the images the try-on generator
# produces -- which made the orientation check silently skip the views it most
# needed to check. BlazeFace still locates the face and its nose keypoint at
# those angles, so it backs the landmarker up for orientation only.
FACE_DETECTOR_MODEL_PATH = MODEL_DIR / "blaze_face_short_range.tflite"
FACE_DETECTOR_MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/face_detector/"
    "blaze_face_short_range/float16/latest/blaze_face_short_range.tflite"
)
_face_detector = None
_face_detector_failures = 0
FACE_DETECTOR_MAX_FAILURES = 3

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
    "crew_cut": "classic crew cut, short tapered sides, short textured top",
    "pompadour": "pompadour hairstyle, volume swept up and back, faded sides",
}

FACE_SHAPE_STYLES = {
    "oval": [
        "buzz_cut", "french_crop", "two_block", "messy_quiff", "curly_taper",
        "blowout_taper", "wavy_burst_fade", "modern_curtains", "wavy_messy_top",
        "crew_cut",
    ],
    "round": [
        "edgar_cut", "low_fade", "french_crop", "blowout_taper", "curly_mid_fade",
        "textured_crop", "caesar_cut", "wavy_fringe", "pompadour",
    ],
    "square": [
        "two_block", "messy_quiff", "modern_curtains", "wavy_side_sweep",
        "curly_modern_mullet", "curly_short_crop", "pompadour",
    ],
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
    "crew_cut": 0,
    "pompadour": 2,
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
    "crew_cut": "Crew Cut",
    "pompadour": "Pompadour",
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


def ensure_hair_segmenter_model() -> Path:
    """Hair model is committed and baked into the image; download is a fallback."""
    MODEL_DIR.mkdir(exist_ok=True)
    if HAIR_MODEL_PATH.exists() and HAIR_MODEL_PATH.stat().st_size > 1000:
        return HAIR_MODEL_PATH

    logger.info("Downloading hair_segmenter.tflite (one-time, ~0.8 MB)...")
    try:
        import certifi
        import urllib.request

        ctx = ssl.create_default_context(cafile=certifi.where())
        with urllib.request.urlopen(HAIR_MODEL_URL, context=ctx, timeout=120) as response:
            HAIR_MODEL_PATH.write_bytes(response.read())
        return HAIR_MODEL_PATH
    except Exception:
        pass

    with httpx.Client(timeout=120, follow_redirects=True, verify=httpx_ssl_verify()) as client:
        response = client.get(HAIR_MODEL_URL)
        response.raise_for_status()
        HAIR_MODEL_PATH.write_bytes(response.content)
    return HAIR_MODEL_PATH


def get_hair_segmenter():
    """Lazy MediaPipe ImageSegmenter for hair, or None when unavailable."""
    global _hair_segmenter, _hair_segmenter_failures
    if _hair_segmenter is not None:
        return _hair_segmenter
    if _hair_segmenter_failures >= HAIR_SEGMENTER_MAX_FAILURES:
        return None
    try:
        model_path = ensure_hair_segmenter_model()
        base_kwargs = {"model_asset_path": str(model_path)}
        delegate_enum = getattr(mp_tasks.BaseOptions, "Delegate", None)
        if delegate_enum is not None and hasattr(delegate_enum, "CPU"):
            base_kwargs["delegate"] = delegate_enum.CPU
        options = vision.ImageSegmenterOptions(
            base_options=mp_tasks.BaseOptions(**base_kwargs),
            running_mode=vision.RunningMode.IMAGE,
            output_category_mask=True,
        )
        _hair_segmenter = vision.ImageSegmenter.create_from_options(options)
        return _hair_segmenter
    except Exception:
        _hair_segmenter_failures += 1
        logger.exception(
            "Hair segmenter init failed (%s/%s); falling back to the geometric mask.",
            _hair_segmenter_failures,
            HAIR_SEGMENTER_MAX_FAILURES,
        )
        return None


# analyze-face asks for the same mask ~12 times per scan (texture, colour,
# length and coverage each re-derive it for each of the three captures).
# Segmentation inference is the expensive step, so memoise per file identity.
_hair_mask_cache: "dict[tuple[str, float, int], np.ndarray | None]" = {}
_HAIR_MASK_CACHE_MAX = 12


def _hair_mask_cache_key(image_path: Path) -> tuple[str, float, int] | None:
    try:
        stat = image_path.stat()
    except OSError:
        return None
    return (str(image_path), stat.st_mtime, stat.st_size)


def segment_hair_mask(image_path: Path) -> np.ndarray | None:
    """Per-pixel hair mask in [0,1] from the segmentation model, else None."""
    key = _hair_mask_cache_key(image_path)
    if key is not None and key in _hair_mask_cache:
        return _hair_mask_cache[key]
    mask = _segment_hair_mask_uncached(image_path)
    if key is not None:
        if len(_hair_mask_cache) >= _HAIR_MASK_CACHE_MAX:
            _hair_mask_cache.clear()
        _hair_mask_cache[key] = mask
    return mask


def _segment_hair_mask_uncached(image_path: Path) -> np.ndarray | None:
    segmenter = get_hair_segmenter()
    if segmenter is None:
        return None
    try:
        img = cv2.imread(str(image_path))
        if img is None:
            return None
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        if not rgb.flags["C_CONTIGUOUS"]:
            rgb = np.ascontiguousarray(rgb)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = segmenter.segment(mp_image)

        category_mask = getattr(result, "category_mask", None)
        if category_mask is not None:
            mask = category_mask.numpy_view()
            hair = (mask == HAIR_SEGMENT_INDEX).astype(np.float32)
        else:
            confidence = getattr(result, "confidence_masks", None)
            if not confidence or len(confidence) <= HAIR_SEGMENT_INDEX:
                return None
            hair = np.asarray(
                confidence[HAIR_SEGMENT_INDEX].numpy_view(), dtype=np.float32
            )

        if hair.shape[:2] != img.shape[:2]:
            hair = cv2.resize(
                hair, (img.shape[1], img.shape[0]), interpolation=cv2.INTER_LINEAR
            )
        # A near-empty mask is a RESULT, not a failure: the model ran fine and
        # found almost no hair. Returning None here made the caller fall back to
        # the landmark hull, which draws a head-shaped region regardless and then
        # measured scalp and background -- so a bald customer, or one wearing a
        # cap, got confident-looking texture and colour invented from whatever
        # was behind them. Hand back the (almost empty) mask instead and let
        # coverage speak for itself; None now means only "segmentation failed".
        return np.clip(cv2.GaussianBlur(hair, (5, 5), 0), 0.0, 1.0)
    except Exception:
        logger.exception("Hair segmentation failed; using geometric fallback.")
        return None


def get_face_landmarker() -> vision.FaceLandmarker | None:
    global _face_landmarker, _face_landmarker_unusable
    if _face_landmarker_unusable:
        return None
    if _face_landmarker is not None:
        return _face_landmarker
    try:
        model_path = ensure_face_landmarker_model()
        base_kwargs = {"model_asset_path": str(model_path)}
        delegate_enum = getattr(mp_tasks.BaseOptions, "Delegate", None)
        if delegate_enum is not None and hasattr(delegate_enum, "CPU"):
            base_kwargs["delegate"] = delegate_enum.CPU
        options = vision.FaceLandmarkerOptions(
            base_options=mp_tasks.BaseOptions(**base_kwargs),
            running_mode=vision.RunningMode.IMAGE,
            num_faces=1,
            min_face_detection_confidence=0.5,
            min_face_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        _face_landmarker = vision.FaceLandmarker.create_from_options(options)
        return _face_landmarker
    except Exception:
        logger.exception(
            "FaceLandmarker init failed (often missing libGLESv2.so.2 on Render). "
            "Continuing with OpenCV-only analysis."
        )
        _face_landmarker_unusable = True
        return None


def detect_face_landmarks(rgb: np.ndarray):
    """Return normalized face landmarks for the first face, or None."""
    landmarker = get_face_landmarker()
    if landmarker is None:
        return None
    try:
        if not rgb.flags["C_CONTIGUOUS"]:
            rgb = np.ascontiguousarray(rgb)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = landmarker.detect(mp_image)
        if not result.face_landmarks:
            return None
        return result.face_landmarks[0]
    except Exception:
        logger.exception("FaceLandmarker detect failed")
        return None


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


def build_hair_only_prompt(
    style_description: str,
    hair_length_level: int = 1,
    hair_color_label: str = "",
    style_key: str = "",
) -> str:
    """Flux Kontext: direct edit instruction + explicit preservation (Replicate prompting guide)."""
    length_hint = LENGTH_STYLE_HINTS.get(hair_length_level, LENGTH_STYLE_HINTS[1])
    current_label = HAIR_LENGTH_LABELS.get(hair_length_level, "short")
    display_name = STYLE_NAMES.get(style_key, style_description)
    color_clause = ""
    if hair_color_label.strip():
        color_clause = (
            f" Hair color stays natural {hair_color_label.strip()} "
            "(same tone as the input photo — do not bleach or recolor)."
        )
    return (
        f"Change only the hair on this person. Replace the entire haircut on the full head — "
        f"crown, top, sides, temples, sideburns, and back hairline — with a {display_name}: "
        f"{style_description}. {length_hint}{color_clause} "
        "Remove all of the old hairstyle everywhere on the head, not just the tips or one side. "
        "The new cut must look clearly different from the original silhouette — realistic barbershop finish. "
        "Do not paste extra hair onto the forehead skin or cheeks. "
        "Keep the same facial features, skin tone, eyebrows, eyes, eyeglasses if present, ears, "
        "neck, shirt, and room background. "
        "Maintain the original head pose, camera angle, framing, and indoor lighting."
    )


def build_aspirational_hair_prompt(
    style_description: str,
    style_key: str = "",
) -> str:
    display_name = STYLE_NAMES.get(style_key, style_description)
    return (
        f"Change only the hair on this person to preview a {display_name}: {style_description}. "
        "Show how the style could look with slightly more length than today. "
        "Keep the same face, skin, eyes, glasses, clothing, pose, background, and lighting."
    )


def build_focused_hair_retry_prompt(
    style_description: str,
    style_key: str = "",
) -> str:
    display_name = STYLE_NAMES.get(style_key, style_description)
    return (
        f"Replace this person's entire head of hair with a {display_name} ({style_description}). "
        "Change crown, sides, temples, and sideburns — not just edges or tips. "
        "Make the new haircut obvious and well-defined. "
        "Keep the same face, eyeglasses, clothing, pose, and background unchanged."
    )


HAIR_REPLACE_STRENGTH_SUFFIX = (
    " Fully replace every visible part of the old haircut on the whole head. "
    "Do not leave patches of the previous style on the sides or top. "
    "Keep face skin and background identical."
)


def replicate_prediction_input(
    prompt: str, data_uri: str, *, prompt_upsampling: bool = False
) -> dict:
    """Replicate Flux Kontext — image + instruction edit."""
    upsample = prompt_upsampling or os.environ.get(
        "REPLICATE_PROMPT_UPSAMPLING", ""
    ).strip().lower() in ("1", "true", "yes")
    return {
        "prompt": prompt,
        "input_image": data_uri,
        "aspect_ratio": "match_input_image",
        "prompt_upsampling": upsample,
        "output_format": "png",
        "safety_tolerance": 2,
    }


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
    """Hair mask for the analysis pipeline.

    Prefers the segmentation model, which marks actual hair pixels. Falls back
    to the landmark-hull approximation only when segmentation is unavailable --
    that path is a rough head-shaped region, so anything derived from it (hair
    colour especially) should be treated as low confidence.
    """
    segmented = segment_hair_mask(image_path)
    if segmented is not None:
        return segmented
    return _geometric_hair_mask(image_path)


def hair_mask_is_segmented(image_path: Path) -> bool:
    """True when the mask came from the model rather than the hull fallback."""
    return segment_hair_mask(image_path) is not None


def _geometric_hair_mask(image_path: Path) -> np.ndarray | None:
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
    top_y = float(point(10)[1])
    face_height = max(chin_y - top_y, 1.0)
    ear_left = point(234)
    ear_right = point(454)
    jaw_y = float(np.mean([point(172)[1], point(397)[1]]))

    clipped = outline.copy().astype(np.float32)
    for i in range(len(clipped)):
        if clipped[i][1] > eyebrow_y:
            clipped[i][1] = eyebrow_y

    crown_y = float(np.clip(top_y - face_height * 0.16, 0, eyebrow_y - 2))
    side_low_y = float(np.clip(eyebrow_y + face_height * 0.30, eyebrow_y + 2, jaw_y))
    side_out = face_height * 0.10
    side_pts = np.array(
        [
            [ear_left[0] - side_out, crown_y],
            [ear_left[0] - side_out * 0.6, side_low_y],
            [ear_left[0] + side_out * 0.15, side_low_y],
            [ear_right[0] - side_out * 0.15, side_low_y],
            [ear_right[0] + side_out * 0.6, side_low_y],
            [ear_right[0] + side_out, crown_y],
        ],
        dtype=np.float32,
    )
    left_x = float(np.min(clipped[:, 0]))
    right_x = float(np.max(clipped[:, 0]))
    center_x = float(np.mean(clipped[:, 0]))
    crown_pts = np.array(
        [
            [left_x, crown_y],
            [center_x, crown_y - face_height * 0.06],
            [right_x, crown_y],
        ],
        dtype=np.float32,
    )
    hull_pts = np.vstack([clipped, crown_pts, side_pts]).astype(np.int32)

    mask = np.zeros((h, w), dtype=np.uint8)
    hull = cv2.convexHull(hull_pts)
    cv2.fillConvexPoly(mask, hull, 255)

    dilate_k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (19, 19))
    mask = cv2.dilate(mask, dilate_k, iterations=2)

    blur_size = int(face_height * 0.05) | 1
    blur_size = max(blur_size, 11)
    if blur_size % 2 == 0:
        blur_size += 1
    mask = cv2.GaussianBlur(mask, (blur_size, blur_size), 0)

    mask_f = mask.astype(np.float32) / 255.0
    # Clear center face skin below brows; keep temple/side hair columns.
    face_cut = int(np.clip(eyebrow_y + face_height * 0.06, 0, h - 1))
    center_l = int(np.clip(ear_left[0] + (ear_right[0] - ear_left[0]) * 0.22, 0, w - 1))
    center_r = int(np.clip(ear_right[0] - (ear_right[0] - ear_left[0]) * 0.22, 0, w - 1))
    neck_cut = int(np.clip(jaw_y + face_height * 0.05, face_cut, h - 1))
    feather = max(int(face_height * 0.05), 4)
    for row in range(face_cut, neck_cut):
        mask_f[row, center_l:center_r] = 0.0
    for row in range(max(0, face_cut - feather), face_cut):
        t = (row - (face_cut - feather)) / max(feather, 1)
        mask_f[row, center_l:center_r] *= float(t)
    for row in range(neck_cut, h):
        mask_f[row, :] = 0.0

    return np.clip(mask_f, 0.0, 1.0)


def _fallback_crown_hair_mask(image_path: Path) -> np.ndarray | None:
    """Ellipse over crown when landmark hull mask is too weak (dim light, dark hair)."""
    img, landmarks = _landmarks_for_image(image_path)
    if img is None or landmarks is None:
        return None

    h, w = img.shape[:2]

    def point(idx: int) -> np.ndarray:
        return np.array([landmarks[idx].x * w, landmarks[idx].y * h], dtype=np.float32)

    eyebrow_y = float(np.mean([point(i)[1] for i in EYEBROW_INDICES]))
    top_y = float(point(10)[1])
    chin_y = float(point(152)[1])
    face_height = max(chin_y - top_y, 1.0)
    ear_left = point(234)
    ear_right = point(454)
    center_x = int(np.clip((ear_left[0] + ear_right[0]) / 2.0, 0, w - 1))
    center_y = int(np.clip((top_y + eyebrow_y) / 2.0 - face_height * 0.04, 0, h - 1))
    axes = (
        int(max((ear_right[0] - ear_left[0]) * 0.72, w * 0.28)),
        int(max((eyebrow_y - top_y) + face_height * 0.32, face_height * 0.26)),
    )

    mask = np.zeros((h, w), dtype=np.uint8)
    cv2.ellipse(mask, (center_x, center_y), axes, 0, 0, 360, 255, -1)
    mask_f = cv2.GaussianBlur(mask.astype(np.float32) / 255.0, (15, 15), 0)
    face_cut = int(np.clip(eyebrow_y + face_height * 0.10, 0, h - 1))
    for row in range(face_cut, h):
        mask_f[row, :] = 0.0
    return np.clip(mask_f, 0.0, 1.0)


def _landmarks_for_image(image_path: Path):
    img = cv2.imread(str(image_path))
    if img is None:
        return None, None
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    return img, detect_face_landmarks(rgb)


def create_face_preserve_mask(image_path: Path, view_key: str = "front") -> np.ndarray | None:
    """
    Soft mask of face skin / features that must stay pixel-identical (not from AI edit).
    """
    img, landmarks = _landmarks_for_image(image_path)
    if img is None or landmarks is None:
        return None

    h, w = img.shape[:2]

    def point(idx: int) -> np.ndarray:
        return np.array([landmarks[idx].x * w, landmarks[idx].y * h], dtype=np.float32)

    eyebrow_y = float(np.mean([point(i)[1] for i in EYEBROW_INDICES]))
    chin_y = float(point(152)[1])
    top_y = float(point(10)[1])
    face_height = max(chin_y - top_y, 1.0)
    nose = point(1)
    ear_left = point(234)
    ear_right = point(454)
    face_center = np.array([(ear_left[0] + ear_right[0]) / 2.0, (eyebrow_y + chin_y) / 2.0])

    mask = np.zeros((h, w), dtype=np.uint8)
    view = (view_key or "front").lower()

    if view in ("left", "right"):
        profile_dir = 1.0 if view == "left" else -1.0
        if (nose[0] - face_center[0]) * profile_dir < 0:
            profile_dir *= -1.0
        center_x = int(np.clip(face_center[0] + profile_dir * w * 0.04, 0, w - 1))
        center_y = int(np.clip((eyebrow_y + chin_y) / 2.0, 0, h - 1))
        axes = (
            int(max(w * 0.16, face_height * 0.34)),
            int(max(face_height * 0.42, h * 0.12)),
        )
        cv2.ellipse(mask, (center_x, center_y), axes, 0, 0, 360, 255, -1)
    else:
        y_min = eyebrow_y - 0.02 * face_height
        y_max = chin_y + 0.08 * face_height
        pts = []
        for i in range(len(landmarks)):
            p = point(i)
            if y_min <= p[1] <= y_max:
                pts.append(p)
        if len(pts) < 3:
            return None
        hull = cv2.convexHull(np.array(pts, dtype=np.int32))
        cv2.fillConvexPoly(mask, hull, 255)

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13, 13))
    mask = cv2.dilate(mask, kernel, iterations=1)

    blur = max(int(face_height * 0.045) | 1, 15)
    if blur % 2 == 0:
        blur += 1
    mask_f = cv2.GaussianBlur(mask.astype(np.float32) / 255.0, (blur, blur), 0)
    return np.clip(mask_f, 0.0, 1.0)


def build_hair_edit_mask(image_path: Path, view_key: str = "front") -> np.ndarray | None:
    """
    Where AI hair changes are allowed: hair region minus protected face skin.
    """
    hair = create_hair_mask(image_path)
    if hair is None:
        return None

    img, landmarks = _landmarks_for_image(image_path)
    if img is None or landmarks is None:
        return hair

    h, w = img.shape[:2]

    def point(idx: int) -> np.ndarray:
        return np.array([landmarks[idx].x * w, landmarks[idx].y * h])

    preserve = create_face_preserve_mask(image_path, view_key)
    edit = hair.copy()
    if preserve is not None:
        # Protect eyes/nose/mouth only; do not carve out temple or side hair.
        edit = hair * np.clip(1.0 - np.power(preserve, 1.5) * 0.97, 0.0, 1.0)

    expand_k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13, 13))
    edit_u8 = np.clip(edit * 255.0, 0, 255).astype(np.uint8)
    edit_u8 = cv2.dilate(edit_u8, expand_k, iterations=1)
    edit = cv2.GaussianBlur(edit_u8.astype(np.float32) / 255.0, (7, 7), 0)

    return np.clip(edit, 0.0, 1.0)


def hair_composite_mode() -> str:
    raw = os.environ.get("HAIR_COMPOSITE_MODE", HAIR_COMPOSITE_MODE_DEFAULT).strip().lower()
    if raw in ("full", "face_lock", "off"):
        return raw
    return HAIR_COMPOSITE_MODE_DEFAULT


def _apply_face_lock(
    result: np.ndarray,
    original_bgr: np.ndarray,
    face_preserve: np.ndarray | None,
    strength: float = 0.94,
) -> np.ndarray:
    if result.shape[:2] != original_bgr.shape[:2]:
        result = _align_bgr_to_reference(original_bgr, result)
    if face_preserve is None:
        return result
    if face_preserve.shape[:2] != original_bgr.shape[:2]:
        face_preserve = cv2.resize(
            face_preserve, (original_bgr.shape[1], original_bgr.shape[0])
        )
    lock = np.clip(face_preserve.astype(np.float32), 0.0, 1.0)
    lock_3 = np.stack([lock, lock, lock], axis=-1)
    blended = (
        result.astype(np.float32) * (1.0 - lock_3 * strength)
        + original_bgr.astype(np.float32) * (lock_3 * strength)
    )
    return np.clip(blended, 0, 255).astype(np.uint8)


def _align_bgr_to_reference(reference: np.ndarray, image: np.ndarray) -> np.ndarray:
    """Replicate often returns a different pixel size than the uploaded capture."""
    if image.shape[:2] == reference.shape[:2]:
        return image
    return cv2.resize(
        image,
        (reference.shape[1], reference.shape[0]),
        interpolation=cv2.INTER_LINEAR,
    )


def _mean_abs_diff(a: np.ndarray, b: np.ndarray) -> float:
    if a.shape[:2] != b.shape[:2]:
        b = _align_bgr_to_reference(a, b)
    return float(np.mean(np.abs(a.astype(np.float32) - b.astype(np.float32))))


def _mean_masked_diff(
    a: np.ndarray, b: np.ndarray, mask: np.ndarray | None
) -> float:
    if mask is None or float(np.max(mask)) < 0.05:
        return _mean_abs_diff(a, b)
    if a.shape[:2] != b.shape[:2]:
        b = _align_bgr_to_reference(a, b)
    m = mask.astype(np.float32)
    if m.shape[:2] != a.shape[:2]:
        m = cv2.resize(m, (a.shape[1], a.shape[0]))
    m3 = np.stack([m, m, m], axis=-1)
    denom = max(float(np.sum(m3)), 1.0)
    return float(np.sum(np.abs(a.astype(np.float32) - b.astype(np.float32)) * m3) / denom)


def _expand_hair_mask(mask: np.ndarray, factor: float = 1.2) -> np.ndarray:
    expanded = np.clip(mask.astype(np.float32) * factor, 0.0, 1.0)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))
    u8 = (expanded * 255).astype(np.uint8)
    u8 = cv2.dilate(u8, kernel, iterations=1)
    return cv2.GaussianBlur(u8.astype(np.float32) / 255.0, (9, 9), 0)


def composite_hair_only(
    original_bgr: np.ndarray,
    edited_bgr: np.ndarray,
    mask: np.ndarray,
    preserve_color: bool = True,
    face_preserve: np.ndarray | None = None,
    mode: str | None = None,
    *,
    full_hair_replace: bool = False,
) -> tuple[np.ndarray, dict[str, float | bool]]:
    composite_mode = mode or hair_composite_mode()
    mask_max = float(np.max(mask)) if mask is not None else 0.0

    if composite_mode == "off":
        result = _apply_face_lock(edited_bgr, original_bgr, face_preserve)
        diff = _mean_abs_diff(result, original_bgr)
        return result, {
            "compositeDiff": round(diff, 2),
            "usedRawOutput": True,
            "maskMax": round(mask_max, 3),
        }

    edited_bgr = _align_bgr_to_reference(original_bgr, edited_bgr)

    if mask.shape[:2] != original_bgr.shape[:2]:
        mask = cv2.resize(mask, (original_bgr.shape[1], original_bgr.shape[0]))

    edit_mask = np.clip(mask.astype(np.float32), 0.0, 1.0)
    mask_max = float(np.max(edit_mask))

    edited_work = edited_bgr.copy()
    light_color = composite_mode == "face_lock" and not full_hair_replace
    use_ai_color = full_hair_replace or composite_mode == "off"
    # face_lock: keep AI haircut shape; only pull natural color lightly at the edges.
    if preserve_color and composite_mode == "full" and not use_ai_color:
        orig_lab = cv2.cvtColor(original_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
        edit_lab = cv2.cvtColor(edited_work, cv2.COLOR_BGR2LAB).astype(np.float32)
        hair_pixels = edit_mask > 0.25
        edit_lab[hair_pixels, 1] = (
            0.40 * edit_lab[hair_pixels, 1] + 0.60 * orig_lab[hair_pixels, 1]
        )
        edit_lab[hair_pixels, 2] = (
            0.40 * edit_lab[hair_pixels, 2] + 0.60 * orig_lab[hair_pixels, 2]
        )
        edit_lab[hair_pixels, 0] = (
            0.65 * edit_lab[hair_pixels, 0] + 0.35 * orig_lab[hair_pixels, 0]
        )
        edited_work = cv2.cvtColor(
            np.clip(edit_lab, 0, 255).astype(np.uint8),
            cv2.COLOR_LAB2BGR,
        )
    elif preserve_color and light_color:
        orig_lab = cv2.cvtColor(original_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
        edit_lab = cv2.cvtColor(edited_work, cv2.COLOR_BGR2LAB).astype(np.float32)
        hair_pixels = edit_mask > 0.35
        edge_pixels = (edit_mask > 0.12) & (edit_mask <= 0.35)
        edit_lab[hair_pixels, 1] = (
            0.92 * edit_lab[hair_pixels, 1] + 0.08 * orig_lab[hair_pixels, 1]
        )
        edit_lab[hair_pixels, 2] = (
            0.92 * edit_lab[hair_pixels, 2] + 0.08 * orig_lab[hair_pixels, 2]
        )
        edit_lab[hair_pixels, 0] = (
            0.94 * edit_lab[hair_pixels, 0] + 0.06 * orig_lab[hair_pixels, 0]
        )
        edit_lab[edge_pixels, 1] = (
            0.78 * edit_lab[edge_pixels, 1] + 0.22 * orig_lab[edge_pixels, 1]
        )
        edit_lab[edge_pixels, 2] = (
            0.78 * edit_lab[edge_pixels, 2] + 0.22 * orig_lab[edge_pixels, 2]
        )
        edit_lab[edge_pixels, 0] = (
            0.85 * edit_lab[edge_pixels, 0] + 0.15 * orig_lab[edge_pixels, 0]
        )
        edited_work = cv2.cvtColor(
            np.clip(edit_lab, 0, 255).astype(np.uint8),
            cv2.COLOR_LAB2BGR,
        )

    def _blend_with_mask(active_mask: np.ndarray) -> np.ndarray:
        blend_mask = np.clip(active_mask.astype(np.float32), 0.0, 1.0)
        if full_hair_replace:
            blend_mask = np.power(blend_mask, 0.72)
        elif light_color:
            blend_mask = np.power(blend_mask, 0.85)
            blend_mask = np.clip(blend_mask * 1.15, 0.0, 1.0)
        else:
            blend_mask = np.power(blend_mask, 0.78)

        mask_3 = np.stack([blend_mask, blend_mask, blend_mask], axis=-1)
        blended = (
            edited_work.astype(np.float32) * mask_3
            + original_bgr.astype(np.float32) * (1.0 - mask_3)
        )
        out = np.clip(blended, 0, 255).astype(np.uint8)
        background_keep = (active_mask < 0.08).astype(np.float32)
        bg_3 = np.stack([background_keep, background_keep, background_keep], axis=-1)
        out = np.clip(
            out.astype(np.float32) * (1.0 - bg_3) + original_bgr.astype(np.float32) * bg_3,
            0,
            255,
        ).astype(np.uint8)
        return _apply_face_lock(out, original_bgr, face_preserve)

    result = _blend_with_mask(edit_mask)
    diff = _mean_abs_diff(result, original_bgr)
    used_raw = False

    if diff < COMPOSITE_MIN_VISIBLE_DIFF:
        logger.warning(
            "Composite diff %.2f below threshold; using stronger AI hair blend",
            diff,
        )
        expanded_mask = _expand_hair_mask(edit_mask, factor=1.55)
        strong_mask = np.clip(np.power(expanded_mask, 0.65 if full_hair_replace else 0.75), 0.0, 1.0)
        mask_3 = np.stack([strong_mask, strong_mask, strong_mask], axis=-1)
        result = np.clip(
            edited_bgr.astype(np.float32) * mask_3
            + original_bgr.astype(np.float32) * (1.0 - mask_3),
            0,
            255,
        ).astype(np.uint8)
        lock_strength = 0.90 if full_hair_replace else 0.96
        result = _apply_face_lock(result, original_bgr, face_preserve, strength=lock_strength)
        diff = _mean_abs_diff(result, original_bgr)
        mask_max = float(np.max(strong_mask))

    face_drift = _mean_masked_diff(result, original_bgr, face_preserve)
    reject_face = face_drift > 28.0

    return result, {
        "compositeDiff": round(diff, 2),
        "usedRawOutput": used_raw,
        "maskMax": round(mask_max, 3),
        "faceDrift": round(face_drift, 2),
        "rejectFaceDrift": reject_face,
    }


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

        # A wide jaw AND wide forehead relative to cheekbones = square, but only
        # if the face is not notably long; a long face with a strong jaw reads
        # as oval, not square.
        if jaw_ratio > 0.9 and forehead_ratio > 0.9 and ratio < 1.35:
            shape = "square"
        elif forehead_ratio > 1.1 and jaw_ratio < 0.85:
            # Tapered jaw with a broad forehead. Previously this branch assigned
            # "square" whenever ratio >= 1.35 -- i.e. a LONG, NARROW face was
            # labelled square, which is the opposite shape. Long + tapered is
            # oval; only short + tapered reads round.
            shape = "round" if ratio < 1.35 else "oval"
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

    coverage = float(np.mean(mask > 0.25))
    hair_pixels = mask > 0.25
    rows = np.where(np.any(hair_pixels, axis=1))[0]
    if len(rows) == 0:
        return 0, HAIR_LENGTH_LABELS[0], 0.0

    crown_depth = (float(rows[-1]) - float(rows[0]) + 1.0) / face_height

    band_lo = int(max(0, rows[0]))
    band_hi = int(min(h, eyebrow_y + face_height * 0.12))
    side_band = hair_pixels[band_lo:band_hi, :] if band_hi > band_lo else hair_pixels
    cols_left = np.where(np.any(side_band[:, : int(left_ear_x)], axis=0))[0]
    cols_right = np.where(np.any(side_band[:, int(right_ear_x) :], axis=0))[0]
    side_cover = 0.0
    if len(cols_left):
        side_cover = max(side_cover, (left_ear_x - cols_left[0]) / face_height)
    if len(cols_right):
        side_cover = max(
            side_cover, (cols_right[-1] + int(right_ear_x) - right_ear_x) / face_height
        )

    # Scale-invariant signals. The previous score was dominated by `coverage`
    # (hair pixels / WHOLE FRAME, weighted 4.0), which is a function of how close
    # the phone was held: the same haircut read "short" at arm's length and
    # "long" in a close crop. Both signals below are normalised by face size, so
    # framing no longer changes the answer.
    #
    #   below_chin  how far the lowest hair pixel sits past the chin, in face
    #               heights. Negative = hair ends above the chin (short).
    #   face_area   hair area / face bounding-box area.
    #
    # Measured on real short-hair captures: below_chin -0.60..-0.30,
    # face_area 0.62..1.00.
    face_width = max(abs(right_ear_x - left_ear_x), 1.0)
    hair_area = float(np.count_nonzero(hair_pixels))
    face_area = hair_area / max(face_height * face_width, 1.0)
    below_chin = (float(rows[-1]) - chin_y) / face_height

    if face_area < 0.35 and crown_depth < 0.55:
        level = 0
    elif below_chin < -0.15:
        level = 1
    elif below_chin < 0.15:
        level = 2
    else:
        level = 3

    score = float(below_chin)
    return level, HAIR_LENGTH_LABELS[level], round(score, 3)


def effective_hair_length_level(
    length_level: int, image_paths: list[Path]
) -> tuple[int, str, float, float]:
    """Blend client hint with fresh detection; avoid 'bald' when crown hair is visible."""
    detected_level, detected_label, score = combined_hair_length(image_paths)
    coverage = combined_hair_mask_coverage(image_paths)
    level = max(0, min(3, int(length_level)))
    level = max(level, detected_level)
    if coverage >= 0.018 and level == 0:
        level = 1
    label = HAIR_LENGTH_LABELS.get(level, detected_label)
    return level, label, score, coverage


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


# Laplacian variance on hair-mask pixels (tune with shop lighting).
# Legacy absolute Laplacian-variance cutoffs. Kept only for the fallback path.
# These were never resolution- or exposure-independent: on 480x640 captures the
# measured hair energy was 405-522, so EVERY scan exceeded 175 and every user
# was classified Curly regardless of their actual hair.
TEXTURE_STRAIGHT_MAX = 85.0
TEXTURE_WAVY_MAX = 175.0

# Preferred metric: hair edge energy divided by the energy of a skin patch from
# the same photo. Dividing by an in-frame control cancels camera sharpness,
# resolution, exposure and noise, which the absolute numbers above could not.
# Measured on real straight-haired captures: 2.37, 2.84, 3.59.
# The wavy/curly boundaries are informed estimates, not measured -- there is one
# subject in the calibration set. Both are env-tunable so they can be corrected
# from real customer scans without a code change; the computed ratio is logged
# on every scan to make that calibration possible.
TEXTURE_RATIO_STRAIGHT_MAX = float(
    os.environ.get("TEXTURE_RATIO_STRAIGHT_MAX", "4.5")
)
TEXTURE_RATIO_WAVY_MAX = float(os.environ.get("TEXTURE_RATIO_WAVY_MAX", "7.0"))

# |yaw| above this counts as a real profile turn rather than a slight tilt.
FACE_YAW_PROFILE_MIN = float(os.environ.get("FACE_YAW_PROFILE_MIN", "0.12"))

# Value (HSV) below which hair reads as black. Measured medians for black hair
# on segmented masks were 40-46, so the previous cutoff of 45 sat exactly inside
# the real range and labelled black hair "dark brown".
HAIR_COLOR_BLACK_MAX_V = float(os.environ.get("HAIR_COLOR_BLACK_MAX_V", "68"))

# Hair coverage (fraction of frame) below which we stop claiming a texture.
# Separates two cases we previously could not tell apart:
#   * genuinely little/no hair  -> bald or very closely shaved
#   * hair present but hidden   -> cap, hood, headscarf, hand, hair tied back
# Below BALD, there is nothing to measure. Between BALD and OBSTRUCTED the face
# was found but far too little hair is visible for the numbers to mean anything.
HAIR_COVERAGE_BALD_MAX = float(os.environ.get("HAIR_COVERAGE_BALD_MAX", "0.010"))
HAIR_COVERAGE_OBSTRUCTED_MAX = float(
    os.environ.get("HAIR_COVERAGE_OBSTRUCTED_MAX", "0.030")
)
TEXTURE_CURLY_MAX = 280.0
# Fraction of image pixels with hair mask above threshold (very low = bald/buzzed).
BALD_MASK_COVERAGE_MAX = 0.012

# full | face_lock | off — how aggressively to blend AI hair onto the capture.
HAIR_COMPOSITE_MODE_DEFAULT = "full"
COMPOSITE_MIN_VISIBLE_DIFF = 5.0
REPLICATE_FULL_HAIR_DIFF = 6.0


def _hair_region_stats(image_path: Path) -> tuple[float | None, float | None]:
    """Return (laplacian_variance, mask_coverage) for visible hair region."""
    img = cv2.imread(str(image_path))
    mask = create_hair_mask(image_path)
    if img is None or mask is None:
        return None, None

    mask_f = np.clip(mask.astype(np.float32), 0.0, 1.0)
    coverage = float(np.mean(mask_f > 0.25))
    hair = mask_f > 0.25
    if not np.any(hair):
        return None, coverage

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    lap = cv2.Laplacian(gray, cv2.CV_64F)
    return float(np.var(lap[hair])), coverage


def _hair_region_texture_energy(image_path: Path) -> float | None:
    energy, _ = _hair_region_stats(image_path)
    return energy


def _skin_control_energy(image_path: Path, lap: np.ndarray, hair: np.ndarray) -> float | None:
    """Laplacian variance of a bare skin patch, used to normalise hair energy.

    Skin is smooth, so its edge energy reflects the camera and lighting rather
    than any structure. Dividing hair energy by it removes the resolution and
    sharpness dependence that made the absolute thresholds meaningless.
    """
    img, landmarks = _landmarks_for_image(image_path)
    if img is None or landmarks is None:
        return None
    h, w = img.shape[:2]

    def point(idx: int) -> np.ndarray:
        return np.array([landmarks[idx].x * w, landmarks[idx].y * h], dtype=np.float32)

    try:
        # Cheek patch: between the eyes and the jaw, inside the face oval.
        left_cheek = point(234)
        right_cheek = point(454)
        eye_y = float(point(168)[1])
        chin_y = float(point(152)[1])
    except Exception:
        return None

    top = int(np.clip(eye_y + (chin_y - eye_y) * 0.25, 0, h - 1))
    bottom = int(np.clip(eye_y + (chin_y - eye_y) * 0.70, top + 1, h))
    span = right_cheek[0] - left_cheek[0]
    left = int(np.clip(left_cheek[0] + span * 0.22, 0, w - 1))
    right = int(np.clip(right_cheek[0] - span * 0.22, left + 1, w))
    if bottom <= top or right <= left:
        return None

    skin = np.zeros((h, w), dtype=bool)
    skin[top:bottom, left:right] = True
    skin &= ~hair
    if int(np.count_nonzero(skin)) < 200:
        return None
    return float(np.var(lap[skin]))


def hair_texture_ratio(image_path: Path) -> float | None:
    """Hair edge energy relative to a skin control patch from the same photo."""
    img = cv2.imread(str(image_path))
    mask = create_hair_mask(image_path)
    if img is None or mask is None:
        return None
    hair = np.clip(mask.astype(np.float32), 0.0, 1.0) > 0.5
    if not np.any(hair):
        return None

    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    lap = cv2.Laplacian(gray, cv2.CV_64F)
    hair_energy = float(np.var(lap[hair]))

    control = _skin_control_energy(image_path, lap, hair)
    if control is None or control <= 1.0:
        # No usable skin patch: fall back to whole-frame energy, which still
        # cancels most of the resolution/sharpness effect.
        control = float(np.var(lap))
        if control <= 1.0:
            return None
    return hair_energy / control


def combined_hair_mask_coverage(image_paths: list[Path]) -> float:
    coverages: list[float] = []
    for path in image_paths:
        _, coverage = _hair_region_stats(path)
        if coverage is not None:
            coverages.append(coverage)
    if not coverages:
        return 0.0
    return float(np.median(coverages))


def _rgb_to_hair_color_label(r: float, g: float, b: float) -> str:
    """Map mean hair RGB (0-255) to a simple visible color label via HSV."""
    bgr = np.uint8([[[int(round(b)), int(round(g)), int(round(r))]]])
    h, s, v = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)[0, 0]

    if v < HAIR_COLOR_BLACK_MAX_V:
        return "black"
    if s < 35 and v < 130:
        return "gray"
    if s < 40:
        if v >= 175:
            return "blonde"
        if v >= 120:
            return "brown"
        return "dark brown"
    if (h <= 12 or h >= 168) and s >= 40:
        if v >= 150:
            return "red"
        return "dark brown"
    if v >= 165 and 18 <= h <= 38:
        return "blonde"
    if v >= 120:
        return "brown"
    return "dark brown"


def detect_hair_color(image_paths: list[Path]) -> dict[str, object]:
    """Sample median RGB inside the hair mask (front capture preferred)."""
    ordered = list(image_paths)
    if len(ordered) > 1:
        front = [p for p in ordered if "front" in p.name.lower()]
        if front:
            ordered = front + [p for p in ordered if p not in front]

    samples: list[tuple[float, float, float]] = []
    for path in ordered:
        img = cv2.imread(str(path))
        mask = create_hair_mask(path)
        if img is None or mask is None:
            continue
        hair = mask > 0.25
        if not np.any(hair):
            continue
        # Median, not mean. Hair carries specular highlights that are far
        # brighter than the hair itself; averaging them in lifted black hair to
        # "dark brown". On real captures the mean read V=59-65 while the median
        # read V=40-46, which is the difference between "dark brown" and "black".
        bgr = img[hair]
        med_b, med_g, med_r = np.median(bgr, axis=0)
        samples.append((float(med_r), float(med_g), float(med_b)))

    if not samples:
        return {"label": "", "rgb": None}

    r = float(np.median([s[0] for s in samples]))
    g = float(np.median([s[1] for s in samples]))
    b = float(np.median([s[2] for s in samples]))
    label = _rgb_to_hair_color_label(r, g, b)
    return {
        "label": label,
        "rgb": [int(round(r)), int(round(g)), int(round(b))],
    }


def detect_hair_texture(image_paths: list[Path]) -> tuple[str, float]:
    """
    Classify visible hair texture from capture photos.
    Returns Straight, Wavy, or Curly.
    """
    ratios: list[float] = []
    for path in image_paths:
        ratio = hair_texture_ratio(path)
        if ratio is not None:
            ratios.append(ratio)

    if ratios:
        ratio = float(np.median(ratios))
        # Logged so the thresholds can be calibrated from real scans: collect
        # these alongside the customer's actual hair type, then set
        # TEXTURE_RATIO_STRAIGHT_MAX / TEXTURE_RATIO_WAVY_MAX accordingly.
        logger.info(
            "hair texture ratio=%.2f (straight<%.2f wavy<%.2f) samples=%s",
            ratio,
            TEXTURE_RATIO_STRAIGHT_MAX,
            TEXTURE_RATIO_WAVY_MAX,
            [round(r, 2) for r in ratios],
        )
        if ratio < TEXTURE_RATIO_STRAIGHT_MAX:
            return "Straight", round(ratio, 2)
        if ratio < TEXTURE_RATIO_WAVY_MAX:
            return "Wavy", round(ratio, 2)
        return "Curly", round(ratio, 2)

    # Fallback: absolute energy. Resolution-dependent and known to over-report
    # Curly, so only used when no ratio could be computed at all.
    energies: list[float] = []
    for path in image_paths:
        energy = _hair_region_texture_energy(path)
        if energy is not None:
            energies.append(energy)
    if not energies:
        return "Straight", 0.0

    energy = float(np.median(energies))
    if energy < TEXTURE_STRAIGHT_MAX:
        return "Straight", round(energy, 2)
    if energy < TEXTURE_WAVY_MAX:
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


async def _replicate_edit_image(
    client: httpx.AsyncClient,
    data_uri: str,
    view_prompt: str,
    view_key: str,
    *,
    prompt_upsampling: bool = False,
) -> tuple[np.ndarray | None, str | None]:
    response = await client.post(
        f"https://api.replicate.com/v1/models/{REPLICATE_MODEL}/predictions",
        headers={
            "Authorization": f"Bearer {REPLICATE_API_TOKEN}",
            "Content-Type": "application/json",
        },
        json={
            "input": replicate_prediction_input(
                view_prompt, data_uri, prompt_upsampling=prompt_upsampling
            )
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
    if edited_bgr is None:
        return None, f"{view_key} view: Replicate returned an unreadable image"
    return edited_bgr, None


def _composite_edited_view(
    original_bgr: np.ndarray,
    edited_bgr: np.ndarray,
    image_path: Path,
    view_key: str,
) -> tuple[np.ndarray, dict[str, float | bool]]:
    edited_bgr = _align_bgr_to_reference(original_bgr, edited_bgr)
    mode = hair_composite_mode()
    face_preserve = create_face_preserve_mask(image_path, view_key)
    diagnostics: dict[str, float | bool] = {
        "compositeDiff": 0.0,
        "usedRawOutput": False,
        "maskMax": 0.0,
        "faceDrift": 0.0,
        "rejectFaceDrift": False,
    }

    if mode == "off":
        final_bgr = _apply_face_lock(edited_bgr, original_bgr, face_preserve)
        diagnostics["compositeDiff"] = round(_mean_abs_diff(final_bgr, original_bgr), 2)
        diagnostics["faceDrift"] = round(
            _mean_masked_diff(final_bgr, original_bgr, face_preserve), 2
        )
        return final_bgr, diagnostics

    hair_edit_mask = build_hair_edit_mask(image_path, view_key)
    if hair_edit_mask is None or float(np.max(hair_edit_mask)) < 0.08:
        logger.warning("%s view: weak hair mask, retrying base mask", view_key)
        hair_edit_mask = create_hair_mask(image_path)
    if hair_edit_mask is None or float(np.max(hair_edit_mask)) < 0.08:
        logger.warning("%s view: using crown fallback hair mask", view_key)
        hair_edit_mask = _fallback_crown_hair_mask(image_path)

    if hair_edit_mask is not None:
        replicate_diff = _mean_masked_diff(edited_bgr, original_bgr, hair_edit_mask)
        full_replace = replicate_diff >= REPLICATE_FULL_HAIR_DIFF
        final_bgr, diagnostics = composite_hair_only(
            original_bgr,
            edited_bgr,
            hair_edit_mask,
            preserve_color=not full_replace,
            face_preserve=face_preserve,
            mode=mode,
            full_hair_replace=full_replace,
        )
        diagnostics["replicateHairDiff"] = round(replicate_diff, 2)
        diagnostics["fullHairReplace"] = full_replace
    else:
        logger.warning("%s view: no hair mask; keeping original capture", view_key)
        final_bgr = original_bgr.copy()
        diagnostics["replicateHairDiff"] = 0.0

    return final_bgr, diagnostics


async def generate_view_hairstyle(
    client: httpx.AsyncClient,
    image_path: Path,
    base_prompt: str,
    view_key: str,
    extra: str = "",
    *,
    style_key: str = "",
    style_desc: str = "",
) -> tuple[str | None, str | None, dict[str, float | bool]]:
    try:
        image_bytes = prepare_image_bytes(image_path)
        image_b64 = base64.b64encode(image_bytes).decode()
        data_uri = f"data:image/jpeg;base64,{image_b64}"

        pose_lock = profile_pose_lock_sentence(image_path)
        view_prompt = f"{base_prompt} {pose_lock} {VIEW_ANGLE_HINTS[view_key]}{extra}"
        logger.info("Starting Replicate for %s view", view_key)

        edited_bgr, replicate_err = await _replicate_edit_image(
            client, data_uri, view_prompt, view_key
        )
        if replicate_err or edited_bgr is None:
            return None, replicate_err or f"{view_key} view: Replicate failed", {}

        original_bgr = cv2.imread(str(image_path))
        if original_bgr is None:
            _, encoded = cv2.imencode(".jpg", edited_bgr, [cv2.IMWRITE_JPEG_QUALITY, 95])
            return (
                base64.b64encode(encoded.tobytes()).decode(),
                None,
                {"compositeDiff": -1.0, "usedRawOutput": True, "maskMax": 0.0},
            )

        final_bgr, diagnostics = _composite_edited_view(
            original_bgr, edited_bgr, image_path, view_key
        )

        weak_change = float(diagnostics.get("compositeDiff", 0)) < 4.0
        weak_replicate = float(diagnostics.get("replicateHairDiff", 0)) < 5.0
        if weak_change or weak_replicate:
            logger.info(
                "%s view: weak haircut change (composite=%.2f replicate=%.2f), retrying",
                view_key,
                diagnostics.get("compositeDiff", 0),
                diagnostics.get("replicateHairDiff", 0),
            )
            retry_prompt = view_prompt + HAIR_REPLACE_STRENGTH_SUFFIX
            edited_retry, retry_err = await _replicate_edit_image(
                client, data_uri, retry_prompt, view_key, prompt_upsampling=True
            )
            if edited_retry is not None and not retry_err:
                retry_bgr, retry_diag = _composite_edited_view(
                    original_bgr, edited_retry, image_path, view_key
                )
                if float(retry_diag.get("compositeDiff", 0)) > float(
                    diagnostics.get("compositeDiff", 0)
                ) or float(retry_diag.get("replicateHairDiff", 0)) > float(
                    diagnostics.get("replicateHairDiff", 0)
                ):
                    final_bgr, diagnostics = retry_bgr, retry_diag
                    diagnostics["retriedStrong"] = True

            if float(diagnostics.get("replicateHairDiff", 0)) < 5.0 and style_desc:
                focused = (
                    build_focused_hair_retry_prompt(style_desc, style_key)
                    + f" {profile_pose_lock_sentence(image_path)} "
                    f"{VIEW_ANGLE_HINTS[view_key]}{extra}"
                )
                edited_focus, focus_err = await _replicate_edit_image(
                    client, data_uri, focused, view_key, prompt_upsampling=True
                )
                if edited_focus is not None and not focus_err:
                    focus_bgr, focus_diag = _composite_edited_view(
                        original_bgr, edited_focus, image_path, view_key
                    )
                    if float(focus_diag.get("replicateHairDiff", 0)) > float(
                        diagnostics.get("replicateHairDiff", 0)
                    ):
                        final_bgr, diagnostics = focus_bgr, focus_diag
                        diagnostics["retriedFocused"] = True

            if diagnostics.get("rejectFaceDrift"):
                return (
                    None,
                    f"{view_key} view: face region changed too much — retry with a clearer photo",
                    diagnostics,
                )

        _, encoded = cv2.imencode(".jpg", final_bgr, [cv2.IMWRITE_JPEG_QUALITY, 95])
        logger.info(
            "Finished %s view (composite=%.2f replicate=%.2f mask=%.3f)",
            view_key,
            diagnostics.get("compositeDiff", 0),
            diagnostics.get("replicateHairDiff", 0),
            diagnostics.get("maskMax", 0),
        )
        return base64.b64encode(encoded.tobytes()).decode(), None, diagnostics

    except Exception as exc:
        logger.exception("generate_view_hairstyle failed for %s", view_key)
        return None, f"{view_key} view: {exc}", {}


@app.get("/")
def root():
    return {"status": "Tatis AI try-on sidecar running", "model": REPLICATE_MODEL}


@app.get("/health")
def health():
    return {
        "ok": True,
        "replicate_configured": bool(REPLICATE_API_TOKEN),
        "model": REPLICATE_MODEL,
        "face_landmarker": (
            "unavailable" if _face_landmarker_unusable else ("ready" if _face_landmarker is not None else "lazy")
        ),
        "hair_segmenter": (
            "unavailable"
            if _hair_segmenter_failures >= HAIR_SEGMENTER_MAX_FAILURES
            else ("ready" if _hair_segmenter is not None else "lazy")
        ),
    }


def get_face_detector():
    """Lazy BlazeFace detector, or None when unavailable."""
    global _face_detector, _face_detector_failures
    if _face_detector is not None:
        return _face_detector
    if _face_detector_failures >= FACE_DETECTOR_MAX_FAILURES:
        return None
    try:
        MODEL_DIR.mkdir(exist_ok=True)
        if not (FACE_DETECTOR_MODEL_PATH.exists() and FACE_DETECTOR_MODEL_PATH.stat().st_size > 1000):
            with httpx.Client(timeout=120, follow_redirects=True, verify=httpx_ssl_verify()) as client:
                resp = client.get(FACE_DETECTOR_MODEL_URL)
                resp.raise_for_status()
                FACE_DETECTOR_MODEL_PATH.write_bytes(resp.content)
        base_kwargs = {"model_asset_path": str(FACE_DETECTOR_MODEL_PATH)}
        delegate_enum = getattr(mp_tasks.BaseOptions, "Delegate", None)
        if delegate_enum is not None and hasattr(delegate_enum, "CPU"):
            base_kwargs["delegate"] = delegate_enum.CPU
        options = vision.FaceDetectorOptions(
            base_options=mp_tasks.BaseOptions(**base_kwargs),
            running_mode=vision.RunningMode.IMAGE,
            min_detection_confidence=0.3,
        )
        _face_detector = vision.FaceDetector.create_from_options(options)
        return _face_detector
    except Exception:
        _face_detector_failures += 1
        logger.exception("Face detector init failed (%s/%s).", _face_detector_failures, FACE_DETECTOR_MAX_FAILURES)
        return None


def _detector_yaw(image_path: Path) -> float | None:
    """Yaw in [-1,1] from BlazeFace's nose keypoint within the face box."""
    detector = get_face_detector()
    if detector is None:
        return None
    try:
        img = cv2.imread(str(image_path))
        if img is None:
            return None
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        if not rgb.flags["C_CONTIGUOUS"]:
            rgb = np.ascontiguousarray(rgb)
        result = detector.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
        if not result.detections:
            return None
        detection = result.detections[0]
        box = detection.bounding_box
        keypoints = getattr(detection, "keypoints", None)
        if not keypoints or len(keypoints) < 3:
            return None

        width = img.shape[1]
        left = box.origin_x / width
        right = (box.origin_x + box.width) / width
        if right - left < 1e-6:
            return None
        # Keypoint 2 is the nose tip; where it sits across the face box tracks
        # head yaw the same way the landmark nose/ear ratio does.
        position = (keypoints[2].x - left) / (right - left)
        return float(np.clip((position - 0.5) * 2.0, -1.0, 1.0))
    except Exception:
        logger.exception("Face detector yaw failed.")
        return None


def face_yaw_direction(image_path: Path) -> dict[str, object]:
    """Which way the head is turned, from landmark geometry.

    Used to verify that a generated try-on kept its input's head turn. Compares
    how far the nose sits from each ear: on a left-turned head the nose is much
    closer to one ear than the other. Sign is in image space, so it is stable
    regardless of how the capture was labelled.
    """
    yaw: float | None = None
    source = "landmarks"

    img, landmarks = _landmarks_for_image(image_path)
    if img is not None and landmarks is not None:
        h, w = img.shape[:2]

        def point(idx: int) -> np.ndarray:
            return np.array([landmarks[idx].x * w, landmarks[idx].y * h], dtype=np.float32)

        left_ear_x = float(point(234)[0])
        right_ear_x = float(point(454)[0])
        span = right_ear_x - left_ear_x
        if abs(span) >= 1e-3:
            # 0 = nose at the left ear, 1 = at the right ear, 0.5 = front on.
            position = (float(point(1)[0]) - left_ear_x) / span
            yaw = float(np.clip((position - 0.5) * 2.0, -1.0, 1.0))

    if yaw is None:
        # The landmarker gives up on hard profiles, which is precisely the case
        # this check exists for: a generated view turned too far returned
        # "unknown" and the orientation correction was skipped instead of
        # applied. BlazeFace still resolves those.
        yaw = _detector_yaw(image_path)
        source = "detector"

    if yaw is None:
        return {"ok": False, "direction": "unknown", "yaw": 0.0, "source": "none"}

    # Threshold chosen so a mild head tilt still reads as "front"; only a real
    # profile turn is called left/right.
    if yaw <= -FACE_YAW_PROFILE_MIN:
        direction = "left"
    elif yaw >= FACE_YAW_PROFILE_MIN:
        direction = "right"
    else:
        direction = "front"

    return {"ok": True, "direction": direction, "yaw": round(yaw, 4), "source": source}


@app.post("/face-orientation")
async def face_orientation(image: UploadFile = File(...)):
    """Report head-turn direction for one image. Used by the try-on view check."""
    path = UPLOAD_DIR / "orientation_probe.jpg"
    await save_upload(image, path)
    try:
        return face_yaw_direction(path)
    finally:
        try:
            path.unlink()
        except OSError:
            pass


@app.post("/enforce-view-orientation")
async def enforce_view_orientation(
    image: UploadFile = File(...),
    expected: str = Form(...),
):
    """Return the image, mirrored if its head turn does not match `expected`.

    The try-on generator does not reliably preserve the input head turn, so a
    LEFT profile can come back turned like the RIGHT one. Mirroring is exact and
    free, where regenerating costs another paid call and can fail identically.
    Done here rather than in PHP because this service already has OpenCV; the
    PHP image has no GD extension.
    """
    path = UPLOAD_DIR / "orientation_fix.jpg"
    await save_upload(image, path)
    try:
        probe = face_yaw_direction(path)
        actual = str(probe.get("direction", "unknown"))
        wanted = (expected or "").strip().lower()

        if not probe.get("ok") or actual == "unknown" or wanted not in ("left", "right"):
            return {"ok": False, "corrected": False, "direction": actual, "image": None}

        if actual == wanted:
            return {"ok": True, "corrected": False, "direction": actual, "image": None}

        img = cv2.imread(str(path))
        if img is None:
            return {"ok": False, "corrected": False, "direction": actual, "image": None}
        flipped = cv2.flip(img, 1)
        ok, buf = cv2.imencode(".jpg", flipped, [int(cv2.IMWRITE_JPEG_QUALITY), 92])
        if not ok:
            return {"ok": False, "corrected": False, "direction": actual, "image": None}

        return {
            "ok": True,
            "corrected": True,
            "direction": actual,
            "expected": wanted,
            "image": base64.b64encode(buf.tobytes()).decode("ascii"),
        }
    finally:
        try:
            path.unlink()
        except OSError:
            pass


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
        mask_coverage = combined_hair_mask_coverage(paths)
        if mask_coverage >= 0.018 and length_level == 0:
            length_level = 1
            length_label = HAIR_LENGTH_LABELS[1]
        no_hair_detected = (
            length_level == 0 and mask_coverage < BALD_MASK_COVERAGE_MAX
        )
        hair_texture, hair_texture_score = detect_hair_texture(paths)
        hair_color = detect_hair_color(paths)

        # Do not report a texture we cannot actually see. With a real hair mask
        # the coverage number is trustworthy, so use it to say "no hair" or
        # "hair is covered" instead of inventing Straight/Wavy/Curly from a
        # handful of pixels.
        segmented = hair_mask_is_segmented(front_path)
        hair_visibility = "ok"
        if segmented:
            if mask_coverage < HAIR_COVERAGE_BALD_MAX:
                hair_visibility = "none"
            elif mask_coverage < HAIR_COVERAGE_OBSTRUCTED_MAX:
                hair_visibility = "obstructed"

        if hair_visibility != "ok":
            logger.info(
                "hair visibility=%s coverage=%.4f; suppressing texture claim",
                hair_visibility,
                mask_coverage,
            )
            hair_texture = ""
            hair_texture_score = 0.0
            hair_color = {"label": "", "rgb": None}
        achievable = styles_for_length(length_level)
        top_styles = recommend_styles(shape, length_level)

        return {
            "face_shape": shape,
            "hair_texture": hair_texture,
            "hair_texture_score": hair_texture_score,
            "hair_length": length_label,
            "hair_length_level": length_level,
            "hair_length_score": length_score,
            "hair_mask_coverage": round(mask_coverage, 4),
            # "model" = per-pixel segmentation; "geometric" = landmark-hull
            # fallback, whose colour/texture numbers are much less reliable.
            "hair_mask_source": "model" if segmented else "geometric",
            # "ok" | "none" (bald/shaved) | "obstructed" (cap, hood, tied back).
            # Anything other than "ok" means hair_texture/hair_color are empty
            # on purpose and the app should ask rather than guess.
            "hair_visibility": hair_visibility,
            "no_hair_detected": no_hair_detected,
            "hair_color": hair_color.get("label", ""),
            "hair_color_rgb": hair_color.get("rgb"),
            "achievable_styles": achievable,
            "top_styles": [{"key": s, "name": STYLE_NAMES.get(s, s)} for s in top_styles],
            "profiles_received": ["front", "left", "right"],
            "landmarker": "unavailable" if _face_landmarker_unusable else "ok",
            # True when the landmarker never loaded, so face-shape came from a
            # degraded path rather than real landmarks. Callers should not treat
            # a degraded result as a confirmed scan.
            "degraded": bool(_face_landmarker_unusable),
        }
    except Exception as e:
        message = str(e)
        if "GLESv2" in message or "libGL" in message:
            logger.exception("analyze-face GLES failure; returning safe defaults")
            return {
                # These are placeholders, not measurements. "degraded" must stay
                # in the payload: callers use it to avoid presenting fabricated
                # values as a real scan result (see face_scan.php analyzeCaptures).
                "degraded": True,
                "degraded_reason": "face_landmarker_unavailable",
                "face_shape": "oval",
                "hair_texture": "Wavy",
                "hair_texture_score": 0.0,
                "hair_length": "short",
                "hair_length_level": 1,
                "hair_length_score": 0.0,
                "hair_mask_coverage": 0.0,
                "no_hair_detected": False,
                "hair_color": "",
                "hair_color_rgb": None,
                "achievable_styles": [],
                "top_styles": [],
                "profiles_received": ["front", "left", "right"],
                "landmarker": "unavailable",
            }
        return JSONResponse(status_code=500, content={"error": message})


@app.post("/generate")
async def generate_hairstyle(
    face_image: UploadFile = File(...),
    left_image: UploadFile = File(...),
    right_image: UploadFile = File(...),
    style: str = Form(""),
    style_name: str = Form(""),
    style_code: str = Form(""),
    hair_length_level: int = Form(1),
    hair_color: str = Form(""),
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

        resolved_name = (style_name or style).strip()
        resolved_code = (style_code or style).strip()
        style_key = resolve_style_key(resolved_name, resolved_code)
        style_desc = STYLE_PROMPTS.get(style_key, f"{resolved_name or resolved_code} hairstyle")
        length_level, _, _, mask_cov = effective_hair_length_level(
            int(hair_length_level), list(views.values())
        )
        achievable = set(styles_for_length(length_level))
        feasible_today = style_key in achievable
        length_note = None
        if not feasible_today:
            required = STYLE_MIN_LENGTH.get(style_key, 1)
            length_note = (
                f"This style usually needs {HAIR_LENGTH_LABELS.get(required, 'more')} hair. "
                "Preview shows the target look — ask your barber what is achievable today."
            )

        profile_note = (
            " Use the same haircut design on all three photos, but each output must keep "
            "that photo's original head turn and camera angle — do not make every frame face the camera."
        )

        color_label = hair_color.strip()
        if not color_label:
            color_info = detect_hair_color(list(views.values()))
            color_label = str(color_info.get("label", ""))

        if feasible_today:
            base_prompt = (
                build_hair_only_prompt(style_desc, length_level, color_label, style_key)
                + profile_note
            )
        else:
            base_prompt = build_aspirational_hair_prompt(style_desc, style_key) + profile_note

        replicate_timeout = httpx.Timeout(600.0, connect=60.0)
        result_images: dict[str, str] = {}
        preview_diagnostics: dict[str, dict[str, float | bool]] = {}

        async with httpx.AsyncClient(
            timeout=replicate_timeout, verify=httpx_ssl_verify()
        ) as client:
            for view_key, path in views.items():
                view_b64, err, diag = await generate_view_hairstyle(
                    client,
                    path,
                    base_prompt,
                    view_key,
                    style_key=style_key,
                    style_desc=style_desc,
                )
                if err or view_b64 is None:
                    return JSONResponse(
                        status_code=500,
                        content={"error": err or f"Failed to generate {view_key} view"},
                    )
                result_images[view_key] = view_b64
                preview_diagnostics[view_key] = diag

            left_h = hashlib.sha256(result_images["left"].encode()).digest()
            right_h = hashlib.sha256(result_images["right"].encode()).digest()
            if left_h == right_h:
                logger.warning("Left/right identical — retrying right view")
                retry_extra = (
                    " CRITICAL: The right-profile output must NOT match the left-profile output. "
                    "This input is RIGHT profile only: nose must stay toward the LEFT side of the frame."
                )
                view_b64, err, diag = await generate_view_hairstyle(
                    client,
                    views["right"],
                    base_prompt,
                    "right",
                    extra=retry_extra,
                    style_key=style_key,
                    style_desc=style_desc,
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
                preview_diagnostics["right"] = diag

        return {
            "result_images": result_images,
            "result_image": result_images["front"],
            "style": style_key,
            "feasible_today": feasible_today,
            "length_note": length_note,
            "preview_diagnostics": preview_diagnostics,
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
