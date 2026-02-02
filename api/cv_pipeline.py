#!/usr/bin/env python3
import json
import sys
from typing import Dict

import cv2
import numpy as np
import mediapipe as mp


def _distance(a, b) -> float:
    return float(np.linalg.norm(np.array(a) - np.array(b)))


def _classify_face_shape(points: Dict[int, tuple]) -> str:
    # landmarks (MediaPipe Face Mesh):
    # 10: forehead/glabella, 152: chin, 234/454: jaw, 93/323: cheekbones, 127/356: forehead width
    try:
        forehead = points[10]
        chin = points[152]
        jaw_left = points[234]
        jaw_right = points[454]
        cheek_left = points[93]
        cheek_right = points[323]
        forehead_left = points[127]
        forehead_right = points[356]
    except KeyError:
        return ""

    face_len = _distance(forehead, chin)
    jaw_w = _distance(jaw_left, jaw_right)
    cheek_w = _distance(cheek_left, cheek_right)
    forehead_w = _distance(forehead_left, forehead_right)

    if jaw_w == 0 or cheek_w == 0:
        return ""

    ratio_len = face_len / jaw_w
    ratio_jaw_cheek = jaw_w / cheek_w
    ratio_forehead_jaw = forehead_w / jaw_w

    if ratio_len > 1.6:
        return "Oblong"
    if ratio_forehead_jaw > 1.1 and ratio_len > 1.3:
        return "Heart"
    if ratio_jaw_cheek > 1.05 and ratio_len > 1.2:
        return "Square"
    if ratio_len < 1.25:
        return "Round"
    if ratio_forehead_jaw < 0.9 and ratio_len > 1.3:
        return "Diamond"
    return "Oval"


def _classify_hair_color(bgr_mean) -> str:
    b, g, r = bgr_mean
    hsv = cv2.cvtColor(np.uint8([[bgr_mean]]), cv2.COLOR_BGR2HSV)[0][0]
    h, s, v = hsv

    if v < 60:
        return "Black"
    if v < 90 and s < 60:
        return "Dark Brown"
    if 10 < h < 25 and s > 80:
        return "Red"
    if v > 160 and s < 50:
        return "Blonde"
    if v > 140 and s < 30:
        return "Gray"
    return "Brown"


def _classify_hair_texture(region) -> str:
    if region is None or region.size == 0:
        return ""
    gray = cv2.cvtColor(region, cv2.COLOR_BGR2GRAY)
    var = cv2.Laplacian(gray, cv2.CV_64F).var()
    if var > 220:
        return "Curly"
    if var > 120:
        return "Wavy"
    return "Straight"


def _classify_hair_length(region) -> str:
    if region is None or region.size == 0:
        return ""
    gray = cv2.cvtColor(region, cv2.COLOR_BGR2GRAY)
    edges = cv2.Canny(gray, 50, 150)
    density = edges.mean() / 255.0
    if density > 0.18:
        return "Long"
    if density > 0.10:
        return "Medium"
    return "Short"


def main() -> int:
    if len(sys.argv) < 2:
        print(json.dumps({"error": "image path required"}))
        return 1

    image_path = sys.argv[1]
    image = cv2.imread(image_path)
    if image is None:
        print(json.dumps({"error": "failed to read image"}))
        return 1

    h, w = image.shape[:2]
    image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

    mp_face_detection = mp.solutions.face_detection
    mp_face_mesh = mp.solutions.face_mesh

    face_box = None
    with mp_face_detection.FaceDetection(model_selection=1, min_detection_confidence=0.5) as detector:
        results = detector.process(image_rgb)
        if results.detections:
            det = max(results.detections, key=lambda d: d.location_data.relative_bounding_box.width)
            box = det.location_data.relative_bounding_box
            x1 = max(int(box.xmin * w), 0)
            y1 = max(int(box.ymin * h), 0)
            x2 = min(int((box.xmin + box.width) * w), w - 1)
            y2 = min(int((box.ymin + box.height) * h), h - 1)
            face_box = (x1, y1, x2, y2)

    face_shape = ""
    with mp_face_mesh.FaceMesh(static_image_mode=True, refine_landmarks=True, max_num_faces=1) as mesh:
        results = mesh.process(image_rgb)
        if results.multi_face_landmarks:
            landmarks = results.multi_face_landmarks[0]
            points = {}
            for idx, lm in enumerate(landmarks.landmark):
                points[idx] = (lm.x * w, lm.y * h)
            face_shape = _classify_face_shape(points)

    hair_color = ""
    hair_texture = ""
    hair_length = ""

    if face_box:
        x1, y1, x2, y2 = face_box
        face_h = max(y2 - y1, 1)
        pad = int(face_h * 0.2)

        hair_top = max(y1 - int(face_h * 0.6), 0)
        hair_bottom = max(y1 + int(face_h * 0.15), 0)
        hair_left = max(x1 - pad, 0)
        hair_right = min(x2 + pad, w - 1)

        hair_region = image[hair_top:hair_bottom, hair_left:hair_right]
        if hair_region.size > 0:
            mean = hair_region.mean(axis=(0, 1))
            hair_color = _classify_hair_color(mean)
            hair_texture = _classify_hair_texture(hair_region)

        length_top = max(y2, 0)
        length_bottom = min(y2 + int(face_h * 0.8), h - 1)
        length_region = image[length_top:length_bottom, hair_left:hair_right]
        hair_length = _classify_hair_length(length_region)

    result = {
        "hair_length": hair_length,
        "hair_texture": hair_texture,
        "color": hair_color,
        "face_shape": face_shape,
    }
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
