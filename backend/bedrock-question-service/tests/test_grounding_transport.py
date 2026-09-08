"""Synthetic native observations only; no grounding, AWS or website requests."""

import copy
import json
import multiprocessing
import socket
import unittest
from unittest.mock import Mock, patch

from evals import grounding_transport as grounding

caller = grounding.caller


def native_response():
    return {
        "output": {"message": {"role": "assistant", "content": [
            {"reasoningContent": {"reasoningText": {"text": "PRIVATE_REASONING"}}},
            {"toolUse": {"toolUseId": "lookup1", "name": "nova_grounding",
                         "input": {"query": "a bounded source query"}, "type": "server_tool_use"}},
            {"toolResult": {"toolUseId": "lookup1", "content": [{"text": "[HIDDEN]"}],
                            "status": "success", "type": "nova_grounding_result"}},
            {"text": 'Generated summary with invented https://prose.invalid/link and "quotation".\n'},
            {"citationsContent": {
                "content": [{"text": "Another generated claim, not a source passage."}],
                "citations": [{"location": {"web": {"url": "https://native.example/source#section", "domain": "native.example"}},
                               "title": "Native citation"}]}},
            {"citationsContent": {"citations": [{
                "location": {"web": {"url": "http://native.example/older"}},
                "sourceContent": [{"text": '  Exact provider source text "e\u0301  x".\r\n'}],
            }]}},
        ]}},
        "stopReason": "end_turn", "usage": {"inputTokens": 11, "outputTokens": 23, "secret": "PRIVATE_USAGE"},
        "ResponseMetadata": {"HTTPHeaders": {"secret": "PRIVATE_HEADER"}},
        "additionalModelResponseFields": {"unknown": "PRIVATE_ADDITIONAL"},
    }


def fake_native_worker(connection, request, settings, credentials, deadline):
    # Still exercises the actual inherited worker and parent protocol.
    client = Mock()
    client.converse.return_value = native_response()
    with patch.object(caller.shared, "new_client", return_value=client):
        grounding.grounding_worker(connection, request, settings, credentials, deadline)


class GroundingTransportTests(unittest.TestCase):
    def setUp(self):
        self.request = grounding.grounding_request("Find relevant sources.", "A fixed educational topic.")

    def test_request_is_exact_native_shape_and_utf8_bounded(self):
        self.assertEqual(self.request, {
            "modelId": "us.amazon.nova-2-lite-v1:0",
            "system": [{"text": "Find relevant sources."}],
            "messages": [{"role": "user", "content": [{"text": "A fixed educational topic."}]}],
            "toolConfig": {"tools": [{"systemTool": {"name": "nova_grounding"}}]},
            "inferenceConfig": {"maxTokens": 2048},
            "additionalModelRequestFields": {"reasoningConfig": {"type": "disabled"}},
        })
        for system, user in ((" ", "x"), (None, "x"), ("x", True), ("x", "🙂" * 8_000)):
            with self.subTest(system=system), self.assertRaises(ValueError):
                grounding.grounding_request(system, user)

    def test_projection_keeps_native_evidence_separate_from_generated_prose(self):
        response = native_response()
        original = copy.deepcopy(response)
        projected = grounding.project_grounding_response(response)
        self.assertEqual(response, original)
        self.assertEqual(projected["reasoningContentBlockCount"], 1)
        for secret in ("PRIVATE_REASONING", "PRIVATE_HEADER", "PRIVATE_ADDITIONAL"):
            self.assertNotIn(secret, projected["text"])
        decoded = grounding.decode_grounding_response(projected)
        self.assertEqual(decoded["schema"], grounding.SCHEMA)
        self.assertEqual(decoded["content"], response["output"]["message"]["content"][1:])
        self.assertEqual(decoded["citation_urls"], [
            {"block_index": 3, "citation_index": 0, "url": "https://native.example/source#section"},
            {"block_index": 4, "citation_index": 0, "url": "http://native.example/older"},
        ])
        self.assertIn("https://prose.invalid/link", decoded["generated_text"])
        self.assertNotIn("[HIDDEN]", decoded["generated_text"])
        self.assertNotIn("Exact provider source text", decoded["generated_text"])
        self.assertNotIn("sourceContent", decoded["content"][3]["citationsContent"]["citations"][0])
        self.assertEqual(decoded["content"][1]["toolResult"]["toolUseId"], decoded["content"][0]["toolUse"]["toolUseId"])

    def test_no_native_citation_means_no_url_even_when_model_claims_a_source(self):
        response = native_response()
        response["output"]["message"]["content"] = [{"text": "I searched https://prose.invalid/only."}]
        decoded = grounding.decode_grounding_response(grounding.project_grounding_response(response))
        self.assertEqual(decoded["citation_urls"], [])
        self.assertEqual(decoded["generated_text"], "I searched https://prose.invalid/only.")

    def test_untagged_tampered_or_nonterminal_envelope_is_not_native_evidence(self):
        base = grounding.project_grounding_response(native_response())
        payload = json.loads(base["text"])
        invalid = [
            {**base, "text": "An ordinary assistant answer."},
            {**base, "text": caller.shared.canonical({**payload, "schema": "another-kind"})},
            {**base, "text": base["text"][:-1] + ',"schema":"' + grounding.SCHEMA + '"}'},
            {**base, "text": caller.shared.canonical({**payload, "citation_urls": ["https://forged.invalid"]})},
            {**base, "content_valid": False}, {**base, "stopReason": "max_tokens"},
        ]
        for response in invalid:
            with self.subTest(response=response), self.assertRaises(ValueError):
                grounding.decode_grounding_response(response)

    def test_unknown_malformed_and_oversized_native_content_cannot_become_evidence(self):
        for blocks in (None, [], [{"unknown": "PRIVATE_UNKNOWN"}],
                       [{"text": "answer", "reasoningContent": {"text": "PRIVATE_REASONING"}}],
                       [{"citationsContent": {"citations": [{"source": "https://prose.invalid"}]}}],
                       [{"toolUse": {"name": "other", "input": {}, "toolUseId": "1"}}]):
            response = native_response()
            response["output"]["message"]["content"] = blocks
            projected = grounding.project_grounding_response(response)
            self.assertFalse(projected["content_valid"])
            self.assertNotIn("PRIVATE", projected["text"])
            with self.assertRaises(ValueError):
                grounding.decode_grounding_response(projected)
        response = native_response()
        response["output"]["message"]["content"] = [{"text": "x" * grounding.MAX_PROJECTED_BYTES}]
        with self.assertRaisesRegex(ValueError, "GroundingProjectionLimit"):
            grounding.project_grounding_response(response)

    def test_grounding_worker_overrides_transport_locally_and_refuses_request_drift(self):
        settings = copy.deepcopy(caller.SETTINGS)
        with patch.object(caller, "_worker") as worker:
            grounding.grounding_worker("connection", self.request, settings, False, 123)
        worker.assert_called_once_with("connection", self.request,
            {**settings, **grounding.TRANSPORT_SETTINGS}, False, 123,
            response_projector=grounding.project_grounding_response)
        self.assertEqual(settings, caller.SETTINGS)
        for changes in ({"modelId": "other"}, {"inferenceConfig": {"maxTokens": 4096}}, {"toolConfig": {}}):
            with patch.object(caller, "_worker") as worker, self.assertRaises(ValueError):
                grounding.grounding_worker("connection", {**self.request, **changes}, settings, False, 123)
            worker.assert_not_called()

    def test_sdk_projection_seam_keeps_default_behavior_and_strips_private_metadata(self):
        for projector in (None, grounding.project_grounding_response):
            receiver, sender = socket.socketpair()
            client, messages = Mock(), []
            client.converse.return_value = native_response()
            kwargs = {} if projector is None else {"response_projector": projector}
            with patch.object(caller.shared, "new_client", return_value=client):
                caller._sdk_exchange(sender, self.request, caller.SETTINGS, False, **kwargs)
            sender.close()
            raw = bytearray()
            while chunk := receiver.recv(65_536):
                raw.extend(chunk)
            receiver.close()
            messages = [json.loads(line) for line in raw.splitlines()]
            response = messages[1]["response"]
            self.assertEqual([m["kind"] for m in messages], ["dispatch", "response", "complete"])
            for secret in ("PRIVATE_REASONING", "PRIVATE_HEADER", "PRIVATE_ADDITIONAL", "PRIVATE_USAGE"):
                self.assertNotIn(secret.encode(), raw)
            client.converse.assert_called_once_with(**self.request)
            client.close.assert_called_once()
            if projector is None:
                expected = caller.recorded._response(native_response())
                expected["usage"] = {"inputTokens": 11, "outputTokens": 23}
                self.assertEqual(response, expected)
                self.assertFalse(response["content_valid"])
            else:
                self.assertEqual(len(grounding.decode_grounding_response(response)["citation_urls"]), 2)

    def test_existing_parent_lifecycle_accepts_tagged_projection_without_another_supervisor(self):
        states = []
        result = caller.observe_request(self.request, worker=fake_native_worker,
            context=multiprocessing.get_context("fork"), timeout=2, on_progress=states.append)
        self.assertEqual(result["status"], "completed")
        self.assertTrue(result["provider_dispatch_attempted"])
        self.assertTrue(result["usage_known"])
        self.assertTrue(result["local_worker_reaped"])
        self.assertTrue(result["local_process_group_cleanup_confirmed"])
        self.assertFalse(result["termination_attempted"])
        self.assertEqual(result["worker_exitcode"], 0)
        self.assertLess(result["sdk_elapsed_seconds"], 2)
        self.assertEqual(len(grounding.decode_grounding_response(result["response"])["citation_urls"]), 2)
        self.assertIsNone(states[0]["provider_dispatch_attempted"])


if __name__ == "__main__":
    unittest.main()
