"""Eval-only exact-artifact observations; this module never approves a question.

The generated harness is intended for a managed remote sandbox. The syntax
allowlist is an eligibility rule, not an arbitrary-Python security boundary.
"""

import ast
import base64
import hashlib
import inspect
import json
import math
import textwrap
from typing import Any


PROTOCOL = "checkpoint.execution.v1"
DEFAULT_LIMITS = {
    "input_bytes": 8192,
    "wall_seconds": 2,
    "cpu_seconds": 2,
    "memory_bytes": 268435456,
    "output_bytes": 4096,
    "result_bytes": 4096,
    "transport_bytes": 65536,
}
SAFE_BUILTINS = (
    "abs",
    "all",
    "any",
    "bool",
    "dict",
    "enumerate",
    "float",
    "int",
    "len",
    "list",
    "max",
    "min",
    "pow",
    "print",
    "range",
    "repr",
    "reversed",
    "round",
    "set",
    "sorted",
    "str",
    "sum",
    "tuple",
    "zip",
)
SAFE_METHODS = (
    "append",
    "extend",
    "insert",
    "pop",
    "remove",
    "reverse",
    "sort",
    "count",
    "index",
    "replace",
    "strip",
    "lstrip",
    "rstrip",
    "split",
    "rsplit",
    "splitlines",
    "join",
    "lower",
    "upper",
    "startswith",
    "endswith",
    "find",
    "rfind",
    "isalpha",
    "isdigit",
    "isspace",
)
SAFE_NODES = (
    "Module",
    "Expression",
    "Expr",
    "Constant",
    "Name",
    "Load",
    "Store",
    "Assign",
    "AugAssign",
    "AnnAssign",
    "If",
    "IfExp",
    "For",
    "While",
    "Break",
    "Continue",
    "Pass",
    "Return",
    "FunctionDef",
    "arguments",
    "arg",
    "Call",
    "keyword",
    "Attribute",
    "Subscript",
    "Slice",
    "List",
    "Tuple",
    "Dict",
    "Set",
    "BinOp",
    "UnaryOp",
    "BoolOp",
    "Compare",
    "Add",
    "Sub",
    "Mult",
    "Div",
    "FloorDiv",
    "Mod",
    "Pow",
    "LShift",
    "RShift",
    "BitOr",
    "BitXor",
    "BitAnd",
    "Invert",
    "Not",
    "UAdd",
    "USub",
    "And",
    "Or",
    "Eq",
    "NotEq",
    "Lt",
    "LtE",
    "Gt",
    "GtE",
    "Is",
    "IsNot",
    "In",
    "NotIn",
)


def _json(value: Any) -> str:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    )


def _sha(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _eligibility(source: str, mode: str, inputs: Any) -> str | None:
    try:
        tree = ast.parse(source, filename="<checkpoint-question>", mode=mode)
    except SyntaxError:
        # A compiler observation may itself be the correct quiz answer.
        return None
    except (ValueError, RecursionError, MemoryError) as exc:
        return f"parse_unavailable:{type(exc).__name__}"
    functions = {
        node.name for node in ast.walk(tree) if isinstance(node, ast.FunctionDef)
    }
    entrypoints = (
        {
            node.name
            for node in getattr(tree, "body", [])
            if isinstance(node, ast.FunctionDef)
        }
        if mode == "exec"
        else set()
    )
    for node in ast.walk(tree):
        if type(node).__name__ not in SAFE_NODES:
            return f"unsupported_syntax:{type(node).__name__}"
        # Check parsed names, including Python's normalized Unicode identifiers.
        names = [getattr(node, name, "") for name in ("id", "name", "arg", "attr")]
        if any("__" in name for name in names if isinstance(name, str)):
            return "unsupported_reflection_name"
        if isinstance(node, ast.FunctionDef) and (node.decorator_list or node.returns):
            return "unsupported_function_metadata"
        if isinstance(node, (ast.arg, ast.AnnAssign)) and getattr(
            node, "annotation", None
        ):
            return "unsupported_annotation"
        if isinstance(node, ast.Attribute) and (
            node.attr not in SAFE_METHODS or not isinstance(node.ctx, ast.Load)
        ):
            return "unsupported_attribute"
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                if node.func.id not in set(SAFE_BUILTINS) | functions:
                    return "unsupported_callable"
            elif not isinstance(node.func, ast.Attribute):
                return "unsupported_dynamic_call"
    if inputs is not None and inputs["entrypoint"] not in entrypoints:
        return "entrypoint_not_defined"
    return None


def prepare_execution_job(
    case_id: str,
    source: str,
    *,
    inputs: dict[str, Any] | None = None,
    mode: str = "exec",
    limits: dict[str, int] | None = None,
) -> dict[str, Any]:
    """Build a job without running its source or contacting any service.

    Callers must establish that source and inputs are explicitly displayed. This
    first adapter does not extract code spans or infer missing inputs from prose.
    """
    if not isinstance(case_id, str) or not case_id or not isinstance(source, str):
        raise ValueError("case_id and source must be strings")
    if mode not in ("exec", "eval"):
        raise ValueError("mode must be exec or eval")
    if inputs is not None:
        if (
            mode != "exec"
            or type(inputs) is not dict
            or set(inputs) != {"entrypoint", "args", "kwargs"}
            or type(inputs["entrypoint"]) is not str
            or not inputs["entrypoint"].isidentifier()
            or "__" in inputs["entrypoint"]
            or type(inputs["args"]) is not list
            or type(inputs["kwargs"]) is not dict
            or any(type(key) is not str for key in inputs["kwargs"])
        ):
            raise ValueError(
                "inputs require an explicit entrypoint, JSON args and kwargs"
            )
    configured = dict(DEFAULT_LIMITS)
    if limits is not None:
        if set(limits) - set(configured):
            raise ValueError("unknown limit")
        for key, value in limits.items():
            if type(value) is not int or not 1 <= value <= configured[key]:
                raise ValueError("trial limits may only be tightened")
            configured[key] = value
    # Round-tripping enforces the exact JSON value supplied to the child. Reject
    # tuples, non-string nested dict keys and similar implicit conversions.
    encoded_inputs = _json(inputs)
    if not _same_json_value(inputs, json.loads(encoded_inputs)):
        raise ValueError("inputs must contain exact JSON types")
    payload = {"source": source, "inputs": inputs, "mode": mode, "limits": configured}
    payload_text = _json(payload)
    reason = None
    if (
        len(source.encode("utf-8")) + len(encoded_inputs.encode("utf-8"))
        > configured["input_bytes"]
    ):
        reason = "input_limit"
    if reason is None:
        reason = _eligibility(source, mode, inputs)
    job = {
        "case_id": case_id,
        "job_id": _sha(payload_text),
        "artifact_sha256": _sha(source),
        "input_sha256": _sha(encoded_inputs),
        "mode": mode,
        "limits": configured,
        "eligible": reason is None,
        "unsupported_reason": reason,
    }
    # repr embeds data as a string literal; candidate content is never inserted
    # as Python statements or shell text in the trusted wrapper.
    job["harness_code"] = (
        HARNESS_PREFIX
        + "\nPAYLOAD = json.loads("
        + repr(payload_text)
        + ")\n"
        + "METADATA = json.loads("
        + repr(
            _json(
                {
                    key: job[key]
                    for key in ("job_id", "artifact_sha256", "input_sha256", "mode")
                }
            )
        )
        + ")\n"
        + "CHILD_CODE = "
        + repr(CHILD_CODE)
        + "\n"
        + "\ndef _run_harness():\n"
        + textwrap.indent(HARNESS_BODY, "    ")
        + "\nprint(json.dumps(_run_harness(), ensure_ascii=False, allow_nan=False))\n"
    )
    job["harness_sha256"] = _sha(job["harness_code"])
    return job


def _same_json_value(left: Any, right: Any) -> bool:
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return (
            all(type(key) is str for key in left)
            and left.keys() == right.keys()
            and all(_same_json_value(value, right[key]) for key, value in left.items())
        )
    if isinstance(left, list):
        return len(left) == len(right) and all(
            _same_json_value(a, b) for a, b in zip(left, right)
        )
    return left == right and (not isinstance(left, float) or math.isfinite(left))


HARNESS_PREFIX = """
import ast, builtins, hashlib, json, os, selectors, signal, subprocess, sys, time
"""

# This is application-owned code, not a model-proposed verifier. The candidate
# runs in a separate namespace with a deliberately limited set of capabilities.
CHILD_CODE = r"""
import base64, builtins, contextlib, json, math, resource, sys
payload = json.loads(sys.stdin.buffer.read())
limits = payload["limits"]
resource.setrlimit(resource.RLIMIT_CPU, (limits["cpu_seconds"], limits["cpu_seconds"] + 1))
resource.setrlimit(resource.RLIMIT_AS, (limits["memory_bytes"], limits["memory_bytes"]))
resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
resource.setrlimit(resource.RLIMIT_FSIZE, (0, 0))

class OutputLimit(Exception):
    pass

class UnsupportedResult(Exception):
    pass

class UnsupportedEntrypoint(Exception):
    pass

class Capture:
    def __init__(self):
        self.parts = []
        self.size = 0
    def write(self, text):
        data = text.encode("utf-8")
        available = limits["output_bytes"] - self.size
        if len(data) > available:
            self.parts.append(data[:available])
            self.size += available
            raise OutputLimit()
        self.parts.append(data)
        self.size += len(data)
        return len(text)
    def flush(self):
        pass
    def value(self):
        return b"".join(self.parts).decode("utf-8", errors="replace")
    def raw_value(self):
        return b"".join(self.parts)

def typed(value, seen=None, depth=0):
    if depth > 12:
        raise UnsupportedResult("result_depth")
    kind = type(value)
    if kind is type(None): return {"type": "none", "value": None}
    if kind is bool: return {"type": "bool", "value": value}
    if kind is int:
        text = str(value)
        if len(text) > 2048: raise UnsupportedResult("integer_size")
        return {"type": "int", "value": text}
    if kind is float:
        if not math.isfinite(value): raise UnsupportedResult("nonfinite_float")
        return {"type": "float", "value": value.hex()}
    if kind is str:
        if len(value.encode("utf-8")) > limits["result_bytes"]: raise UnsupportedResult("string_size")
        return {"type": "str", "value": value}
    if kind not in (list, tuple, dict): raise UnsupportedResult("result_type")
    if len(value) > 256: raise UnsupportedResult("result_items")
    seen = set() if seen is None else seen
    if id(value) in seen: raise UnsupportedResult("result_cycle")
    seen.add(id(value))
    try:
        if kind is dict:
            if any(type(key) is not str for key in value): raise UnsupportedResult("dictionary_keys")
            data = [[key, typed(item, seen, depth + 1)] for key, item in value.items()]
        else:
            data = [typed(item, seen, depth + 1) for item in value]
        return {"type": kind.__name__, "value": data}
    finally:
        seen.remove(id(value))

capture = Capture()
namespace = {"__name__": "__checkpoint_question__", "__builtins__": {
    name: getattr(builtins, name) for name in payload["safe_builtins"]
}}
record = {"status": "observed", "stdout": "", "return_value": None,
          "exception": None, "truncated": False, "reason": None,
          "runtime": {"version": sys.version, "implementation": sys.implementation.name,
                      "isolated": sys.flags.isolated, "optimize": sys.flags.optimize,
                      "hash_randomization": sys.flags.hash_randomization}}
try:
    compiled = compile(payload["source"], "<checkpoint-question>", payload["mode"], dont_inherit=True, optimize=0)
    with contextlib.redirect_stdout(capture):
        if payload["mode"] == "eval":
            value = eval(compiled, namespace, namespace)
        else:
            exec(compiled, namespace, namespace)
            inputs = payload["inputs"]
            if inputs is not None and inputs["entrypoint"] not in namespace:
                raise UnsupportedEntrypoint()
            value = namespace[inputs["entrypoint"]](*inputs["args"], **inputs["kwargs"]) if inputs is not None else None
    try:
        record["return_value"] = typed(value)
        if len(json.dumps(record["return_value"], ensure_ascii=False).encode("utf-8")) > limits["result_bytes"]:
            raise UnsupportedResult("serialized_result_size")
    except (UnsupportedResult, ValueError, RecursionError) as exc:
        record.update(status="inconclusive", reason="serialization:" + str(exc), return_value=None)
except OutputLimit:
    record.update(status="inconclusive", reason="output_limit", truncated=True)
except UnsupportedEntrypoint:
    record.update(status="unsupported", reason="entrypoint_unavailable")
except MemoryError:
    record.update(status="inconclusive", reason="memory_limit")
except Exception as exc:
    record["exception"] = {"type": type(exc).__name__, "message": str(exc)[:1024]}
record["stdout"] = capture.value()
record["stdout_base64"] = base64.b64encode(capture.raw_value()).decode("ascii")
sys.stdout.write(json.dumps(record, ensure_ascii=False, allow_nan=False))
"""


HARNESS_BODY = r"""
def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()
def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
actual = {"artifact_sha256": digest(PAYLOAD["source"]),
          "input_sha256": digest(canonical(PAYLOAD["inputs"])),
          "job_id": digest(canonical(PAYLOAD)), "mode": PAYLOAD["mode"]}
result = {"protocol": "checkpoint.execution.v1", **actual, "limits": PAYLOAD["limits"],
          "runtime": {"version": sys.version, "implementation": sys.implementation.name},
          "status": "inconclusive", "compile": None, "child": None,
          "child_exit_code": None, "timed_out": False, "transport_truncated": False,
          "child_reaped": True, "reason": None}
if actual != METADATA:
    result["reason"] = "prepared_metadata_mismatch"
    return result
try:
    compile(PAYLOAD["source"], "<checkpoint-question>", PAYLOAD["mode"], dont_inherit=True, optimize=0)
except SyntaxError as exc:
    result.update(status="observed", compile={"valid": False, "exception": type(exc).__name__,
                  "line": exc.lineno, "offset": exc.offset, "message": exc.msg})
except (ValueError, MemoryError, RecursionError) as exc:
    result["reason"] = "compile_unavailable:" + type(exc).__name__
else:
    result["compile"] = {"valid": True}
    reason = _eligibility(PAYLOAD["source"], PAYLOAD["mode"], PAYLOAD["inputs"])
    if reason is not None:
        result.update(status="unsupported", reason=reason)
        return result
    payload = dict(PAYLOAD, safe_builtins=SAFE_BUILTINS)
    process = None
    selector = selectors.DefaultSelector()
    buffers = {"stdout": bytearray(), "stderr": bytearray()}
    deadline = time.monotonic() + PAYLOAD["limits"]["wall_seconds"]
    try:
        process = subprocess.Popen([sys.executable, "-I", "-S", "-u", "-c", CHILD_CODE],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            start_new_session=True, close_fds=True,
            env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"})
        pending = memoryview(json.dumps(payload, ensure_ascii=False, allow_nan=False).encode("utf-8"))
        for stream, name, event in ((process.stdin, "stdin", selectors.EVENT_WRITE),
                                   (process.stdout, "stdout", selectors.EVENT_READ),
                                   (process.stderr, "stderr", selectors.EVENT_READ)):
            os.set_blocking(stream.fileno(), False)
            selector.register(stream, event, name)
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                result.update(timed_out=True, reason="child_deadline")
                break
            for key, _ in selector.select(min(remaining, 0.1)):
                if key.data == "stdin":
                    try:
                        count = os.write(key.fd, pending)
                        pending = pending[count:]
                    except BrokenPipeError:
                        pending = pending[:0]
                    if not pending:
                        selector.unregister(key.fileobj)
                        key.fileobj.close()
                else:
                    chunk = os.read(key.fd, 8192)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        key.fileobj.close()
                        continue
                    buffer = buffers[key.data]
                    remaining_bytes = PAYLOAD["limits"]["transport_bytes"] - sum(map(len, buffers.values()))
                    buffer.extend(chunk[:max(0, remaining_bytes)])
                    if len(chunk) > remaining_bytes:
                        result.update(transport_truncated=True, reason="child_transport_limit")
                        break
            if result["transport_truncated"]:
                break
    except Exception as exc:
        result["reason"] = "harness_failure:" + type(exc).__name__
    finally:
        if process is not None:
            if result["reason"] is None and process.poll() is None:
                try: process.wait(timeout=max(0, deadline - time.monotonic()))
                except subprocess.TimeoutExpired:
                    result.update(timed_out=True, reason="child_deadline")
            if process.poll() is None:
                try: os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError: pass
            try: process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                result.update(child_reaped=False, reason="child_cleanup_timeout")
            result["child_exit_code"] = process.poll()
        for key in list(selector.get_map().values()):
            key.fileobj.close()
        selector.close()
    if result["reason"] is None and process is not None:
        if process.returncode != 0:
            result["reason"] = "child_nonzero_exit"
        elif buffers["stderr"]:
            result["reason"] = "unexpected_child_stderr"
        else:
            try:
                child = json.loads(buffers["stdout"].decode("utf-8"))
                result["child"] = child
                result["status"] = child["status"]
            except (ValueError, KeyError, TypeError):
                result["reason"] = "invalid_child_envelope"
    result["child_stderr"] = buffers["stderr"].decode("utf-8", errors="replace")
return result
"""

# The remote parent also checks eligibility using the same application-owned
# function. This matters if its Python version accepts syntax the local version
# could not parse. Never execute a merely locally unparseable artifact unchecked.
HARNESS_PREFIX += (
    "\nSAFE_BUILTINS = "
    + repr(SAFE_BUILTINS)
    + "\nSAFE_METHODS = "
    + repr(SAFE_METHODS)
    + "\nSAFE_NODES = "
    + repr(SAFE_NODES)
    + "\nAny = object\n"
    + inspect.getsource(_eligibility)
)


def parse_execution_observation(
    job: dict[str, Any], result_json: dict[str, Any]
) -> dict[str, Any]:
    """Validate service success and correlation; hashes are not signatures."""

    def failed(reason: str) -> dict[str, Any]:
        return {"status": "inconclusive", "reason": reason, "job_id": job["job_id"]}

    if not job["eligible"]:
        return {
            "status": "unsupported",
            "reason": job["unsupported_reason"],
            "job_id": job["job_id"],
        }
    if not isinstance(job.get("harness_code"), str) or _sha(
        job["harness_code"]
    ) != job.get("harness_sha256"):
        return failed("harness_mismatch")
    if (
        not isinstance(result_json, dict)
        or result_json.get("isError") is not False
        or type(result_json.get("exitCode")) is not int
        or result_json["exitCode"] != 0
        or result_json.get("stdErr") != ""
        or not isinstance(result_json.get("stdOut"), str)
    ):
        return failed("service_result_failure")
    raw = result_json["stdOut"]
    if len(raw.encode("utf-8")) > job["limits"]["transport_bytes"]:
        return failed("service_output_limit")
    try:
        record = json.loads(
            raw, object_pairs_hook=_unique_object, parse_constant=_reject_constant
        )
    except (ValueError, RecursionError):
        return failed("invalid_harness_json")
    if not isinstance(record, dict) or record.get("protocol") != PROTOCOL:
        return failed("invalid_protocol")
    if any(
        not _same_json_value(record.get(key), job[key])
        for key in ("job_id", "artifact_sha256", "input_sha256", "mode", "limits")
    ):
        return failed("artifact_mismatch")
    runtime = record.get("runtime")
    if not isinstance(runtime, dict) or any(
        not isinstance(runtime.get(key), str) or not runtime[key]
        for key in ("version", "implementation")
    ):
        return failed("missing_runtime")
    if record.get("status") not in ("observed", "unsupported", "inconclusive"):
        return failed("invalid_status")
    if record["status"] == "observed" and (
        record.get("reason") is not None
        or record.get("timed_out") is not False
        or record.get("transport_truncated") is not False
        or record.get("child_reaped") is not True
    ):
        return failed("inconsistent_observation")
    compile_result = record.get("compile")
    if (
        not isinstance(compile_result, dict)
        or type(compile_result.get("valid")) is not bool
    ):
        return failed("invalid_compile_observation")
    if record["status"] == "observed":
        if compile_result["valid"]:
            child = record.get("child")
            if (
                type(record.get("child_exit_code")) is not int
                or record["child_exit_code"] != 0
                or not isinstance(child, dict)
                or child.get("status") != "observed"
                or child.get("truncated") is not False
                or child.get("reason") is not None
                or not isinstance(child.get("stdout"), str)
            ):
                return failed("invalid_runtime_observation")
            child_runtime = child.get("runtime")
            if (
                not isinstance(child_runtime, dict)
                or not isinstance(child_runtime.get("version"), str)
                or not child_runtime["version"]
                or not isinstance(child_runtime.get("implementation"), str)
                or not child_runtime["implementation"]
                or type(child_runtime.get("isolated")) is not int
                or child_runtime["isolated"] != 1
                or type(child_runtime.get("optimize")) is not int
                or child_runtime["optimize"] != 0
            ):
                return failed("invalid_child_runtime")
            try:
                if len(child["stdout"].encode("utf-8")) > job["limits"]["output_bytes"]:
                    return failed("runtime_output_limit")
                if type(child.get("stdout_base64")) is not str:
                    return failed("missing_runtime_bytes")
                captured = base64.b64decode(child["stdout_base64"], validate=True)
                if captured != child["stdout"].encode("utf-8"):
                    return failed("runtime_bytes_mismatch")
                exception = child.get("exception")
                if exception is None:
                    if not _valid_typed_result(child.get("return_value")):
                        return failed("invalid_return_value")
                    if (
                        len(_json(child["return_value"]).encode("utf-8"))
                        > job["limits"]["result_bytes"]
                    ):
                        return failed("runtime_result_limit")
                elif (
                    type(exception) is not dict
                    or set(exception) != {"type", "message"}
                    or not isinstance(exception["type"], str)
                    or not exception["type"]
                    or not isinstance(exception["message"], str)
                    or len(exception["message"]) > 1024
                    or child.get("return_value") is not None
                ):
                    return failed("invalid_exception_observation")
            except (ValueError, RecursionError):
                return failed("invalid_runtime_data")
        elif (
            compile_result.get("exception")
            not in ("SyntaxError", "IndentationError", "TabError")
            or record.get("child") is not None
        ):
            return failed("invalid_syntax_observation")
    return record


def _valid_typed_result(item: Any, depth: int = 0) -> bool:
    if depth > 12 or type(item) is not dict or set(item) != {"type", "value"}:
        return False
    kind, value = item["type"], item["value"]
    if kind == "none":
        return value is None
    if kind == "bool":
        return type(value) is bool
    if kind == "int":
        if type(value) is not str or len(value) > 2048:
            return False
        try:
            return str(int(value)) == value
        except (ValueError, OverflowError):
            return False
    if kind == "float":
        try:
            number = float.fromhex(value) if type(value) is str else float("nan")
            return math.isfinite(number) and number.hex() == value
        except (ValueError, OverflowError):
            return False
    if kind == "str":
        return type(value) is str
    if kind in ("list", "tuple"):
        return (
            type(value) is list
            and len(value) <= 256
            and all(_valid_typed_result(v, depth + 1) for v in value)
        )
    if kind == "dict":
        if type(value) is not list or len(value) > 256:
            return False
        seen = set()
        for pair in value:
            if (
                type(pair) is not list
                or len(pair) != 2
                or type(pair[0]) is not str
                or pair[0] in seen
            ):
                return False
            seen.add(pair[0])
            if not _valid_typed_result(pair[1], depth + 1):
                return False
        return True
    return False


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def _reject_constant(value: str) -> None:
    raise ValueError("non-finite JSON constant")
