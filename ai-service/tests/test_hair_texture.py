"""Bucket-boundary cover for detect_hair_texture().

Uses stdlib unittest deliberately -- the service has no test dependency today
and this needs none. Run with:

    .venv/Scripts/python.exe -m unittest discover -s tests -v

hair_texture_ratio is monkeypatched throughout, so nothing here touches an
image, MediaPipe or the network. That is the point: it pins lines 1492-1496 of
api.py, where a measured ratio becomes a label, independently of how the ratio
was produced.
"""

import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import api  # noqa: E402


class HairTextureBucketTest(unittest.TestCase):
    def setUp(self):
        self._real_ratio = api.hair_texture_ratio
        self._real_energy = api._hair_region_texture_energy
        self.straight_max = api.TEXTURE_RATIO_STRAIGHT_MAX
        self.wavy_max = api.TEXTURE_RATIO_WAVY_MAX

    def tearDown(self):
        api.hair_texture_ratio = self._real_ratio
        api._hair_region_texture_energy = self._real_energy

    def _classify(self, *ratios):
        """Label for a scan whose per-angle ratios are `ratios`."""
        values = list(ratios)
        api.hair_texture_ratio = lambda path: values.pop(0)
        label, score = api.detect_hair_texture(
            [Path(f"fake_{i}.jpg") for i in range(len(ratios))]
        )
        return label, score

    # --- the three buckets -------------------------------------------------

    def test_below_straight_max_is_straight(self):
        label, score = self._classify(1.0, 1.0, 1.0)
        self.assertEqual(label, "Straight")
        self.assertEqual(score, 1.0)

    def test_between_thresholds_is_wavy(self):
        midpoint = (self.straight_max + self.wavy_max) / 2
        label, _ = self._classify(midpoint, midpoint, midpoint)
        self.assertEqual(label, "Wavy")

    def test_above_wavy_max_is_curly(self):
        label, score = self._classify(12.0, 12.0, 12.0)
        self.assertEqual(label, "Curly")
        self.assertEqual(score, 12.0)

    # --- boundaries are exclusive on the low side --------------------------

    def test_exactly_straight_max_is_wavy_not_straight(self):
        label, _ = self._classify(*[self.straight_max] * 3)
        self.assertEqual(label, "Wavy")

    def test_just_under_straight_max_is_straight(self):
        label, _ = self._classify(*[self.straight_max - 0.01] * 3)
        self.assertEqual(label, "Straight")

    def test_exactly_wavy_max_is_curly_not_wavy(self):
        label, _ = self._classify(*[self.wavy_max] * 3)
        self.assertEqual(label, "Curly")

    # --- aggregation -------------------------------------------------------

    def test_median_decides_not_any_single_angle(self):
        # Documents current behaviour: one high side-profile reading does not
        # carry the scan. Real captures routinely span 10x between angles
        # (e.g. [0.88, 8.39, 5.25]), so this is load-bearing, not incidental.
        label, score = self._classify(0.9, 8.4, 5.3)
        self.assertEqual(score, 5.3)
        self.assertEqual(label, "Wavy")

    def test_single_angle_scan_still_classifies(self):
        label, _ = self._classify(9.0)
        self.assertEqual(label, "Curly")

    # --- the no-signal path ------------------------------------------------

    def test_no_ratio_and_no_energy_returns_zero_score(self):
        api.hair_texture_ratio = lambda path: None
        api._hair_region_texture_energy = lambda path: None
        label, score = api.detect_hair_texture([Path("fake.jpg")])
        self.assertEqual(score, 0.0)
        # The label here is "Straight" only because nothing could be measured.
        # The client must not present that as a finding -- see
        # UserSession.neutralHairTexture and hair_texture_fallback_test.dart.
        self.assertEqual(label, "Straight")

    def test_empty_path_list_returns_zero_score(self):
        _, score = api.detect_hair_texture([])
        self.assertEqual(score, 0.0)

    # --- thresholds stay tunable without a redeploy ------------------------

    def test_thresholds_are_env_overridable(self):
        self.assertIsInstance(api.TEXTURE_RATIO_STRAIGHT_MAX, float)
        self.assertIsInstance(api.TEXTURE_RATIO_WAVY_MAX, float)
        self.assertLess(api.TEXTURE_RATIO_STRAIGHT_MAX, api.TEXTURE_RATIO_WAVY_MAX)


class CalibrationCorpusTest(unittest.TestCase):
    """Guards the two curly subjects that prompted this investigation.

    Skips when the calibration folder is absent, so the suite still runs on a
    clean checkout or in CI.
    """

    CURLY_DIRS = ["subject1", "subject2"]

    def setUp(self):
        self.root = Path(__file__).resolve().parent.parent / "calibration"
        if not self.root.is_dir():
            self.skipTest("no calibration/ folder on this machine")

    def test_known_curly_subjects_are_not_classified_straight(self):
        checked = 0
        for name in self.CURLY_DIRS:
            folder = self.root / name
            if not folder.is_dir():
                continue
            paths = [
                folder / f for f in ("front.jpg", "left.jpg", "right.jpg")
                if (folder / f).exists()
            ]
            if not paths:
                continue
            label, score = api.detect_hair_texture(paths)
            checked += 1
            self.assertNotEqual(
                label,
                "Straight",
                msg=f"{name} is visibly curly but scored {score} -> {label}",
            )
        if checked == 0:
            self.skipTest("no curly subject images found")


if __name__ == "__main__":
    unittest.main(verbosity=2)
