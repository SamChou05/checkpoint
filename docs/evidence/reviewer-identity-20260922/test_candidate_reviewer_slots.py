"""Offline proofs for exact batch identity; no claim of live model qualification."""

import copy
import importlib.util
import json
from pathlib import Path
import unittest

import jsonschema

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("identity_candidate", HERE / "candidate_reviewer_slots.py")
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)
from service_errors import ProviderError  # noqa: E402


def row(valid=True):
    return {"valid": valid, "answer": "é  choice" if valid else "",
            "difficulty": 2 if valid else 0,
            "explanation": " Preserve exact feedback.\n" if valid else "",
            "choiceFeedback": [{"choice": "é  choice", "explanation": " Exact reason.\n"}] if valid else []}


def payload(count):
    return {"reviews": {str(i): row() for i in range(count)}}


class ReviewerIdentityTests(unittest.TestCase):
    def test_all_bounded_counts_enforce_exact_required_keys_and_restore_numeric_order(self):
        for count in range(1, 21):
            with self.subTest(count=count):
                raw = payload(count)
                raw["reviews"] = dict(reversed(list(raw["reviews"].items())))
                schema = candidate.schema(count)
                jsonschema.Draft202012Validator.check_schema(schema)
                jsonschema.validate(raw, schema)
                decoded = json.loads(candidate.adapt(json.dumps(raw), count))
                self.assertEqual([r["index"] for r in decoded["reviews"]], list(range(count)))
                self.assertTrue(all("index" not in s["properties"] for s in schema["properties"]["reviews"]["properties"].values()))

    def test_unknown_missing_noncanonical_and_negative_keys_rejected(self):
        for key in ("-1", "5", "01", "1.0", "true", "x"):
            raw = payload(5)
            raw["reviews"][key] = row(False)
            with self.subTest(key=key), self.assertRaises(ProviderError):
                candidate.adapt(json.dumps(raw), 5)
        for key in ("0", "1", "2", "3", "4"):
            raw = payload(5)
            del raw["reviews"][key]
            with self.subTest(key=key), self.assertRaises(ProviderError):
                candidate.adapt(json.dumps(raw), 5)

    def test_duplicate_json_slot_or_field_never_last_wins(self):
        for raw in ('{"reviews":{"0":{},"0":{}}}',
                    json.dumps(payload(1)).replace('"valid": true', '"valid":false,"valid":true'),
                    '{"reviews":{},"reviews":{}}'):
            with self.subTest(raw=raw), self.assertRaises(ProviderError):
                candidate.adapt(raw, 1)

    def test_embedded_identity_unknown_fields_and_wrong_types_rejected(self):
        for update in ({"index": 0}, {"index": -1}, {"valid": 1}, {"difficulty": True},
                       {"answer": None}, {"choiceFeedback": {}}, {"unknown": "text"}):
            raw = payload(1)
            raw["reviews"]["0"].update(update)
            with self.subTest(update=update), self.assertRaises(ProviderError):
                candidate.adapt(json.dumps(raw), 1)
        for field in row():
            raw = payload(1)
            del raw["reviews"]["0"][field]
            with self.subTest(field=field), self.assertRaises(ProviderError):
                candidate.adapt(json.dumps(raw), 1)

    def test_strict_text_envelope_and_nonfinite_numbers_fail(self):
        for raw in ('[]', '{}', '{"reviews":[]}', 'null', '```json\n{}\n```',
                    json.dumps(payload(1)).replace('"difficulty": 2', '"difficulty": NaN'),
                    json.dumps(payload(1)).replace('"difficulty": 2', '"difficulty": 1e309')):
            with self.subTest(raw=raw), self.assertRaises(ProviderError):
                candidate.adapt(raw, 1)

    def test_exact_positive_bytes_and_negative_nonadmission_remain_v1(self):
        raw = payload(2)
        raw["reviews"]["1"] = row(False)
        # Typed rejected feedback is unused, matching the established v1 rule.
        raw["reviews"]["1"]["answer"] = "a wrong answer must never be surfaced"
        decoded = json.loads(candidate.adapt(json.dumps(raw), 2))
        self.assertEqual(decoded["reviews"][0]["answer"], "é  choice")
        self.assertEqual(decoded["reviews"][0]["explanation"], row()["explanation"])
        self.assertEqual(decoded["reviews"][0]["choiceExplanations"], {"é  choice": " Exact reason.\n"})
        self.assertEqual(decoded["reviews"][1], {"index": 1, "valid": False})

    def test_captured_phantom_arrays_are_not_salvaged(self):
        capture = json.loads((HERE.parent / "question-reliability-release-20260922/pipeline-adaptive-capture.json").read_text())
        for call_index in (2, 5):
            raw = ''.join(b['text'] for b in capture['calls'][call_index]['response']['output']['message']['content'] if 'text' in b)
            # Historical schema accepts these, proving the missing identity rule.
            candidate.adapt_native_response(raw, "default_reviewer_v1")
            with self.subTest(call_index=call_index), self.assertRaises(ProviderError):
                candidate.adapt(raw, 5)

    def test_enum_arrays_still_admit_missing_and_duplicate_identities(self):
        legacy = json.loads(candidate.native_output_config("default_reviewer_v1")["textFormat"]["structure"]["jsonSchema"]["schema"])
        legacy["properties"]["reviews"]["items"]["properties"]["index"]["enum"] = list(range(5))
        for rows in ([], [{"index": 0, **row()}], [{"index": 0, **row()}] * 5):
            jsonschema.validate({"reviews": rows}, legacy)

    def test_count_only_schema_family_and_original_contract_unchanged(self):
        before = copy.deepcopy(candidate.native_output_config("default_reviewer_v1"))
        for value in (False, True, 0, -1, 21, 5.0, "5", None):
            with self.subTest(value=value), self.assertRaises(ValueError):
                candidate.schema(value)
        self.assertEqual(candidate.metadata(5), candidate.metadata(5))
        self.assertNotEqual(candidate.metadata(4)["sha256"], candidate.metadata(5)["sha256"])
        self.assertEqual(candidate.native_output_config("default_reviewer_v1"), before)
        self.assertEqual(__import__('hashlib').sha256(before['textFormat']['structure']['jsonSchema']['schema'].encode()).hexdigest(),
                         '77c15c631555d0d83bfaa2e0ba1c19478c51d2573586220cce2ce94684bfe2fe')


if __name__ == "__main__":
    unittest.main()
