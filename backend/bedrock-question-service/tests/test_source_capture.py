import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock

from evals.checkpoint_source_capture import capture_sources


class SourceCaptureTests(unittest.TestCase):
    def test_dispatch_is_durable_and_failed_sources_are_preserved_without_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "capture.json"
            urls = ["https://example.com/one", "https://example.com/two"]
            responses = [{"status": "failed", "source_text": None},
                         {"status": "acquired", "source_text": "exact material"}]
            calls = []

            def fetch(url, *, limits):
                stored = json.loads(output.read_text())
                row = stored["records"][len(calls)]
                self.assertEqual(row["status"], "dispatched")
                self.assertEqual(row["url"], url)
                self.assertEqual(limits.body_bytes, 1_048_576)
                calls.append(url)
                return responses[len(calls) - 1]

            result = capture_sources(urls, output, fetch=fetch)
            self.assertEqual(calls, urls)
            self.assertEqual(result["status"], "completed")
            self.assertEqual([r["acquisition"] for r in result["records"]], responses)
            self.assertEqual(json.loads(output.read_text()), result)
            self.assertEqual(result["model_calls"], 0)

    def test_existing_capture_is_never_overwritten_or_refetched(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "capture.json"
            output.write_text("original")
            fetch = Mock()
            with self.assertRaises(FileExistsError):
                capture_sources(["https://example.com/"], output, fetch=fetch)
            fetch.assert_not_called()
            self.assertEqual(output.read_text(), "original")

    def test_unexpected_exception_stops_later_dispatch_and_retains_no_error_text(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "capture.json"
            fetch = Mock(side_effect=RuntimeError("private local detail"))
            with self.assertRaises(RuntimeError):
                capture_sources(["https://example.com/a", "https://example.com/b"],
                                output, fetch=fetch)
            result = json.loads(output.read_text())
            self.assertEqual(result["status"], "stopped")
            self.assertEqual(result["records"][0]["error_type"], "RuntimeError")
            self.assertEqual(result["records"][1]["status"], "unattempted")
            self.assertEqual(fetch.call_count, 1)
            self.assertNotIn("private local detail", output.read_text())

    def test_invalid_batch_cannot_dispatch_or_create_output(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "capture.json"
            fetch = Mock()
            for urls in ([], ["x"] * 2, [str(i) for i in range(6)], [False], "url"):
                with self.subTest(urls=urls), self.assertRaises(ValueError):
                    capture_sources(urls, output, fetch=fetch)
            fetch.assert_not_called()
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
