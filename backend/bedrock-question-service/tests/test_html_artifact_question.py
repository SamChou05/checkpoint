import copy
import itertools
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from evals import html_artifact_question as artifact

NODE = Path(
    "/Users/samchou/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"
)
PLAYWRIGHT = Path(
    "/Users/samchou/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright"
)
BROWSERS = Path("/tmp/checkpoint-html-browser-runtime-20260906")


def spec(nested=False):
    html = "<fieldset disabled><legend><input id=x required></legend></fieldset>"
    if nested:
        html = "<fieldset disabled><legend><fieldset disabled><input id=x required></fieldset></legend></fieldset>"
    return {
        "html": html,
        "targetID": "x",
        "properties": [
            "disabled",
            "matches(':disabled')",
            "willValidate",
            "checkValidity()",
        ],
        "alternatives": [
            {"values": values, "reason": reason}
            for values, reason in (
                (
                    [False, False, True, False],
                    "The first legend can exempt its input from this fieldset disabling.",
                ),
                (
                    [False, True, False, True],
                    "A separate disabled ancestor can still bar the target from validation.",
                ),
                (
                    [True, True, False, True],
                    "This proposal treats inherited disabling as an own disabled property.",
                ),
                (
                    [False, False, True, True],
                    "This proposal treats the empty required input as satisfying validation.",
                ),
            )
        ],
        "explanation": "Proposed causal feedback stays unassessed even after the native tuple has been measured.",
        "topic": "HTML form validation",
        "difficulty": 3,
    }


def observation(job, values):
    # A synthetic envelope for binding tests, not claimed native evidence.
    dom = "<html><head></head><body>" + job["spec"]["html"] + "</body></html>"
    return {
        "protocol": artifact.OBSERVATION_PROTOCOL,
        **{
            k: job[k]
            for k in (
                "job_id",
                "artifact_sha256",
                "probe_sha256",
                "observer_source_sha256",
            )
        },
        "status": "observed",
        "reason": "",
        "browser": {"name": "chromium", "version": "test-only"},
        "settings": copy.deepcopy(artifact.SETTINGS),
        "values": values,
        "serialized_dom": dom,
        "serialized_dom_sha256": artifact.digest(dom),
        "target_outer_html": '<input id="x" required="">',
        "cleanup": {"context": "closed", "browser": "closed"},
    }


class HTMLArtifactTests(unittest.TestCase):
    def test_feedback_requires_twelve_nonpadding_characters_without_rewriting(self):
        value = spec()
        value["explanation"] = "  " + "é" * 12 + "\n"
        value["alternatives"][0]["reason"] = "\t" + "x" * 12 + " "
        job = artifact.prepare_html_artifact(value)
        self.assertEqual(job["spec"], value)
        for field in ("explanation", "reason"):
            changed = copy.deepcopy(value)
            if field == "explanation":
                changed[field] = " " + "x" * 11 + " "
            else:
                changed["alternatives"][0][field] = " " + "x" * 11 + " "
            with (
                self.subTest(field=field),
                self.assertRaises(artifact.HTMLArtifactError),
            ):
                artifact.prepare_html_artifact(changed)

    def _run_node(self, data, module):
        env = {
            k: os.environ[k]
            for k in ("PATH", "HOME", "TMPDIR", "LANG")
            if k in os.environ
        }
        env["CHECKPOINT_PLAYWRIGHT_MODULE"] = str(module)
        return subprocess.run(
            [str(NODE), str(artifact.OBSERVER)],
            input=artifact.canonical(data) if isinstance(data, dict) else data,
            text=True,
            capture_output=True,
            timeout=10,
            env=env,
        )

    @unittest.skipUnless(NODE.exists(), "Optional Node runtime unavailable")
    def test_js_feedback_and_input_bounds_precede_browser_import(self):
        job = artifact.prepare_html_artifact(spec())
        for field in ("explanation", "reason"):
            changed = copy.deepcopy(job)
            if field == "explanation":
                changed["spec"][field] = " " + "x" * 11 + " "
            else:
                changed["spec"]["alternatives"][0][field] = " " + "x" * 11 + " "
            changed["job_id"] = artifact.digest(
                artifact.canonical({k: v for k, v in changed.items() if k != "job_id"})
            )
            result = self._run_node(
                changed, "/nonexistent/checkpoint-no-browser-import.cjs"
            )
            observed = json.loads(result.stdout)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(observed["reason"], "invalid_or_oversized_text")
            self.assertEqual(
                observed["cleanup"],
                {"context": "not_created", "browser": "not_created"},
            )
        result = self._run_node(
            "x" * 16385, "/nonexistent/checkpoint-no-browser-import.cjs"
        )
        self.assertEqual(
            json.loads(result.stdout)["reason"], "input_byte_limit_exceeded"
        )

    @unittest.skipUnless(NODE.exists(), "Optional Node runtime unavailable")
    def test_js_failed_cleanup_and_oversized_capture_never_bind(self):
        # Trusted fixed provider stubs exercise lifecycle/capture branches. They
        # do not launch a browser or supply model-authored JavaScript.
        template = """
        let evaluations = 0;
        module.exports = {chromium: {launch: async () => {
          LAUNCH
          return {
            version: () => VERSION,
            newContext: async () => ({
              route: async () => {},
              newPage: async () => ({setContent: async () => {}, evaluate: async () =>
                ++evaluations === 1 ? true : {values: [false,false,true,false], dom: DOM, targetOuterHTML: DOM}}),
              close: async () => {}
            }),
            close: async () => { CLOSE }
          };
        }}};
        """
        job = artifact.prepare_html_artifact(spec())
        for branch, reason in (
            ("launch", "Error"),
            ("close", "cleanup_failed"),
            ("output", "output_byte_limit_exceeded"),
            ("version", "invalid_or_oversized_text"),
        ):
            script = template.replace(
                "LAUNCH",
                "throw new Error('fixed launch failure');"
                if branch == "launch"
                else "",
            )
            script = script.replace(
                "CLOSE",
                "throw new Error('fixed cleanup failure');"
                if branch == "close"
                else "",
            )
            script = script.replace(
                "DOM",
                "'😀'.repeat(4096)"
                if branch == "output"
                else "'<input id=x required>'",
            )
            script = script.replace(
                "VERSION", "'x'.repeat(40000)" if branch == "version" else "'test-only'"
            )
            with tempfile.TemporaryDirectory() as directory:
                module = Path(directory) / "fixed-provider.cjs"
                module.write_text(script)
                result = self._run_node(job, module)
            observed = json.loads(result.stdout)
            self.assertEqual(result.returncode, 1)
            self.assertLessEqual(len(result.stdout.encode("utf-8")), 32768)
            self.assertEqual(observed["status"], "operational_failure")
            self.assertEqual(observed["reason"], reason)
            if branch == "launch":
                self.assertEqual(observed["cleanup"]["browser"], "launch_unconfirmed")
            elif branch == "close":
                self.assertEqual(
                    observed["cleanup"], {"context": "closed", "browser": "failed"}
                )
            else:
                self.assertIsNone(observed["values"])
            with self.assertRaises(artifact.HTMLArtifactError):
                artifact.bind_html_observation(job, observed)

    def test_exact_content_probe_and_native_tuple_define_key(self):
        source = spec()
        source["html"] = (
            "<fieldset disabled>\n<legend>e\u0301  é<input id=x required></legend>\n</fieldset>"
        )
        source["explanation"] += ' Exact "e\u0301  z" stays unchanged.'
        before = copy.deepcopy(source)
        job = artifact.prepare_html_artifact(source)
        self.assertEqual(source, before)
        self.assertTrue(job["prompt"].endswith("\n" + source["html"]))
        self.assertIn(
            "disabled, matches(':disabled'), willValidate, checkValidity() (in order)",
            job["prompt"],
        )
        self.assertIn("#x", job["prompt"])
        result = artifact.bind_html_observation(
            job, observation(job, [False, True, False, True])
        )
        self.assertEqual(
            result["question"]["expectedAnswer"], "[false, true, false, true]"
        )
        self.assertEqual(result["question"]["explanation"], source["explanation"])
        self.assertEqual(result["question"]["feedback_assessment"], "unassessed")
        self.assertEqual(
            result["question"]["choiceExplanations"][job["choices"][1]],
            source["alternatives"][1]["reason"],
        )
        self.assertNotIn("verificationVersion", result["question"])
        self.assertTrue(artifact.validate_bound_question(result))
        self.assertEqual(source, before)

    def test_unknown_script_fields_and_untyped_values_are_rejected(self):
        changes = (
            lambda s: s.update(expectedAnswer="[false, false, true, false]"),
            lambda s: s.update(qualified=True),
            lambda s: s.update(script="alert(1)"),
            lambda s: s.update(
                properties=["disabled", 'constructor.constructor("return 1")()']
            ),
            lambda s: s.update(properties=["disabled", "disabled"]),
            lambda s: s.update(properties=["disabled"]),
            lambda s: s.update(targetID="x;alert(1)"),
            lambda s: s["alternatives"][0]["values"].__setitem__(0, 0),
            lambda s: s["alternatives"][0].update(qualified=True),
        )
        for change in changes:
            value = spec()
            change(value)
            with (
                self.subTest(change=change),
                self.assertRaises(artifact.HTMLArtifactError),
            ):
                artifact.prepare_html_artifact(value)

    def test_active_or_ambiguous_html_is_rejected_before_native_dispatch(self):
        for html in (
            '<input id=x onfocus="alert(1)">',
            "<input id=x><script>alert(1)</script>",
            '<iframe src="file:///etc/passwd" id=x></iframe>',
            '<input id=x><img src="https://example.com/x">',
            '<input id=x style="background:url(https://example.com)">',
            '<input id=x formaction="https://example.com">',
            "<meta http-equiv=refresh content=0><input id=x>",
            "<input id=x id=y>",
            "<input id=x><input id=x>",
            "<fieldset><input id=x>",
            "<fieldset/><input id=x>",
            "<!DOCTYPE html><input id=x>",
            "<input id=y>",
        ):
            value = spec()
            value["html"] = html
            with self.subTest(html=html), self.assertRaises(artifact.HTMLArtifactError):
                artifact.prepare_html_artifact(value)

    def test_full_field_limits_reject_without_clipping(self):
        value = spec()
        value["explanation"] = "x" * 420
        value["alternatives"][0]["reason"] = "y" * 280
        value["html"] += (
            "<!--" + "z" * (320 - len(artifact.render_prompt(value)) - 7) + "-->"
        )
        job = artifact.prepare_html_artifact(value)
        self.assertEqual(len(job["prompt"]), 320)
        self.assertEqual(job["spec"]["explanation"], "x" * 420)
        self.assertEqual(job["spec"]["alternatives"][0]["reason"], "y" * 280)
        self.assertTrue(all(len(c) <= 140 for c in job["choices"]))
        for change in (
            lambda s: s.update(html=s["html"] + " "),
            lambda s: s.update(explanation=s["explanation"] + "x"),
            lambda s: s["alternatives"][0].update(
                reason=s["alternatives"][0]["reason"] + "y"
            ),
        ):
            changed = copy.deepcopy(value)
            change(changed)
            with (
                self.subTest(change=change),
                self.assertRaises(artifact.HTMLArtifactError),
            ):
                artifact.prepare_html_artifact(changed)

    def test_duplicates_and_missing_observed_answer_are_rejected(self):
        value = spec()
        value["alternatives"][0]["values"] = value["alternatives"][1]["values"]
        with self.assertRaises(artifact.HTMLArtifactError):
            artifact.prepare_html_artifact(value)
        job = artifact.prepare_html_artifact(spec())
        missing = next(
            list(v)
            for v in itertools.product((False, True), repeat=4)
            if list(v) not in [a["values"] for a in job["spec"]["alternatives"]]
        )
        with self.assertRaisesRegex(
            artifact.HTMLArtifactError, "observed_answer_not_uniquely_offered"
        ):
            artifact.bind_html_observation(job, observation(job, missing))

    def test_tampered_or_incomplete_observations_cannot_bind(self):
        job = artifact.prepare_html_artifact(spec())
        original = observation(job, [False, False, True, False])
        for change in (
            lambda o: o.update(job_id="wrong"),
            lambda o: o.update(artifact_sha256="wrong"),
            lambda o: o.update(probe_sha256="wrong"),
            lambda o: o.update(observer_source_sha256="wrong"),
            lambda o: o.update(qualified=True),
            lambda o: o.update(status="unsupported"),
            lambda o: o.update(reason="unexpected"),
            lambda o: o["settings"].update(javaScriptEnabled=0),
            lambda o: o["settings"].update(offline=False),
            lambda o: o["cleanup"].update(browser="failed"),
            lambda o: o.update(serialized_dom=o["serialized_dom"] + " changed"),
            lambda o: o["values"].__setitem__(0, 0),
            lambda o: o["browser"].update(name="firefox"),
        ):
            native = copy.deepcopy(original)
            change(native)
            with (
                self.subTest(change=change),
                self.assertRaises(artifact.HTMLArtifactError),
            ):
                artifact.bind_html_observation(job, native)
        with self.assertRaises(artifact.HTMLArtifactError):
            artifact.bind_html_observation(
                artifact.prepare_html_artifact(spec(True)), original
            )

    def test_mutated_display_feedback_or_probe_is_detected(self):
        job = artifact.prepare_html_artifact(spec())
        bundle = artifact.bind_html_observation(
            job, observation(job, [False, False, True, False])
        )
        for change in (
            lambda b: b["question"].update(prompt="Changed scenario"),
            lambda b: b["question"].update(expectedAnswer=b["question"]["choices"][1]),
            lambda b: b["question"].update(explanation="Changed unassessed feedback"),
            lambda b: b["question"].update(feedback_assessment="qualified"),
            lambda b: b["job"]["spec"]["properties"].reverse(),
            lambda b: b["job"]["spec"].update(html="<input id=x>"),
            lambda b: b["evidence"].update(question_sha256="wrong"),
        ):
            changed = copy.deepcopy(bundle)
            change(changed)
            with (
                self.subTest(change=change),
                self.assertRaises(artifact.HTMLArtifactError),
            ):
                artifact.validate_bound_question(changed)

    @unittest.skipUnless(
        NODE.exists() and PLAYWRIGHT.exists() and BROWSERS.exists(),
        "Optional local Chromium runtime unavailable",
    )
    def test_native_first_legend_and_nested_disabled_ancestor(self):
        # Two fixed harmless fixtures, not model-generated JavaScript. The native
        # browser is not mocked. This is not a difficulty or feedback assessment.
        env = {
            k: os.environ[k]
            for k in ("PATH", "HOME", "TMPDIR", "LANG")
            if k in os.environ
        }
        env.update(
            CHECKPOINT_PLAYWRIGHT_MODULE=str(PLAYWRIGHT),
            PLAYWRIGHT_BROWSERS_PATH=str(BROWSERS),
        )
        for nested, expected in (
            (False, [False, False, True, False]),
            (True, [False, True, False, True]),
        ):
            job = artifact.prepare_html_artifact(spec(nested))
            completed = subprocess.run(
                [str(NODE), str(artifact.OBSERVER)],
                input=artifact.canonical(job),
                text=True,
                capture_output=True,
                timeout=35,
                env=env,
            )
            self.assertEqual(
                completed.returncode, 0, completed.stdout + completed.stderr
            )
            self.assertLessEqual(len(completed.stdout.encode("utf-8")), 32768)
            native = json.loads(completed.stdout)
            self.assertEqual(native["values"], expected)
            self.assertEqual(native["settings"], artifact.SETTINGS)
            self.assertEqual(
                native["cleanup"], {"context": "closed", "browser": "closed"}
            )
            self.assertEqual(native["browser"]["name"], "chromium")
            self.assertIn("required", native["target_outer_html"])
            self.assertNotIn("disabled", native["target_outer_html"])
            result = artifact.bind_html_observation(job, native)
            self.assertEqual(
                result["question"]["expectedAnswer"], artifact.render_choice(expected)
            )
            self.assertTrue(artifact.validate_bound_question(result))
