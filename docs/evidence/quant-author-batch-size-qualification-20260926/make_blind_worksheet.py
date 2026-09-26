"""One-shot, five-slot blind projection of a frozen numerical worker capture."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_hash(value):
    if re.fullmatch(r'[0-9a-f]{64}', value) is None:
        raise ValueError('Expected a lowercase SHA-256 digest')


def project(plan_path, capture_path, expected_plan_sha, expected_capture_sha, worksheet_path, private_path):
    check_hash(expected_plan_sha)
    check_hash(expected_capture_sha)
    if worksheet_path == private_path or worksheet_path.exists() or private_path.exists():
        raise RuntimeError('Blind outputs must be distinct and absent')
    if sha(plan_path) != expected_plan_sha or sha(capture_path) != expected_capture_sha:
        raise RuntimeError('Frozen input bytes differ from supplied digests')
    plan = json.loads(plan_path.read_bytes())
    capture = json.loads(capture_path.read_bytes())
    jobs = plan.get('jobs')
    if (plan.get('state') != 'frozen' or not isinstance(jobs, list) or len(jobs) != 1
            or jobs[0].get('id') != 'quantitative'
            or jobs[0].get('request', {}).get('targetCount') != 5):
        raise RuntimeError('Frozen five-slot numerical plan required')
    if (capture.get('plan_sha256') != expected_plan_sha or capture.get('plan') != plan
            or capture.get('status') not in ('completed_pending_review', 'globally_aborted')):
        raise RuntimeError('Capture differs from frozen plan or is not terminal')
    original_jobs = capture.get('original_jobs')
    if (not isinstance(original_jobs, list) or len(original_jobs) != 1
            or original_jobs[0].get('id') != 'quantitative'):
        raise RuntimeError('Original job slot ledger missing')
    slots = original_jobs[0].get('slots')
    if (not isinstance(slots, list) or len(slots) != 5
            or any(not isinstance(slot, dict) or slot.get('ordinal') != i for i, slot in enumerate(slots))):
        raise RuntimeError('Five original slots missing or reordered')
    observed_jobs = capture.get('jobs')
    if (not isinstance(observed_jobs, list) or len(observed_jobs) > 1
            or (observed_jobs and observed_jobs[0].get('id') != 'quantitative')):
        raise RuntimeError('Unexpected observed jobs')
    observed = observed_jobs[0] if observed_jobs else None
    returned = observed.get('returned') if observed else []
    if not isinstance(returned, list) or len(returned) > 5:
        raise RuntimeError('Invalid return cardinality')
    credited = bool(observed and observed.get('within_deadline') is True)
    expected_returned = sum(slot.get('status') == 'returned' for slot in slots)
    if expected_returned != (len(returned) if credited else 0):
        raise RuntimeError('Slot credit differs from returned rows')
    if any((slot.get('status') == 'returned') != (credited and i < len(returned))
           for i, slot in enumerate(slots)):
        raise RuntimeError('Returned slots are not the original prefix')
    items, mapping = [], {}
    for i, slot in enumerate(slots):
        opaque_id = secrets.token_hex(12)
        while opaque_id in mapping:
            opaque_id = secrets.token_hex(12)
        row = returned[i] if credited and i < len(returned) else None
        item = {'id': opaque_id, 'requested_slot': True}
        rotation = None
        if (isinstance(row, dict) and isinstance(row.get('prompt'), str) and row['prompt'].strip()
                and isinstance(row.get('choices'), list) and len(row['choices']) == 4
                and all(isinstance(choice, str) for choice in row['choices'])):
            offset = secrets.randbelow(4)
            rotation = list(range(offset, 4)) + list(range(offset))
            item['stem'] = row['prompt']
            item['choices'] = {letter: row['choices'][position]
                               for letter, position in zip('ABCD', rotation, strict=True)}
        else:
            item['unavailable'] = True
        mapping[opaque_id] = {'job_id': 'quantitative', 'original_slot_ordinal': i,
                              'returned_row_index': i if row is not None else None,
                              'display_to_source_choice_index': rotation,
                              'captured_slot_status': slot.get('status')}
        items.append(item)
    secrets.SystemRandom().shuffle(items)
    worksheet = {'version': 1, 'plan_sha256': expected_plan_sha,
                 'capture_sha256': expected_capture_sha, 'items': items}
    assert len(items) == 5 and sum(item['requested_slot'] for item in items) == 5
    assert set(mapping) == {item['id'] for item in items}
    forbidden = {'expectedAnswer', 'correctChoice', 'explanation', 'provenance', 'returned_sources', 'returned_provenance'}
    assert not any(field in forbidden for item in items for field in item)
    for item in items:
        source = mapping[item['id']]
        idx = source['returned_row_index']
        if 'unavailable' in item:
            assert item == {'id': item['id'], 'requested_slot': True, 'unavailable': True}
            assert source['display_to_source_choice_index'] is None
        else:
            row = returned[idx]
            assert item['stem'] == row['prompt']
            assert list(item['choices']) == list('ABCD')
            assert list(item['choices'].values()) == [row['choices'][j] for j in source['display_to_source_choice_index']]
    if sha(plan_path) != expected_plan_sha or sha(capture_path) != expected_capture_sha:
        raise RuntimeError('Inputs changed during projection')
    worksheet_bytes = (json.dumps(worksheet, ensure_ascii=True, indent=2, allow_nan=False) + '\n').encode()
    private = {'version': 1, 'plan_sha256': expected_plan_sha,
               'capture_sha256': expected_capture_sha,
               'worksheet_sha256': hashlib.sha256(worksheet_bytes).hexdigest(), 'mapping': mapping}
    private_bytes = (json.dumps(private, ensure_ascii=True, indent=2, allow_nan=False) + '\n').encode()
    with os.fdopen(os.open(worksheet_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as stream:
        stream.write(worksheet_bytes)
        stream.flush()
        os.fsync(stream.fileno())
    with os.fdopen(os.open(private_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as stream:
        stream.write(private_bytes)
        stream.flush()
        os.fsync(stream.fileno())
    if sha(plan_path) != expected_plan_sha or sha(capture_path) != expected_capture_sha:
        raise RuntimeError('Inputs changed after projection')
    return {'worksheet_sha256': sha(worksheet_path), 'private_map_sha256': sha(private_path),
            'available': sum('stem' in item for item in items), 'original_slots': len(items)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', required=True, type=Path)
    parser.add_argument('--capture', required=True, type=Path)
    parser.add_argument('--plan-sha256', required=True)
    parser.add_argument('--capture-sha256', required=True)
    parser.add_argument('--worksheet', required=True, type=Path)
    parser.add_argument('--private-map', required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(project(args.plan, args.capture, args.plan_sha256,
                             args.capture_sha256, args.worksheet, args.private_map)))


if __name__ == '__main__':
    main()
