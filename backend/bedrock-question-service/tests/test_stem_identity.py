"""Versioned content identity across author inventory, old rows and claims."""

import ast
import copy
import json
from pathlib import Path
import uuid
from unittest import mock

import question_bank
from question_bank_common import (
    _normalized_stem_identity,
    _legacy_normalized_stem_identity,
    _stem_fingerprint,
)
from question_generation import _provider_visible_request, _generate_sanitized_questions
from question_quality import _sanitize_questions
from request_contract import _normalize_request
from lambda_test_support import _request_payload, _raw_question
from question_bank_test_support import (
    QuestionBankTestCase,
    ClaimDynamo,
    FakeQueue,
    _claim_records,
    _ensure_payload,
    _event,
)

FIXTURES = json.loads(
    (Path(__file__).parent / "fixtures/stem_identity_contract.json").read_text()
)


class StemIdentityTests(QuestionBankTestCase):
    def test_shared_v2_contract_and_proved_v1_collisions(self):
        for pair in FIXTURES["pairs"]:
            for stem in pair["stems"]:
                ast.parse(stem.split("\n", 1)[1])
            self.assertNotEqual(*pair["outputs"])
            self.assertEqual(
                [_stem_fingerprint(stem, version=1) for stem in pair["stems"]],
                pair["legacyFingerprints"],
            )
            self.assertEqual(
                [_stem_fingerprint(stem) for stem in pair["stems"]],
                pair["fingerprints"],
            )
            self.assertNotEqual(*pair["fingerprints"])
        for first, second in FIXTURES["equivalent"]:
            self.assertEqual(
                _normalized_stem_identity(first), _normalized_stem_identity(second)
            )
        for first, second in FIXTURES["distinct"]:
            self.assertNotEqual(
                _normalized_stem_identity(first), _normalized_stem_identity(second)
            )

    def test_version_is_explicit_and_old_packets_keep_v1_interpretation(self):
        for version in (1, 2):
            payload = _request_payload(target_count=2)
            payload.update(
                stemFingerprintVersion=version,
                blockedStemFingerprints=[
                    _stem_fingerprint(
                        FIXTURES["questions"][0]["prompt"], version=version
                    )
                ],
            )
            request = _normalize_request(payload)
            self.assertEqual(request["stemFingerprintVersion"], version)
            accepted = _sanitize_questions(FIXTURES["questions"], request)
            # v1 collisions cannot be reversed; v2 preserves the second program.
            self.assertEqual(len(accepted), 0 if version == 1 else 1)
            self.assertNotIn(
                "stemFingerprintVersion", _provider_visible_request(request)
            )
        old = _normalize_request(_request_payload())
        self.assertEqual(old["stemFingerprintVersion"], 1)
        for invalid in (0, 3, True, "2", 2.0):
            with self.assertRaises(ValueError):
                _normalize_request(
                    {**_request_payload(), "stemFingerprintVersion": invalid}
                )
            with self.assertRaises(ValueError):
                _stem_fingerprint("Preserve this stem?", version=invalid)

    def test_inventory_ids_preserve_each_proved_code_distinction(self):
        for pair in FIXTURES["pairs"]:
            questions = [
                {**FIXTURES["questions"][index], "prompt": stem}
                for index, stem in enumerate(pair["stems"])
            ]
            prepared = question_bank._prepare_questions("bank", questions, [])
            self.assertEqual(len(prepared), 2)
            self.assertNotEqual(prepared[0]["remoteID"], prepared[1]["remoteID"])
            old_row = {"questionJSON": {"S": json.dumps(prepared[0])}}
            self.assertEqual(
                question_bank._prepare_questions("bank", questions, [old_row]),
                [prepared[1]],
            )

    def test_fresh_generation_and_inventory_preserve_distinct_code_and_exact_duplicates(
        self,
    ):
        request = _normalize_request(_request_payload(target_count=3))
        generated = _sanitize_questions(
            FIXTURES["questions"] + [FIXTURES["questions"][0]], request
        )
        self.assertEqual(len(generated), 2)
        bank_id = "a" * 64
        prepared = question_bank._prepare_questions(bank_id, generated, [])
        self.assertEqual(len(prepared), 2)
        self.assertNotEqual(prepared[0]["remoteID"], prepared[1]["remoteID"])
        first = prepared[0]
        legacy_id = str(
            uuid.uuid5(
                uuid.NAMESPACE_URL,
                f"checkpoint:{bank_id}:stem:"
                + _legacy_normalized_stem_identity(first["prompt"]),
            )
        )
        old_row = {
            "remoteID": {"S": legacy_id},
            "questionJSON": {"S": json.dumps(first)},
            "state": {"S": "claimed"},
            "stemFingerprint": {"S": FIXTURES["pairs"][0]["legacyFingerprints"][0]},
        }
        remaining = question_bank._prepare_questions(bank_id, generated, [old_row])
        self.assertEqual([q["prompt"] for q in remaining], [prepared[1]["prompt"]])
        self.assertNotEqual(remaining[0]["remoteID"], legacy_id)

    def test_v2_claim_recomputes_legacy_row_identity_and_replays_same_result(self):
        bank_id, meta, pointer, template = _claim_records(low=0)
        rows = []
        for index, question in enumerate(FIXTURES["questions"]):
            row = copy.deepcopy(template)
            remote_id = str(uuid.UUID(int=index + 1))
            row.update(
                sk={"S": "QUESTION#" + remote_id},
                remoteID={"S": remote_id},
                questionJSON={"S": json.dumps({**question, "remoteID": remote_id})},
                stemFingerprint={"S": FIXTURES["pairs"][0]["legacyFingerprints"][0]},
            )
            rows.append(row)
        meta.update(
            readyCount={"N": "2"},
            generatedCount={"N": "2"},
            desiredCount={"N": "2"},
            initialFillComplete={"BOOL": True},
        )
        client = ClaimDynamo(meta, pointer, rows)
        payload = {
            "bankID": bank_id,
            "claimID": "v2-old-rows",
            "limit": 2,
            "stemFingerprintVersion": 2,
            "blockedStemFingerprints": [FIXTURES["pairs"][0]["fingerprints"][0]],
        }
        with mock.patch.object(question_bank, "_ensure_refill"):
            first = question_bank.claim_questions(
                payload, _event(), dynamodb_client=client, sqs_client=FakeQueue()
            )
            replay = question_bank.claim_questions(
                payload, _event(), dynamodb_client=client, sqs_client=FakeQueue()
            )
        self.assertEqual(first, replay)
        self.assertEqual(
            [q["prompt"] for q in first["questions"]],
            [FIXTURES["questions"][1]["prompt"]],
        )
        self.assertEqual(rows[0]["state"], {"S": "discarded"})
        self.assertEqual(rows[1]["state"], {"S": "claimed"})
        self.assertEqual(len(client.transactions), 1)

    def test_old_client_claims_keep_explicit_legacy_hash_semantics(self):
        bank_id, meta, pointer, row = _claim_records(low=0)
        prompt = json.loads(row["questionJSON"]["S"])["prompt"]
        client = ClaimDynamo(meta, pointer, [row])
        with mock.patch.object(question_bank, "_ensure_refill"):
            response = question_bank.claim_questions(
                {
                    "bankID": bank_id,
                    "claimID": "old-client",
                    "limit": 1,
                    "blockedStemFingerprints": [_stem_fingerprint(prompt, version=1)],
                },
                _event(),
                dynamodb_client=client,
                sqs_client=FakeQueue(),
            )
        self.assertEqual(response["questions"], [])
        self.assertEqual(row["state"], {"S": "discarded"})

    def test_ensure_persists_version_and_worker_and_top_off_keep_it(self):
        payload = _ensure_payload()
        payload.update(
            stemFingerprintVersion=2,
            blockedStemFingerprints=[FIXTURES["pairs"][0]["fingerprints"][0]],
        )
        meta = {}
        client = mock.Mock()

        def put_item(**kwargs):
            meta.update(kwargs["Item"])
            return {}

        def update_item(**kwargs):
            values = kwargs.get("ExpressionAttributeValues", {})
            if ":request" in values:
                meta["generationRequest"] = values[":request"]
            return {"Attributes": meta}

        client.put_item.side_effect = put_item
        client.update_item.side_effect = update_item
        with (
            mock.patch.object(
                question_bank,
                "_get_item",
                side_effect=lambda _c, _t, key, **_kw: meta or None
                if key["sk"]["S"] == "META"
                else None,
            ),
            mock.patch.object(question_bank, "_ensure_refill"),
            mock.patch.object(question_bank, "_require_current_bank"),
        ):
            old_payload = {
                **payload,
                "blockedStemFingerprints": [
                    FIXTURES["pairs"][0]["legacyFingerprints"][0]
                ],
            }
            old_payload.pop("stemFingerprintVersion")
            question_bank.ensure_bank(
                old_payload,
                _event(),
                _normalize_request,
                dynamodb_client=client,
                sqs_client=FakeQueue(),
            )
            self.assertEqual(
                json.loads(meta["generationRequest"]["S"])["stemFingerprintVersion"], 1
            )
            question_bank.ensure_bank(
                payload,
                _event(),
                _normalize_request,
                dynamodb_client=client,
                sqs_client=FakeQueue(),
            )
        persisted = json.loads(meta["generationRequest"]["S"])
        self.assertEqual(persisted["stemFingerprintVersion"], 2)
        self.assertEqual(
            persisted["blockedStemFingerprints"], payload["blockedStemFingerprints"]
        )
        passes = []

        def author(request, *_args, **_kwargs):
            passes.append(copy.deepcopy(request))
            return {
                "questions": FIXTURES["questions"]
                if len(passes) == 1
                else [
                    _raw_question(
                        "Which conclusion follows in this new reasoning problem?"
                    )
                ]
            }

        with (
            mock.patch(
                "question_generation._generate_provider_payload", side_effect=author
            ),
            mock.patch(
                "question_generation.verify_questions",
                side_effect=lambda questions, *_args, **_kwargs: questions,
            ),
            mock.patch.dict("os.environ", {"GENERATION_ATTEMPTS": "2"}),
        ):
            generated = _generate_sanitized_questions(
                {**persisted, "targetCount": 2}, None
            )
        self.assertEqual(len(generated), 2)
        self.assertEqual(len(passes), 2)
        for top_off in passes:
            self.assertEqual(top_off["stemFingerprintVersion"], 2)
            self.assertEqual(
                top_off["blockedStemFingerprints"], payload["blockedStemFingerprints"]
            )
        observed = []

        def generate(request, _reserve):
            observed.append(request)
            return _sanitize_questions(FIXTURES["questions"], request)

        pointer = {"currentBankID": meta["bankID"]}
        with (
            mock.patch.object(
                question_bank, "_get_item", side_effect=[meta, pointer, meta]
            ),
            mock.patch.object(
                question_bank, "_query_question_history", return_value=[]
            ),
            mock.patch.object(question_bank, "_commit_generated_questions") as commit,
            mock.patch.object(question_bank, "_ensure_refill"),
        ):
            question_bank._process_job(
                {
                    "bankPK": meta["pk"]["S"],
                    "jobID": "job",
                    "contextRevision": meta["contextRevision"]["S"],
                },
                generate,
                client,
                FakeQueue(),
            )
        self.assertEqual(observed[0]["stemFingerprintVersion"], 2)
        self.assertEqual(
            [q["prompt"] for q in commit.call_args.args[8]],
            [FIXTURES["questions"][1]["prompt"]],
        )

    def test_old_queued_request_defaults_to_v1_without_reinterpreting_its_tokens(self):
        request = _normalize_request(_request_payload(target_count=3))
        request.pop("stemFingerprintVersion")
        request["blockedStemFingerprints"] = [
            FIXTURES["pairs"][0]["legacyFingerprints"][0]
        ]
        meta = {
            "bankID": {"S": "bank"},
            "contextRevision": {"S": "revision"},
            "goalKey": {"S": "goal"},
            "readyCount": {"N": "0"},
            "generatedCount": {"N": "0"},
            "desiredCount": {"N": "3"},
            "lowWatermark": {"N": "0"},
            "generationRequest": {"S": json.dumps(request)},
        }
        observed = []
        novel = _raw_question("Which conclusion follows for this new argument?")

        def generate(current, _reserve):
            observed.append(current)
            return _sanitize_questions(FIXTURES["questions"] + [novel], current)

        with (
            mock.patch.object(
                question_bank,
                "_get_item",
                side_effect=[meta, {"currentBankID": {"S": "bank"}}, meta],
            ),
            mock.patch.object(
                question_bank, "_query_question_history", return_value=[]
            ),
            mock.patch.object(question_bank, "_commit_generated_questions") as commit,
            mock.patch.object(question_bank, "_ensure_refill"),
        ):
            question_bank._process_job(
                {
                    "bankPK": "BANK#owner#bank",
                    "jobID": "old-job",
                    "contextRevision": "revision",
                },
                generate,
                mock.Mock(),
                FakeQueue(),
            )
        self.assertNotIn("stemFingerprintVersion", observed[0])
        self.assertEqual(
            [q["prompt"] for q in commit.call_args.args[8]], [novel["prompt"]]
        )
