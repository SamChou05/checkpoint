"""Closed flat author transport and server-owned quantitative provenance.

Flat node identities are positions, never model-written IDs. Only this adapter
creates compiled provenance, after the bounded compiler has derived all learner
content. No provider flag, key, digest, or teaching can substitute for compilation.
"""

import copy
from dataclasses import dataclass
import json

from quantitative_task_compiler import (
    MAX_EXPRESSION_DEPTH, MAX_EXPRESSION_NODES, RELATIONS, SELECTIONS, UNITS,
    QuantitativeTaskError, compile_question,
)


MIXED_AUTHOR_CONTRACT = "question_author_mixed_v1"
SLOTS = ("a", "b", "c", "d")
LEARNER_FIELDS = ("prompt", "choices", "expectedAnswer", "explanation", "choiceExplanations")
METADATA = ("topic", "difficulty", "skillID", "objectiveID", "objective")


class QuantitativeAuthoringError(ValueError):
    """Malformed typed transport or broken trusted content association."""


def _object(properties, required=None):
    return {"type": "object", "properties": properties,
            "required": list(properties) if required is None else required,
            "additionalProperties": False}


def mixed_author_schema(prose_schema, *, shared=False):
    """Nonrecursive transport grammar; all tree/value limits remain local."""
    string, integer = {"type": "string"}, {"type": "integer"}
    node = {"anyOf": [
        _object({"kind": {"type": "string", "enum": ["literal"]}, "value": string}),
        _object({"kind": {"type": "string", "enum": ["variable"]}}),
        _object({"kind": {"type": "string", "enum": ["binary"]},
                 "op": {"type": "string", "enum": ["add", "sub", "mul", "div"]},
                 "left": integer, "right": integer}),
    ]}
    common = {"unit": {"type": "string", "enum": sorted(UNITS)},
              "nodes": {"type": "array", "items": {"$ref": "#/$defs/node"} if shared else node}}
    choices = _object({slot: string for slot in SLOTS})
    exact = _object({"kind": {"type": "string", "enum": ["exact_value"]},
                     **common, "root": integer, "choices": choices})
    scalar = _object({"kind": {"type": "string", "enum": ["scalar_condition"]},
                      **common,
                      "condition": _object({"left": integer,
                                            "relation": {"type": "string", "enum": list(RELATIONS)},
                                            "right": integer}),
                      "selection": {"type": "string", "enum": sorted(SELECTIONS)},
                      "domain": {"anyOf": [
                          _object({"kind": {"type": "string", "enum": ["offered"]}}),
                          _object({"kind": {"type": "string", "enum": ["integer_interval"]},
                                   "lower": integer, "upper": integer}),
                      ]}, "choices": choices})
    task = {"anyOf": [exact, scalar]}
    quantitative = _object({"kind": {"type": "string", "enum": ["quantitative"]},
                            "task": {"$ref": "#/$defs/task"} if shared else task,
                            **{name: integer if name == "difficulty" else string for name in METADATA}},
                           ["kind", "task", "topic", "difficulty"])
    prose = _object({"kind": {"type": "string", "enum": ["prose"]},
                     "question": {"$ref": "#/$defs/proseQuestion"} if shared else copy.deepcopy(prose_schema)})
    schema = _object({"questions": {"type": "array", "items": {"anyOf": [prose, quantitative]}}})
    if shared:
        schema["$defs"] = {"node": node, "task": task, "proseQuestion": copy.deepcopy(prose_schema)}
    return schema


MIXED_AUTHOR_INSTRUCTIONS = """
MIXED AUTHOR CONTRACT (question_author_mixed_v1): Return {"questions":[...]} using exactly one of two closed
row variants. This replaces earlier author output examples only. Preserve all
existing subject, assignment, difficulty, novelty and content-quality requirements.

For ordinary subject questions return {"kind":"prose","question":{...}}. The
nested question uses prompt, choices with exactly a/b/c/d string slots,
explanation, correctChoice (a/b/c/d), topic, difficulty, format:"Multiple Choice",
and optional skillID/objectiveID/objective. No expectedAnswer or choice feedback.

For an objective that is fully served by a self-contained numerical expression
or scalar-condition task, return {"kind":"quantitative","task":{...},"topic":
"...","difficulty":2,...optional skill/objective metadata}. Do not use this
variant when a scenario, empirical or physical law, causal inference, programming
syntax, representation distinction or other subject facts are needed. Use the
ordinary prose variant for those tasks; do not reduce their objective to arithmetic.
The application renders the entire quantitative question, answer and all teaching.
Never return a proposed key, stem, explanation, approval or provenance in this row.

A quantitative task has kind exact_value or scalar_condition, a unit from the
schema, nodes, and four numeric choices in a/b/c/d slots. Exact tasks have root.
Scalar tasks have condition:{left,relation,right}, selection (any_satisfying,
minimum,maximum), and domain:{kind:"offered"} or {kind:"integer_interval",lower,
upper}. Relations lt/le/gt/ge/eq/ne mean </<=/>/>=/=/!=. An integer interval is
inclusive and contains at most 201 values within -1000000..1000000. Selection
minimum/maximum applies to the entire stated domain, not an unstated preference.
Any_satisfying requires exactly one offered value to satisfy the condition.

Nodes are a flat array of 1..31 entries. Each position is its identity. A literal
is {kind:"literal",value:"exact number"}; a variable is {kind:"variable"} and
means x (scalar tasks only); a binary is {kind:"binary",op:"add|sub|mul|div",
left:earlier_position,right:earlier_position}. Roots are positions in nodes. Use
only backward references and every node. Shared references count again toward
the expanded expression's maximum 31 nodes (both condition roots combined) and
depth 6. No code, function calls, free expression strings, or unstated premises.
Number strings are integers, decimals or fractions with positive denominator,
at most 24 characters, with numerator magnitude and denominator at most 10^9.
All numerical values use one declared unit; no implicit conversion or dimensional
inference. Distinct numeric spellings of the same value are duplicate choices.
Undefined arithmetic anywhere in the domain, zero/multiple offered answers, or
equivalent choices reject the item. A rejected spec cannot be repaired as prose
in the same row. On a later top-up, author a new complete task or a fresh ordinary
question matching the original objective; no bypass of the compilation failure.
""".strip()


def _fields(value, required, optional=()):
    if (type(value) is not dict or len(value) > len(required) + len(optional)
            or any(type(key) is not str for key in value)
            or not set(required) <= set(value) or set(value) - set(required) - set(optional)):
        raise QuantitativeAuthoringError("Invalid closed author fields.")


def flat_task_spec(task):
    """Validate the flat graph and its expanded bounds BEFORE building trees."""
    if type(task) is not dict or type(task.get("kind")) is not str:
        raise QuantitativeAuthoringError("Invalid task kind.")
    kind = task["kind"]
    if kind == "exact_value":
        _fields(task, ("kind", "unit", "nodes", "root", "choices"))
        roots = [task["root"]]
    elif kind == "scalar_condition":
        _fields(task, ("kind", "unit", "nodes", "condition", "selection", "domain", "choices"))
        _fields(task["condition"], ("left", "relation", "right"))
        roots = [task["condition"]["left"], task["condition"]["right"]]
    else:
        raise QuantitativeAuthoringError("Invalid task kind.")
    nodes = task["nodes"]
    if type(nodes) is not list or not 1 <= len(nodes) <= MAX_EXPRESSION_NODES:
        raise QuantitativeAuthoringError("Invalid node count.")
    sizes, depths, references = [], [], []
    for index, node in enumerate(nodes):
        if type(node) is not dict or type(node.get("kind")) is not str:
            raise QuantitativeAuthoringError("Invalid node kind.")
        node_kind = node["kind"]
        if node_kind == "literal":
            _fields(node, ("kind", "value"))
            if type(node["value"]) is not str:
                raise QuantitativeAuthoringError("Literal must be a number string.")
            size, depth, refs = 1, 1, ()
        elif node_kind == "variable":
            _fields(node, ("kind",))
            if kind != "scalar_condition":
                raise QuantitativeAuthoringError("Variable in exact task.")
            size, depth, refs = 1, 1, ()
        elif node_kind == "binary":
            _fields(node, ("kind", "op", "left", "right"))
            if type(node["op"]) is not str or node["op"] not in {"add", "sub", "mul", "div"}:
                raise QuantitativeAuthoringError("Invalid binary operator.")
            refs = (node["left"], node["right"])
            if any(type(ref) is not int or not 0 <= ref < index for ref in refs):
                raise QuantitativeAuthoringError("Nodes require backward integer references.")
            size = 1 + sum(sizes[ref] for ref in refs)
            depth = 1 + max(depths[ref] for ref in refs)
        else:
            raise QuantitativeAuthoringError("Invalid node kind.")
        if size > MAX_EXPRESSION_NODES or depth > MAX_EXPRESSION_DEPTH:
            raise QuantitativeAuthoringError("Expanded expression exceeds compiler limits.")
        sizes.append(size)
        depths.append(depth)
        references.append(refs)
    if any(type(root) is not int or not 0 <= root < len(nodes) for root in roots):
        raise QuantitativeAuthoringError("Invalid root reference.")
    if sum(sizes[root] for root in roots) > MAX_EXPRESSION_NODES:
        raise QuantitativeAuthoringError("Combined roots exceed compiler node limit.")
    reachable, pending = set(), list(roots)
    while pending:
        index = pending.pop()
        if index not in reachable:
            reachable.add(index)
            pending.extend(references[index])
    if len(reachable) != len(nodes):
        raise QuantitativeAuthoringError("Unreachable author nodes.")

    def tree(index):
        node = nodes[index]
        if node["kind"] == "literal":
            return {"value": node["value"]}
        if node["kind"] == "variable":
            return {"variable": "x"}
        return {"op": node["op"], "left": tree(node["left"]), "right": tree(node["right"])}

    _fields(task["choices"], SLOTS)
    spec = {"kind": kind, "unit": task["unit"], "choices": [task["choices"][slot] for slot in SLOTS]}
    if kind == "exact_value":
        spec["expression"] = tree(roots[0])
    else:
        spec.update(condition={"left": tree(roots[0]), "relation": task["condition"]["relation"],
                               "right": tree(roots[1])},
                    selection=task["selection"], domain=task["domain"])
    return spec


@dataclass(frozen=True)
class CompiledCandidate:
    """Private immutable sidecar; never serialized into model or learner data."""

    spec_json: str
    learner_json: str

    @classmethod
    def from_task(cls, task):
        spec = flat_task_spec(task)
        learner = compile_question(spec)
        return cls(json.dumps(spec, sort_keys=True, allow_nan=False),
                   json.dumps(learner, sort_keys=True, allow_nan=False))

    def content(self, question=None):
        rendered = compile_question(json.loads(self.spec_json))
        if rendered != json.loads(self.learner_json):
            raise QuantitativeAuthoringError("Compiled provenance changed.")
        if question is not None and any(question.get(key) != rendered[key] for key in LEARNER_FIELDS):
            raise QuantitativeAuthoringError("Compiled learner content changed.")
        return rendered


def checked_provenance(mapping, count):
    if mapping is None:
        return {}
    if (type(mapping) is not dict
            or any(type(index) is not int or not 0 <= index < count
                   or type(value) is not CompiledCandidate for index, value in mapping.items())):
        raise QuantitativeAuthoringError("Compiled provenance must be a trusted ordinal sidecar.")
    return dict(mapping)


def prepare_mixed_rows(payload):
    """Keep source positions even for a failed spec; never fall back to prose."""
    _fields(payload, ("questions",))
    if type(payload["questions"]) is not list:
        raise QuantitativeAuthoringError("Questions must be an array.")
    rows, compiled, failures = [], {}, []
    for index, row in enumerate(payload["questions"]):
        if type(row) is not dict or type(row.get("kind")) is not str:
            raise QuantitativeAuthoringError("Invalid author row.")
        if row["kind"] == "prose":
            _fields(row, ("kind", "question"))
            question = copy.deepcopy(row["question"])
            _fields(question, ("prompt", "choices", "explanation", "correctChoice", "topic", "difficulty", "format"),
                    ("skillID", "objectiveID", "objective"))
            _fields(question["choices"], SLOTS)
            key = question.pop("correctChoice")
            if type(key) is not str or key not in SLOTS:
                raise QuantitativeAuthoringError("Invalid prose key slot.")
            slots = question["choices"]
            question["choices"] = [slots[slot] for slot in SLOTS]
            question["expectedAnswer"] = slots[key]
            rows.append(question)
        elif row["kind"] == "quantitative":
            _fields(row, ("kind", "task", "topic", "difficulty"), ("skillID", "objectiveID", "objective"))
            try:
                provenance = CompiledCandidate.from_task(row["task"])
            except (QuantitativeAuthoringError, QuantitativeTaskError) as error:
                rows.append(None)
                code = getattr(error, "code", "invalid_spec")
                failures.append(code if code in {"no_answer", "multiple_answers", "equivalent_choices"} else "invalid_spec")
                continue
            compiled[index] = provenance
            rows.append({**provenance.content(), **{key: row[key] for key in METADATA if key in row},
                         "format": "Multiple Choice"})
        else:
            raise QuantitativeAuthoringError("Unknown author variant.")
    return rows, compiled, failures
