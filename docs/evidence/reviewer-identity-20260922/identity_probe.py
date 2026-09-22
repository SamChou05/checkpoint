"""Two-call inactive outer-identity feasibility trial; explicit execution only."""

import argparse
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import time

import boto3
import botocore
from botocore.config import Config

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location("frozen_reviewer_identity", HERE / "candidate_reviewer_slots.py")
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)
PLAN_PATH = HERE / "plan.json"
PLAN_SHA = "79d4e8cdf39c7378573081e7eacadd086d128d2b98eb97d346c6264c4eb4fdc4"
MANIFEST = HERE / "execution-v2.json"
CAPTURE = HERE / "capture.json"


def sha(value):
    return hashlib.sha256(value).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False).encode()


def save(path, value, *, exclusive=False):
    text = json.dumps(value, indent=2, ensure_ascii=False) + "\n"
    if exclusive:
        with path.open("x") as stream:
            stream.write(text)
    else:
        temporary = path.with_suffix(".partial")
        temporary.write_text(text)
        temporary.replace(path)


def dependencies():
    return {"python": sys.version.split()[0], "boto3": boto3.__version__, "botocore": botocore.__version__}


def hashes(paths):
    return {path: sha((ROOT / path).read_bytes()) for path in paths}


def load_plan():
    raw = PLAN_PATH.read_bytes()
    if sha(raw) != PLAN_SHA:
        raise RuntimeError("Prospective plan changed.")
    plan = json.loads(raw)
    if hashes(plan["source_sha256"]) != plan["source_sha256"] or dependencies() != plan["dependencies"]:
        raise RuntimeError("Planned source or dependencies changed.")
    if candidate.metadata(5) != plan["contract"]:
        raise RuntimeError("Candidate grammar changed.")
    source = plan["source_capture"]
    if sha((ROOT / source["path"]).read_bytes()) != source["sha256"]:
        raise RuntimeError("Prior evidence changed.")
    if len(plan["calls"]) != 2:
        raise RuntimeError("Expected exactly two calls.")
    prior = json.loads((ROOT / source["path"]).read_text())
    for sequence, call in enumerate(plan["calls"]):
        request = call["provider_request"]
        if call["sequence"] != sequence or call["trusted_count"] != 5 or sha(canonical(request)) != call["request_sha256"]:
            raise RuntimeError("Frozen request changed.")
        expected = copy.deepcopy(prior["calls"][call["source_review_call_index"]]["request"])
        expected["outputConfig"] = candidate.output_config(5)
        expected["system"][0]["text"] += "\n\n" + candidate.prompt_override(5)
        if request != expected:
            raise RuntimeError("Request delta exceeds identity transport.")
    return plan


def prepare():
    plan = load_plan()
    paths = [*plan["source_sha256"], str(Path(__file__).relative_to(ROOT))]
    manifest = {
        "plan_sha256": PLAN_SHA, "created_at": datetime.now(timezone.utc).isoformat(),
        "source_sha256": hashes(paths), "dependencies": dependencies(),
        "maximum_calls": 2, "sdk_total_max_attempts": 1,
        "read_timeout_seconds": 75, "connect_timeout_seconds": 3, "region": "us-east-1",
        "first_schema_compilation": "Inside the same75s transport ceiling; no warmup, retry, timeout increase or replacement call.",
        "capture_redaction": "Remove complete reasoningContent blocks and their signatures before persistence; record the count. Plain JSON answer blocks and all other response metadata remain unchanged. The complete response exists only in memory for validation.",
        "scoring": "Separate structural identity feasibility from semantic control judgments. A transport/schema failure is a structural failure; a wrong key, false rejection, bad feedback or ambiguous acceptance is a semantic/admission failure. Neither rewrites the other result. No production promotion.",
    }
    save(MANIFEST, manifest, exclusive=True)
    print(json.dumps({"plan_sha256": PLAN_SHA, "execution_manifest_sha256": sha(MANIFEST.read_bytes())}))


def preflight(expected_hash):
    raw = MANIFEST.read_bytes()
    manifest = json.loads(raw)
    if sha(raw) != expected_hash or manifest["plan_sha256"] != PLAN_SHA:
        raise RuntimeError("Execution manifest changed.")
    if hashes(manifest["source_sha256"]) != manifest["source_sha256"] or manifest["dependencies"] != dependencies():
        raise RuntimeError("Execution source or dependencies changed.")
    return load_plan(), manifest


def assess(response, call, plan):
    text = ''.join(block['text'] for block in response['output']['message']['content'] if 'text' in block)
    decoded = json.loads(candidate.adapt(text, call['trusted_count']))
    # The candidate's closed-object validation establishes complete unique IDs.
    # Retain explicit assertions and never silently remap/discard an unbound row.
    if [row['index'] for row in decoded['reviews']] != list(range(5)):
        raise ValueError("Adapter identity mismatch.")
    raw_payload = json.loads(text)
    user_text = call['provider_request']['messages'][0]['content'][0]['text']
    supplied = json.loads(user_text.split('<question_review_json>\n', 1)[1].split('\n</question_review_json>', 1)[0])['items']
    gold = {row['item_index']: row for row in plan['gold_items'] if row['sequence'] == call['sequence']}
    items = []
    for row, offered in zip(decoded['reviews'], supplied, strict=True):
        index = row['index']
        raw_row = raw_payload['reviews'][str(index)]
        valid = row['valid'] is True
        result = {'index': index, 'valid': valid, 'expected_valid': gold[index]['expected_valid'],
                  'validity_agreement': valid == gold[index]['expected_valid'], 'semantic_audit': 'pending'}
        if valid:
            # The same exact bytes must survive adaptation, even if a later gate
            # rejects their contents. These checks do not assert semantic truth.
            if row['answer'] != raw_row['answer'] or row['explanation'] != raw_row['explanation']:
                raise ValueError("Adapter changed exact text.")
            if row['choiceExplanations'] != {entry['choice']: entry['explanation'] for entry in raw_row['choiceFeedback']}:
                raise ValueError("Adapter changed feedback bytes.")
            feedback = row['choiceExplanations']
            bounds = 12 <= len(row['explanation'].strip()) <= 420 and len(row['explanation']) <= 420 and all(
                12 <= len(value.strip()) <= 280 and len(value) <= 280 for value in feedback.values())
            labels = any(re.search(r'\b(?:choice|option|answer)\s+[A-D]\b', value, re.I)
                         for value in [row['explanation'], *feedback.values()])
            result.update(exact_author_key=row['answer'] == gold[index]['author_key'],
                          exact_feedback_coverage=set(feedback) == set(offered['choices']),
                          exact_bytes_preserved=True, feedback_bounds=bounds,
                          difficulty=row['difficulty'], difficulty_requested_range=2 <= row['difficulty'] <= 3,
                          original_answer_letter_predicate=labels)
        else:
            if row != {'index': index, 'valid': False}:
                raise ValueError("Negative row surfaced unused content.")
        items.append(result)
    return {'structural_identity_pass': True, 'adapted_response': decoded, 'items': items}


def capture_response(response):
    """Persist visible output and usage only, without adaptive reasoning traces."""
    sanitized = copy.deepcopy(response)
    message = sanitized.get('output', {}).get('message', {})
    blocks = message.get('content', [])
    count = sum('reasoningContent' in block for block in blocks)
    if 'content' in message:
        message['content'] = [block for block in blocks if 'reasoningContent' not in block]
    return sanitized, count


def run(client, plan, capture, path):
    for call in plan['calls']:
        if len(capture['calls']) >= 2:
            raise RuntimeError("Two-call ceiling reached.")
        row = {'sequence': call['sequence'], 'source_review_call_index': call['source_review_call_index'],
               'request': copy.deepcopy(call['provider_request']), 'request_sha256': call['request_sha256'],
               'started_at': datetime.now(timezone.utc).isoformat(), 'dispatch_attempted': True}
        capture['calls'].append(row)
        save(path, capture)
        start = time.monotonic()
        try:
            response = client.converse(**copy.deepcopy(call['provider_request']))
        except Exception as error:
            row['error_type'] = type(error).__name__
            capture['stop_reason'] = 'transport_failure'
        else:
            row['response'], row['reasoning_content_block_count'] = capture_response(response)
            if response.get('stopReason') != 'end_turn':
                capture['stop_reason'] = 'non_end_turn'
            else:
                try:
                    row['assessment'] = assess(response, call, plan)
                except Exception as error:
                    row['validation_error_type'] = type(error).__name__
                    capture['stop_reason'] = 'structure_or_mapping_failure'
        finally:
            row['elapsed_seconds'] = round(time.monotonic() - start, 3)
            save(path, capture)
        if 'stop_reason' in capture:
            break
    capture['status'] = 'stopped_after_failure' if 'stop_reason' in capture else 'dispatch_complete_pending_semantic_audit'
    capture['finished_at'] = datetime.now(timezone.utc).isoformat()
    save(path, capture)


def execute(expected_hash):
    plan, manifest = preflight(expected_hash)
    capture = {'plan_sha256': PLAN_SHA, 'execution_manifest_sha256': expected_hash,
               'started_at': datetime.now(timezone.utc).isoformat(), 'calls': [], 'status': 'preflight'}
    save(CAPTURE, capture, exclusive=True)
    credentials = json.loads(subprocess.check_output(['aws', 'configure', 'export-credentials', '--format', 'process'], stderr=subprocess.DEVNULL))
    client = boto3.client('bedrock-runtime', region_name=manifest['region'],
                         aws_access_key_id=credentials['AccessKeyId'], aws_secret_access_key=credentials['SecretAccessKey'],
                         aws_session_token=credentials.get('SessionToken'),
                         config=Config(connect_timeout=3, read_timeout=75, retries={'total_max_attempts': 1}))
    del credentials
    capture['status'] = 'running'
    run(client, plan, capture, CAPTURE)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument('--prepare', action='store_true')
    actions.add_argument('--check', metavar='MANIFEST_SHA256')
    actions.add_argument('--execute', metavar='MANIFEST_SHA256')
    args = parser.parse_args()
    if args.prepare:
        prepare()
    elif args.check:
        preflight(args.check)
        print('Frozen preflight passed; no provider call.')
    else:
        execute(args.execute)
