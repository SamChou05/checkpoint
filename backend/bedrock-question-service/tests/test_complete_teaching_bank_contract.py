"""Explicit complete-teaching banks preserve their contract through delivery."""

import copy
import json
from unittest import mock

import question_bank
import question_generation
from question_bank_test_support import (
    ClaimDynamo,
    ConditionalFailure,
    FakeQueue,
    QuestionBankTestCase,
    _claim_records,
    _ensure_payload,
    _event,
)
from request_contract import _normalize_request
from verification_policy import (
    COMPLETE_TEACHING_VERIFICATION_POLICY_REVISION,
    MAX_SUPPORTED_VERIFICATION_POLICY_REVISION,
    VERIFICATION_POLICY_REVISION,
    meets_verification_policy,
)


class LifecycleDynamo:
    """Stateful fixture for ensure/queue/worker boundaries used by these tests.

    The actual claim transaction is exercised separately through the existing
    ClaimDynamo fixture. This fixture models contract/version fences explicitly;
    it is not a general DynamoDB expression interpreter.
    """

    def __init__(self):
        self.items = {}
        self.transactions = []

    @staticmethod
    def key(value):
        return value["pk"]["S"], value["sk"]["S"]

    def get_item(self, **kwargs):
        item = self.items.get(self.key(kwargs["Key"]))
        return {"Item": copy.deepcopy(item)} if item else {}

    def query(self, **kwargs):
        pk = kwargs["ExpressionAttributeValues"][":pk"]["S"]
        return {"Items": [copy.deepcopy(item) for (row_pk, sk), item in self.items.items()
                          if row_pk == pk and sk.startswith("QUESTION#")]}

    def put_item(self, **kwargs):
        item = kwargs["Item"]
        key = self.key(item)
        if key in self.items:
            raise ConditionalFailure()
        self.items[key] = copy.deepcopy(item)
        return {}

    def update_item(self, **kwargs):
        key = self.key(kwargs["Key"])
        item = self.items.setdefault(key, copy.deepcopy(kwargs["Key"]))
        values = kwargs["ExpressionAttributeValues"]
        expression = kwargs["UpdateExpression"]
        condition = kwargs.get("ConditionExpression", "")
        if ":request" in values:
            if (item.get("contextRevision") != values[":revision"]
                    or item.get("feedbackContract") != values.get(":feedbackContract")):
                raise ConditionalFailure()
            if ":feedbackContract" in values:
                assert "feedbackContract = :feedbackContract" in condition
            else:
                assert "attribute_not_exists(feedbackContract)" in condition
            desired = int(values[":desired"]["N"])
            previous = int(item["desiredCount"]["N"])
            grows = "desiredCount = :desired" in expression
            if (grows and desired < previous) or (not grows and desired > previous):
                raise ConditionalFailure()
            item.update(generationRequest=values[":request"],
                        skillAllocationKey=values[":allocation"], lowWatermark=values[":low"])
            if grows:
                item["desiredCount"] = values[":desired"]
        elif key[0].startswith("OWNER#"):
            if ":previous" in values and item.get("currentBankID") != values[":previous"]:
                raise ConditionalFailure()
            item.update(currentBankID=values[":bank"], contextRevision=values[":revision"])
        elif ":processing" in values:
            if item.get("status") != values[":queued"]:
                raise ConditionalFailure()
            item.update(status=values[":processing"], leaseToken=values[":token"],
                        leaseUntil=values[":lease"], enqueueStatus=values[":sent"])
        elif ":sent" in values:
            item["enqueueStatus"] = values[":sent"]
        elif ":stale" in values:
            if key[1].startswith("JOB#"):
                if item.get("leaseToken") != values[":token"]:
                    raise ConditionalFailure()
                item["status"] = values[":stale"]
            else:
                item["state"] = values[":stale"]
        elif ":true" in values:
            item["initialFillComplete"] = values[":true"]
        else:
            raise AssertionError(f"Unexpected lifecycle update: {expression}")
        return {"Attributes": copy.deepcopy(item)}

    def transact_write_items(self, **kwargs):
        transaction = kwargs["TransactItems"]
        self.transactions.append(copy.deepcopy(transaction))
        # Validate every pointer condition before applying any put/update.
        for operation in transaction:
            if check := operation.get("ConditionCheck"):
                item = self.items[self.key(check["Key"])]
                values = check["ExpressionAttributeValues"]
                assert "currentBankID = :bank" in check["ConditionExpression"]
                if item.get("currentBankID") != values[":bank"]:
                    raise ConditionalFailure()
                if ":revision" in values and item.get("contextRevision") != values[":revision"]:
                    raise ConditionalFailure()
        for operation in transaction:
            if put := operation.get("Put"):
                self.put_item(**put)
            elif update := operation.get("Update"):
                item = self.items[self.key(update["Key"])]
                values = update["ExpressionAttributeValues"]
                if ":queued" in values and ":job" in values:
                    item.update(activeJobID=values[":job"], state=values[":queued"])
                elif ":count" in values and ":job" in values:
                    assert "contextRevision = :revision" in update["ConditionExpression"]
                    assert "activeJobID = :job" in update["ConditionExpression"]
                    for field in ("readyCount", "generatedCount"):
                        item[field] = {"N": str(int(item[field]["N"]) + int(values[":count"]["N"]))}
                    item.update(state=values[":state"])
                    item.pop("activeJobID", None)
                elif ":complete" in values:
                    item.update(status=values[":complete"], producedCount=values[":count"])
                    item.pop("leaseToken", None)
                    item.pop("leaseUntil", None)
                else:
                    raise AssertionError(f"Unexpected lifecycle transaction: {update}")
        return {}


def complete_question(index=1, revision=4):
    choices = [f"Supported conclusion {index}", "Reversed condition", "Missing premise", "Contrary result"]
    return {"prompt": f"Given both stated conditions in case {index}, what follows?",
            "choices": choices, "expectedAnswer": choices[0], "topic": "Reasoning",
            "difficulty": 3, "format": "Multiple Choice",
            "explanation": "Both stated conditions establish the supported conclusion.",
            "choiceExplanations": {choice: f"The stated conditions distinguish {choice}." for choice in choices},
            "verificationVersion": 1, "verificationPolicyRevision": revision}


class CompleteTeachingBankContractTests(QuestionBankTestCase):
    def setUp(self):
        super().setUp()
        self.store = LifecycleDynamo()
        self.queue = FakeQueue()

    def ensure(self, *, complete=True, desired=1, revision=None):
        payload = {**_ensure_payload(), "desiredCount": desired}
        if revision is not None:
            payload["contextRevision"] = revision
        if complete:
            payload["feedbackContract"] = "authored_complete"
        return question_bank.ensure_bank(
            payload, _event(), _normalize_request,
            dynamodb_client=self.store, sqs_client=self.queue,
        )

    def run_message(self, message, generate):
        with mock.patch.object(question_bank, "_reserve_provider_attempt", return_value=True):
            question_bank._process_job(message, generate, self.store, self.queue)

    def claim_store(self, bank_id):
        meta = next(copy.deepcopy(item) for item in self.store.items.values()
                    if item.get("bankID") == {"S": bank_id} and item["sk"] == {"S": "META"})
        pointer = next(copy.deepcopy(item) for (pk, _), item in self.store.items.items()
                       if pk.startswith("OWNER#"))
        questions = [copy.deepcopy(item) for (pk, sk), item in self.store.items.items()
                     if pk == meta["pk"]["S"] and sk.startswith("QUESTION#")]
        return ClaimDynamo(meta, pointer, questions)

    def claim(self, bank_id, store, *, claim_id="complete-claim", minimum=None):
        payload = {"bankID": bank_id, "claimID": claim_id, "limit": 20}
        if minimum is not None:
            payload["minimumVerificationPolicyRevision"] = minimum
        with mock.patch.object(question_bank, "_ensure_refill"):
            return question_bank.claim_questions(
                payload, _event(), dynamodb_client=store, sqs_client=FakeQueue(),
            )

    def test_ensure_queue_worker_claim_and_replay_keep_explicit_complete_contract(self):
        self.assertEqual(VERIFICATION_POLICY_REVISION, 2)
        self.assertEqual(COMPLETE_TEACHING_VERIFICATION_POLICY_REVISION, 4)
        self.assertEqual(MAX_SUPPORTED_VERIFICATION_POLICY_REVISION, 4)
        receipt = self.ensure()
        self.assertEqual(len(self.queue.messages), 1)
        message = json.loads(self.queue.messages[0]["MessageBody"])
        persisted = self.store.items[(message["bankPK"], "META")]
        self.assertEqual(persisted["feedbackContract"], {"S": "authored_complete"})
        self.assertEqual(json.loads(persisted["generationRequest"]["S"])["feedbackContract"], "authored_complete")
        authored = complete_question()
        observed = []

        def generate(request, reserve):
            observed.append(copy.deepcopy(request))
            # Use the actual selection function; generation itself is scripted.
            self.assertEqual(question_generation._feedback_contract(request), "authored_complete")
            for _ in range(3):
                reserve()
            return [copy.deepcopy(authored)]

        with mock.patch.dict("os.environ", {"QUESTION_FEEDBACK_CONTRACT": "reviewer_written"}):
            self.run_message(message, generate)
        self.assertEqual(len(observed), 1)
        self.assertEqual(persisted["readyCount"], {"N": "1"})
        self.assertEqual(persisted["generatedCount"], {"N": "1"})
        store = self.claim_store(receipt["bankID"])
        first = self.claim(receipt["bankID"], store)
        replay = self.claim(receipt["bankID"], store, minimum=0)
        self.assertEqual(first, replay)
        returned = first["questions"][0]
        self.assertEqual({key: value for key, value in returned.items() if key != "remoteID"}, authored)
        self.assertEqual(len(returned["choiceExplanations"]), 4)

    def test_same_caller_revision_changed_contract_supersedes_bank_and_queued_fill(self):
        old = self.ensure(complete=False)
        old_message = json.loads(self.queue.messages[-1]["MessageBody"])
        complete = self.ensure()
        self.assertNotEqual(old["bankID"], complete["bankID"])
        self.assertEqual(self.ensure()["bankID"], complete["bankID"])
        generate = mock.Mock(side_effect=AssertionError("A superseded fill reached generation"))
        self.run_message(old_message, generate)
        generate.assert_not_called()
        self.assertEqual(self.store.items[(old_message["bankPK"], f"JOB#{old_message['jobID']}")]["status"],
                         {"S": "superseded"})
        old_store = self.claim_store(old["bankID"])
        with self.assertRaises(question_bank.QuestionBankError) as raised:
            self.claim(old["bankID"], old_store)
        self.assertEqual(raised.exception.code, "stale_bank")

    def test_inflight_fill_cannot_commit_after_same_revision_contract_switch(self):
        old = self.ensure(complete=False)
        message = json.loads(self.queue.messages[-1]["MessageBody"])

        def generate(_request, _reserve):
            self.ensure()
            return [complete_question(revision=2)]

        with mock.patch.object(question_bank, "_reset_job_for_retry"), self.assertRaises(ConditionalFailure):
            self.run_message(message, generate)
        old_rows = [item for (pk, sk), item in self.store.items.items()
                    if pk == message["bankPK"] and sk.startswith("QUESTION#")]
        self.assertEqual(old_rows, [])
        self.assertEqual(self.store.items[(message["bankPK"], "META")]["readyCount"], {"N": "0"})
        self.assertNotEqual(self.ensure()["bankID"], old["bankID"])

    def test_legacy_identity_unchanged_and_caller_revision_cannot_collide_with_contract(self):
        legacy = self.ensure(complete=False)
        reference_id = _claim_records(low=0)[0]
        self.assertEqual(legacy["bankID"], reference_id)
        crafted = self.ensure(complete=False, revision="0123456789abcdef:feedback:authored_complete")
        complete = self.ensure()
        self.assertNotEqual(crafted["bankID"], complete["bankID"])
        self.assertNotEqual(legacy["bankID"], complete["bankID"])

    def test_worker_excludes_lower_stamps_before_counting_ready_inventory(self):
        receipt = self.ensure()
        message = json.loads(self.queue.messages[0]["MessageBody"])
        output = [complete_question(index=revision, revision=revision) for revision in (2, 3, 4)]
        original = copy.deepcopy(output)
        self.run_message(message, lambda *_: output)
        self.assertEqual(output, original)
        store = self.claim_store(receipt["bankID"])
        self.assertEqual(store.meta["generatedCount"], {"N": "1"})
        self.assertEqual(len(store.questions), 1)
        self.assertEqual(json.loads(store.questions[0]["questionJSON"]["S"])["verificationPolicyRevision"], 4)

    def test_complete_stamp_cannot_admit_structural_damage_at_worker_claim_or_replay(self):
        for damage in (
            "missing_feedback", "renamed_feedback", "wrong_format", "missing_format",
            "high_difficulty", "zero_difficulty", "boolean_difficulty",
            "string_difficulty", "missing_difficulty",
        ):
            with self.subTest(damage=damage):
                invalid = complete_question(index=2)
                if damage in ("missing_feedback", "renamed_feedback"):
                    choice = invalid["choices"][1]
                    feedback = invalid["choiceExplanations"].pop(choice)
                    if damage == "renamed_feedback":
                        invalid["choiceExplanations"][choice + " changed"] = feedback
                elif damage == "wrong_format":
                    invalid["format"] = "Short Answer"
                elif damage == "missing_format":
                    invalid.pop("format")
                elif damage == "missing_difficulty":
                    invalid.pop("difficulty")
                else:
                    invalid["difficulty"] = {
                        "high_difficulty": 99, "zero_difficulty": 0,
                        "boolean_difficulty": True, "string_difficulty": "3",
                    }[damage]
                original = copy.deepcopy(invalid)
                self.assertFalse(meets_verification_policy(invalid, 4))
                self.assertFalse(meets_verification_policy(invalid, 2))
                self.assertTrue(meets_verification_policy(invalid, 0))
                legacy = {**invalid, "verificationPolicyRevision": 2}
                self.assertTrue(meets_verification_policy(legacy, 2))

                self.store = LifecycleDynamo()
                self.queue = FakeQueue()
                receipt = self.ensure()
                message = json.loads(self.queue.messages[0]["MessageBody"])
                self.run_message(message, lambda *_: [invalid, complete_question()])
                store = self.claim_store(receipt["bankID"])
                self.assertEqual(store.meta["generatedCount"], {"N": "1"})
                self.assertEqual(len(store.questions), 1)
                self.assertEqual(json.loads(store.questions[0]["questionJSON"]["S"])["prompt"], complete_question()["prompt"])

                # Damage after storage must also fail actual claim admission.
                row = store.questions[0]
                row["questionJSON"] = {"S": json.dumps(invalid)}
                response = self.claim(receipt["bankID"], store)
                self.assertEqual(response["questions"], [])
                self.assertEqual(row["state"], {"S": "discarded"})
                self.assertEqual(json.loads(row["questionJSON"]["S"]), original)

                # Damage after claim creation must fail its replay, not be repaired.
                store = self.claim_store(receipt["bankID"])
                self.claim(receipt["bankID"], store)
                cached = next(iter(store.claims.values()))
                cached_response = json.loads(cached["responseJSON"]["S"])
                cached_response["questions"][0] = invalid
                cached["responseJSON"] = {"S": json.dumps(cached_response)}
                before = copy.deepcopy(store.claims)
                with self.assertRaises(question_bank.QuestionBankError) as raised:
                    self.claim(receipt["bankID"], store)
                self.assertEqual(raised.exception.code, "claim_conflict")
                self.assertEqual(store.claims, before)
                self.assertEqual(invalid, original)

    def test_complete_bank_claim_rejects_legacy_rows_even_when_minimum_omitted_or_lower(self):
        for minimum in (None, 0, 2, 3):
            with self.subTest(minimum=minimum):
                bank_id, meta, pointer, template = _claim_records(low=0)
                meta.update(feedbackContract={"S": "authored_complete"}, readyCount={"N": "3"},
                            generatedCount={"N": "3"}, desiredCount={"N": "3"})
                rows = []
                for revision in (2, 3, 4):
                    row = copy.deepcopy(template)
                    row.update(sk={"S": f"QUESTION#revision-{revision}"}, remoteID={"S": f"revision-{revision}"},
                               questionJSON={"S": json.dumps(complete_question(index=revision, revision=revision))})
                    rows.append(row)
                before = [row["questionJSON"]["S"] for row in rows]
                store = ClaimDynamo(meta, pointer, rows)
                response = self.claim(bank_id, store, minimum=minimum)
                self.assertEqual([q["verificationPolicyRevision"] for q in response["questions"]], [4])
                self.assertEqual([row["state"]["S"] for row in rows], ["discarded", "discarded", "claimed"])
                self.assertEqual([row["questionJSON"]["S"] for row in rows], before)

    def test_complete_bank_rejects_cached_lower_policy_without_relabeling(self):
        for revision in (2, 3):
            with self.subTest(revision=revision):
                bank_id, meta, pointer, template = _claim_records(low=0)
                template["questionJSON"] = {"S": json.dumps(complete_question(revision=revision))}
                store = ClaimDynamo(meta, pointer, [template])
                self.claim(bank_id, store)
                cached = copy.deepcopy(store.claims)
                # A stale lower-policy cache under complete metadata must conflict,
                # not be reissued or upgraded, even to a caller omitting the floor.
                store.meta["feedbackContract"] = {"S": "authored_complete"}
                with self.assertRaises(question_bank.QuestionBankError) as raised:
                    self.claim(bank_id, store)
                self.assertEqual(raised.exception.code, "claim_conflict")
                self.assertEqual(store.claims, cached)

    def test_revision_three_and_four_are_supported_claim_floors_without_default_promotion(self):
        for revision in (3, 4):
            with self.subTest(revision=revision):
                bank_id, meta, pointer, row = _claim_records(low=0)
                row["questionJSON"] = {"S": json.dumps(complete_question(revision=revision))}
                store = ClaimDynamo(meta, pointer, [row])
                self.assertEqual(len(self.claim(bank_id, store, minimum=revision)["questions"]), 1)
        self.assertEqual(VERIFICATION_POLICY_REVISION, 2)

    def test_complete_bank_rejects_racing_lower_policy_cached_response(self):
        bank_id, meta, pointer, template = _claim_records(low=0)
        meta["feedbackContract"] = {"S": "authored_complete"}
        template["questionJSON"] = {"S": json.dumps(complete_question())}
        store = ClaimDynamo(meta, pointer, [template])

        def stale_claim_wins(**kwargs):
            stored = copy.deepcopy(next(operation["Put"]["Item"] for operation in kwargs["TransactItems"]
                                        if "Put" in operation and operation["Put"]["Item"]["itemType"] == {"S": "claim"}))
            response = json.loads(stored["responseJSON"]["S"])
            response["questions"][0]["verificationPolicyRevision"] = 3
            stored["responseJSON"] = {"S": json.dumps(response)}
            store.claims[stored["sk"]["S"]] = stored
            raise ConditionalFailure()

        with mock.patch.object(store, "transact_write_items", side_effect=stale_claim_wins):
            with self.assertRaises(question_bank.QuestionBankError) as raised:
                self.claim(bank_id, store)
        self.assertEqual(raised.exception.code, "claim_conflict")
        cached = next(iter(store.claims.values()))
        self.assertEqual(json.loads(cached["responseJSON"]["S"])["questions"][0]["verificationPolicyRevision"], 3)

    def test_configuration_cannot_retarget_existing_bank_in_either_direction(self):
        for complete in (False, True):
            with self.subTest(complete=complete):
                self.store = LifecycleDynamo()
                self.queue = FakeQueue()
                self.ensure(complete=complete)
                message = json.loads(self.queue.messages[0]["MessageBody"])
                meta = self.store.items[(message["bankPK"], "META")]
                original = meta["generationRequest"]["S"]
                changed = json.loads(original)
                if complete:
                    changed.pop("feedbackContract")
                else:
                    changed["feedbackContract"] = "authored_complete"
                with self.assertRaises(question_bank.QuestionBankError) as raised:
                    question_bank._update_bank_configuration(
                        self.store, "question-banks", {"pk": meta["pk"], "sk": meta["sk"]},
                        message["contextRevision"], changed, 1, 0, 1_700_000_000,
                    )
                self.assertEqual(raised.exception.code, "stale_bank")
                self.assertEqual(meta["generationRequest"]["S"], original)

    def test_worker_does_not_call_provider_if_persisted_contract_was_lost(self):
        self.ensure()
        message = json.loads(self.queue.messages[0]["MessageBody"])
        meta = self.store.items[(message["bankPK"], "META")]
        damaged = json.loads(meta["generationRequest"]["S"])
        damaged.pop("feedbackContract")
        meta["generationRequest"] = {"S": json.dumps(damaged)}
        generate = mock.Mock(side_effect=AssertionError("A damaged contract reached generation"))
        with mock.patch.object(question_bank, "_mark_generation_blocked") as blocked:
            self.run_message(message, generate)
        generate.assert_not_called()
        self.assertEqual(blocked.call_args.args[-1], "feedback_contract_mismatch")
