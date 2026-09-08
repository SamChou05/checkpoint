"""Durable remaining budgets across full verified passes and redeliveries."""

import copy
import json
import os
from unittest import mock

import question_bank
from lambda_test_support import FakeBedrockClient, _raw_question, _request_payload
from question_bank_test_support import (
    ConditionalFailure,
    FakeQueue,
    QuestionBankTestCase,
)
from question_generation import _generate_sanitized_questions, _new_provider_call_budget
from request_contract import _normalize_request
from service_errors import ProviderDeadlineExceededError


class BudgetLedger:
    def __init__(self, used=0, daily=0):
        self.job = {"status": {"S": "queued"}, "providerAttemptCount": {"N": str(used)}}
        self.daily = daily
        self.reservations = 0
        self.leases = []

    def update_item(self, **request):
        self.leases.append(request)
        if self.job["status"]["S"] == "complete":
            raise ConditionalFailure()
        values = request["ExpressionAttributeValues"]
        self.job.update(status={"S": "processing"}, leaseToken=values[":token"])
        assert request["ReturnValues"] == "ALL_NEW"
        return {"Attributes": copy.deepcopy(self.job)}

    def transact_write_items(self, **request):
        job_update, quota_update = [item["Update"] for item in request["TransactItems"]]
        job_values, quota_values = [
            item["ExpressionAttributeValues"] for item in (job_update, quota_update)
        ]
        used = int(self.job["providerAttemptCount"]["N"])
        if (
            self.job["leaseToken"] != job_values[":token"]
            or used >= int(job_values[":limit"]["N"])
            or self.daily >= int(quota_values[":limit"]["N"])
        ):
            raise ConditionalFailure()
        self.job["providerAttemptCount"] = {"N": str(used + 1)}
        self.daily += 1
        self.reservations += 1

    def get_item(self, **request):
        return {
            "Item": {"count": {"N": str(self.daily)}}
            if request["TableName"] == "rate-limits"
            else self.job
        }


class ReviewingClient(FakeBedrockClient):
    def __init__(self, *, reject_passes):
        super().__init__(
            [
                self.question_response(
                    _raw_question(
                        "Which conclusion follows from the first stated evidence?"
                    )
                ),
                self.question_response(
                    _raw_question(
                        "Which conclusion follows from the second stated evidence?"
                    )
                ),
            ]
        )
        self.reject_passes = reject_passes

    def converse(self, **request):
        response = super().converse(**request)
        if (
            "<question_review_json>" in request["messages"][0]["content"][0]["text"]
            and len(self.review_calls) <= self.reject_passes
        ):
            response["output"]["message"]["content"][0]["text"] = json.dumps(
                {"reviews": [{"index": 0, "valid": False, "answer": ""}]}
            )
        return response


class AsyncProviderBudgetTests(QuestionBankTestCase):
    def setUp(self):
        super().setUp()
        settings = mock.patch.dict(
            os.environ,
            {
                "MAX_PROVIDER_CALLS_PER_REQUEST": "6",
                "QUESTION_BANK_MAX_RECEIVE_COUNT": "5",
                "MAX_REQUESTS_PER_INSTALL_PER_DAY": "40",
                "RATE_LIMIT_TABLE_NAME": "rate-limits",
            },
        )
        settings.start()
        self.addCleanup(settings.stop)

    def run_job(
        self,
        ledger,
        *,
        reject_passes=0,
        callback=None,
        stale=False,
        desired_count=1,
        commit_side_effect=None,
    ):
        request = _normalize_request(_request_payload(target_count=1))
        # A persisted/request-supplied budget field must not control the allowance.
        request["remainingProviderCalls"] = 999
        meta = {
            "contextRevision": {"S": "other" if stale else "revision"},
            "goalKey": {"S": "goal"},
            "bankID": {"S": "bank"},
            "readyCount": {"N": "0"},
            "generatedCount": {"N": "0"},
            "desiredCount": {"N": str(desired_count)},
            "lowWatermark": {"N": "0"},
            "generationRequest": {"S": json.dumps(request)},
        }
        client = ReviewingClient(reject_passes=reject_passes)
        budgets = []

        def generate(current, reservation):
            budget = _new_provider_call_budget(None, reserve_call=reservation)
            budgets.append(budget.maximum_calls)
            if callback:
                return callback(reservation)
            return _generate_sanitized_questions(current, client, call_budget=budget)

        with (
            mock.patch.object(
                question_bank,
                "_get_item",
                side_effect=[meta, {"currentBankID": {"S": "bank"}}, meta],
            ),
            mock.patch.object(
                question_bank, "_query_question_history", return_value=[]
            ),
            mock.patch.object(
                question_bank,
                "_commit_generated_questions",
                side_effect=commit_side_effect,
            ) as commit,
            mock.patch.object(question_bank, "_ensure_refill"),
            mock.patch.object(question_bank, "_reset_job_for_retry") as retry,
            mock.patch.object(question_bank, "_mark_job_terminal_failure") as terminal,
            mock.patch.object(
                question_bank, "_mark_rate_limited", return_value=True
            ) as rate_limited,
            mock.patch.object(question_bank, "_finish_stale_job") as finish_stale,
        ):
            result = question_bank.handle_worker_event(
                {
                    "Records": [
                        {
                            "messageId": "message",
                            "body": json.dumps(
                                {
                                    "bankPK": "BANK#owner#bank",
                                    "jobID": "job",
                                    "contextRevision": "revision",
                                }
                            ),
                            "attributes": {"ApproximateReceiveCount": "1"},
                        }
                    ]
                },
                None,
                generate,
                dynamodb_client=ledger,
                sqs_client=FakeQueue(),
            )
        return (
            result,
            client,
            budgets,
            commit,
            retry,
            terminal,
            rate_limited,
            finish_stale,
        )

    def test_first_rejection_gets_second_complete_pass_in_same_delivery(self):
        ledger = BudgetLedger()
        result, client, budgets, commit, retry, terminal, _, _ = self.run_job(
            ledger, reject_passes=1
        )
        self.assertEqual(result, {"batchItemFailures": []})
        self.assertEqual(budgets, [6])
        self.assertEqual(
            (len(client.calls), len(client.solution_calls), len(client.review_calls)),
            (2, 2, 2),
        )
        self.assertEqual((ledger.reservations, ledger.daily), (6, 6))
        self.assertEqual(len(commit.call_args.args[8]), 1)
        self.assertEqual(commit.call_args.args[8][0]["verificationPolicyRevision"], 2)
        retry.assert_not_called()
        terminal.assert_not_called()

    def test_two_rejected_passes_terminally_ack_without_waiting_for_redelivery(self):
        ledger = BudgetLedger()
        result, client, _, commit, retry, terminal, _, _ = self.run_job(
            ledger, reject_passes=2
        )
        self.assertEqual(result, {"batchItemFailures": []})
        self.assertEqual(ledger.reservations, 6)
        self.assertEqual(len(client.review_calls), 2)
        commit.assert_not_called()
        retry.assert_not_called()
        terminal.assert_called_once()

    def test_redelivery_seeds_remaining_budget_from_atomic_lease_snapshot(self):
        ledger = BudgetLedger(used=3, daily=3)
        result, client, budgets, commit, retry, terminal, _, _ = self.run_job(ledger)
        self.assertEqual(result, {"batchItemFailures": []})
        self.assertEqual(budgets, [3])
        self.assertEqual((ledger.reservations, ledger.daily), (3, 6))
        self.assertEqual(len(client.review_calls), 1)
        commit.assert_called_once()
        retry.assert_not_called()
        terminal.assert_not_called()

    def test_remainders_smaller_than_full_pass_spend_nothing_and_ack(self):
        for used in (4, 5, 6, 9):
            with self.subTest(used=used):
                ledger = BudgetLedger(used=used, daily=used)
                result, client, budgets, commit, retry, terminal, _, _ = self.run_job(
                    ledger
                )
                self.assertEqual(result, {"batchItemFailures": []})
                self.assertEqual((ledger.reservations, ledger.daily), (0, used))
                self.assertEqual((client.calls, budgets), ([], []))
                commit.assert_not_called()
                retry.assert_not_called()
                terminal.assert_called_once()

    def test_daily_quota_still_charges_each_call_and_stops_at_forty(self):
        ledger = BudgetLedger(daily=38)
        result, client, _, commit, retry, terminal, rate_limited, _ = self.run_job(
            ledger
        )
        self.assertEqual(result, {"batchItemFailures": []})
        self.assertEqual((ledger.reservations, ledger.daily), (2, 40))
        self.assertEqual(len(client.review_calls), 0)
        commit.assert_not_called()
        retry.assert_not_called()
        terminal.assert_not_called()
        rate_limited.assert_called_once()

    def test_deadline_and_transient_failure_retry_when_full_pass_still_fits(self):
        for error in (
            ProviderDeadlineExceededError("deadline"),
            RuntimeError("transport"),
        ):
            with self.subTest(error=type(error).__name__):
                ledger = BudgetLedger()

                def fail(reservation):
                    reservation()
                    raise error

                result, _, _, commit, retry, terminal, _, _ = self.run_job(
                    ledger, callback=fail
                )
                self.assertEqual(
                    result, {"batchItemFailures": [{"itemIdentifier": "message"}]}
                )
                self.assertEqual(ledger.reservations, 1)
                commit.assert_not_called()
                retry.assert_called_once()
                terminal.assert_not_called()

    def test_stale_map_fence_wins_before_exhausted_budget(self):
        ledger = BudgetLedger(used=6)
        result, client, _, commit, retry, terminal, _, finish_stale = self.run_job(
            ledger, stale=True
        )
        self.assertEqual(result, {"batchItemFailures": []})
        self.assertEqual(ledger.reservations, 0)
        self.assertEqual(client.calls, [])
        commit.assert_not_called()
        retry.assert_not_called()
        terminal.assert_not_called()
        finish_stale.assert_called_once()

    def test_lost_commit_response_redelivers_and_repairs_chain_after_six_calls(self):
        ledger = BudgetLedger()

        def committed_but_response_lost(*_args, **_kwargs):
            ledger.job["status"] = {"S": "complete"}
            ledger.job.pop("leaseToken", None)
            raise TimeoutError("Commit response lost after successful transaction")

        result, _, _, commit, retry, terminal, _, _ = self.run_job(
            ledger,
            reject_passes=1,
            desired_count=2,
            commit_side_effect=committed_but_response_lost,
        )
        self.assertEqual(result, {"batchItemFailures": [{"itemIdentifier": "message"}]})
        self.assertEqual(ledger.reservations, 6)
        self.assertEqual(len(commit.call_args.args[8]), 1)
        retry.assert_called_once()
        terminal.assert_not_called()

        generate = mock.Mock()
        meta = {
            "contextRevision": {"S": "revision"},
            "goalKey": {"S": "goal"},
            "desiredCount": {"N": "2"},
            "generatedCount": {"N": "1"},
        }
        with (
            mock.patch.object(
                question_bank,
                "_get_item",
                side_effect=[ledger.job, meta, {"currentBankID": {"S": "bank"}}],
            ),
            mock.patch.object(question_bank, "_ensure_refill") as refill,
        ):
            question_bank._process_job(
                {
                    "bankPK": "BANK#owner#bank",
                    "jobID": "job",
                    "contextRevision": "revision",
                },
                generate,
                ledger,
                FakeQueue(),
            )
        generate.assert_not_called()
        refill.assert_called_once()
        self.assertEqual(ledger.reservations, 6)
