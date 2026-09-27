"""Exercise model boundaries and actual source-backed recommendation assembly."""
import io
import json
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from PIL import Image

from analysis.coach_response_builder import CoachResponseBuilder
from analysis.coaching_contract import CoachDecision, VisualReview
from analysis.video_observations import measure_poses


def decision_for(case):
    return CoachDecision(status="recommend", summary="Try one pivot rehearsal, then compare your strike.",
                         focus="Backswing pivot", rationale="The observed sequence matches the selected case.",
                         observation_ids=["V01"], case_id=case["id"], cue="Bump gently, then turn to create a gap.",
                         reassess="Compare the same view and strike, then a swing without the prop.", questions=[],
                         prerequisite_checks=[{"condition_index": i, "status": "supported", "observation_ids": ["V01"],
                                               "explanation": "Synthetic test observation supplies the condition."}
                                              for i in range(len(case["applicability"]))])


class GroundedCoachingTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict("os.environ", {"OPENAI_API_KEY": ""})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.builder = CoachResponseBuilder()
        self.case = self.builder.library.cases["DcqwwGio81y-C02"]
        self.observation = {"id": "V01", "description": "Synthetic matching visual evidence", "frame_indices": [0],
                            "confidence": 0.8, "kind": "visual_interpretation", "topic": "sternum pelvis falling back"}

    def test_recommendation_requires_all_conditions_and_real_references(self):
        decision = decision_for(self.case)
        self.builder.validate_decision(decision, [self.observation], [self.case])
        mutations = [
            {"case_id": "invented"}, {"observation_ids": ["missing"]}, {"cue": None},
            {"prerequisite_checks": []},
            {"prerequisite_checks": [c.model_copy(update={"status": "unknown"}) for c in decision.prerequisite_checks]},
            {"prerequisite_checks": [decision.prerequisite_checks[0]] * len(decision.prerequisite_checks)},
        ]
        for mutation in mutations:
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                self.builder.validate_decision(decision.model_copy(update=mutation), [self.observation], [self.case])
        for update in ({"confidence": 0.3}, {"kind": "measured_2d"}):
            with self.subTest(update=update), self.assertRaises(ValueError):
                self.builder.validate_decision(decision, [{**self.observation, **update}], [self.case])

    def test_assembled_drill_comes_from_source_and_is_persistable(self):
        review = VisualReview(findings=[{k: v for k, v in {**self.observation, "phase": "backswing"}.items() if k != "kind"}],
                              strengths=[], missing_evidence=[])
        outputs = iter([review, decision_for(self.case)])
        calls = []

        def parse(**kwargs):
            calls.append(kwargs)
            return SimpleNamespace(status="completed", output_parsed=next(outputs))

        self.builder.client = SimpleNamespace(responses=SimpleNamespace(parse=parse))
        buffer = io.BytesIO()
        Image.new("RGB", (80, 120)).save(buffer, "PNG")
        bundle = self.builder.build_coaching_bundle([], [], frames=[(0, buffer.getvalue())], fps=30, vantage="FO")
        self.assertEqual(bundle.detail["status"], "recommend")
        self.assertEqual(len(bundle.drills), 1)
        self.assertEqual(bundle.drills[0].id, self.case["id"])
        self.assertIn(self.case["intervention"]["setup"], bundle.drills[0].summary)
        self.assertEqual(bundle.detail["sources"][1]["start_seconds"], 123)
        self.assertEqual(bundle.detail["evidence"][0]["timestamps"], [0])
        self.assertEqual(len(calls), 2)
        self.assertFalse(calls[0]["store"])
        self.assertTrue(any(c["type"] == "input_image" for c in calls[0]["input"][0]["content"]))
        self.assertEqual(json.loads(json.dumps(bundle.context))["decision"]["case_id"], self.case["id"])

    def test_invalid_visual_timestamp_and_model_failure_withhold_drills(self):
        review = VisualReview(findings=[dict(id="V01", description="Not supplied", frame_indices=[999], confidence=0.9,
                                            phase="top", topic="pivot")], strengths=[], missing_evidence=[])
        self.builder.client = SimpleNamespace(responses=SimpleNamespace(
            parse=lambda **kw: SimpleNamespace(status="completed", output_parsed=review)))
        buffer = io.BytesIO()
        Image.new("RGB", (80, 120)).save(buffer, "PNG")
        bundle = self.builder.build_coaching_bundle([], [], frames=[(0, buffer.getvalue())])
        self.assertEqual(bundle.drills, [])
        self.assertEqual(bundle.detail["status"], "model_unavailable")
        self.assertEqual(bundle.detail["evidence"], [])

    def test_no_key_is_explicit_and_keeps_reported_context(self):
        bundle = self.builder.build_coaching_bundle([], [], golfer_context={"club": "7 iron"})
        self.assertEqual(bundle.detail["status"], "model_unavailable")
        self.assertEqual(bundle.drills, [])
        self.assertEqual(bundle.detail["evidence"][0]["kind"], "golfer_report")
        self.assertEqual(bundle.detail["evidence"][0]["timestamps"], [])

    def test_image_metrics_geometry_and_dropout(self):
        poses = []
        for i in range(5):
            points = {name: SimpleNamespace(x=x, y=y, visibility=0.9) for name, x, y in [
                ("nose", 0.3 + i * 0.01, 0.2), ("left_shoulder", 0.3, 0.4), ("right_shoulder", 0.5, 0.4),
                ("left_hip", 0.3, 0.6), ("right_hip", 0.5, 0.6),
                ("left_wrist", 0.3, 0.5), ("right_wrist", 0.5, 0.5)]}
            poses.append(SimpleNamespace(frame_index=i * 2, keypoints=points))
        result = measure_poses(poses, fps=30, width=1920, height=1080, vantage="DTL")
        values = {m.key: m.value for m in result.metrics}
        self.assertAlmostEqual(values["head_x_range_pct"], 4)
        self.assertEqual(values["torso_image_angle_range_deg"], 0)
        self.assertEqual(result.observations[0]["frame_indices"], [0, 8])
        for pose in poses:
            for point in pose.keypoints.values():
                point.visibility = 0.1
        poor = measure_poses(poses, fps=30, width=1920, height=1080, vantage="DTL")
        self.assertEqual(poor.metrics, [])
        self.assertEqual(poor.layers_by_frame, {})


if __name__ == "__main__":
    unittest.main()
