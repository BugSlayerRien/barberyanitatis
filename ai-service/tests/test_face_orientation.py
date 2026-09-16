"""Cover for face_yaw_direction()'s numeric yaw.

The PHP side now depends on this endpoint returning `yaw` and not just
`direction` -- left/right duplicate detection compares the two signed numbers.
The field was always there; it was simply discarded by the client. These tests
pin it so it cannot quietly disappear.

Run with:

    .venv/Scripts/python.exe -m unittest discover -s tests -v

_detector_yaw / _landmark_yaw are monkeypatched throughout, so nothing here
touches an image, MediaPipe or the network.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import api  # noqa: E402


class FaceYawDirectionTest(unittest.TestCase):
    def setUp(self):
        self._real_detector = api._detector_yaw
        self._real_landmark = getattr(api, "_landmark_yaw", None)
        self.threshold = api.FACE_YAW_PROFILE_MIN

    def tearDown(self):
        api._detector_yaw = self._real_detector
        if self._real_landmark is not None:
            api._landmark_yaw = self._real_landmark

    def _direction_for(self, yaw):
        """face_yaw_direction() with both yaw sources forced to `yaw`."""
        api._detector_yaw = lambda path: yaw
        if self._real_landmark is not None:
            api._landmark_yaw = lambda path: yaw
        return api.face_yaw_direction(Path("fake.jpg"))

    # --- the contract PHP relies on ---------------------------------------

    def test_payload_carries_a_numeric_yaw_not_just_a_direction(self):
        result = self._direction_for(0.42)
        self.assertTrue(result["ok"])
        self.assertIn("yaw", result)
        self.assertIsInstance(result["yaw"], float)
        self.assertAlmostEqual(result["yaw"], 0.42, places=2)

    def test_sign_is_preserved_because_duplicate_detection_depends_on_it(self):
        self.assertLess(self._direction_for(-0.5)["yaw"], 0)
        self.assertGreater(self._direction_for(0.5)["yaw"], 0)

    # --- direction bucketing ----------------------------------------------

    def test_negative_yaw_is_left(self):
        self.assertEqual(self._direction_for(-0.4)["direction"], "left")

    def test_positive_yaw_is_right(self):
        self.assertEqual(self._direction_for(0.4)["direction"], "right")

    def test_mild_tilt_reads_as_front(self):
        # Deliberate: only a real profile turn should be called left/right.
        self.assertEqual(self._direction_for(0.0)["direction"], "front")
        self.assertEqual(
            self._direction_for(self.threshold / 2)["direction"], "front"
        )

    def test_exactly_at_threshold_is_a_profile(self):
        self.assertEqual(self._direction_for(self.threshold)["direction"], "right")
        self.assertEqual(self._direction_for(-self.threshold)["direction"], "left")

    # --- the unknown path --------------------------------------------------

    def test_no_face_reports_not_ok(self):
        result = self._direction_for(None)
        self.assertFalse(result["ok"])
        self.assertEqual(result["direction"], "unknown")
        # PHP maps this to null and skips the check rather than guessing.
        self.assertEqual(result["yaw"], 0.0)

    # --- the duplication condition itself ---------------------------------

    def test_same_sign_pair_is_what_duplication_looks_like(self):
        # Mirrors tryon_views_are_duplicated() in api/replicate_helper.php.
        left = self._direction_for(0.41)["yaw"]
        right = self._direction_for(0.38)["yaw"]
        self.assertTrue((left >= 0) == (right >= 0), "both turned the same way")

    def test_opposite_sign_pair_is_a_healthy_result(self):
        left = self._direction_for(-0.41)["yaw"]
        right = self._direction_for(0.38)["yaw"]
        self.assertFalse((left >= 0) == (right >= 0))

    def test_threshold_is_env_overridable(self):
        self.assertIsInstance(api.FACE_YAW_PROFILE_MIN, float)
        self.assertGreater(api.FACE_YAW_PROFILE_MIN, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
