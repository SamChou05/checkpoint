import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('projection', Path(__file__).with_name('make_blind_worksheet.py'))
p = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p)


def write(path, obj):
    path.write_text(json.dumps(obj, indent=2) + '\n')
    return hashlib.sha256(path.read_bytes()).hexdigest()


class ProjectionTests(unittest.TestCase):
    def fixture(self, directory, count=3):
        plan = {'state': 'frozen', 'jobs': [{'id': 'quantitative', 'request': {'targetCount': 5}}]}
        plan_path = directory / 'plan.json'
        ph = write(plan_path, plan)
        rows = [{'prompt': f'Solve {i}+1.', 'choices': [f'{i}.{j}' for j in range(4)],
                 'expectedAnswer': '0', 'explanation': 'secret teaching',
                 'returned_provenance': 'secret provenance'} for i in range(count)]
        capture = {'plan': plan, 'plan_sha256': ph, 'status': 'completed_pending_review',
                   'original_jobs': [{'id': 'quantitative', 'slots': [
                       {'ordinal': i, 'status': 'returned' if i < count else 'unfilled'} for i in range(5)]}],
                   'jobs': [{'id': 'quantitative', 'returned': rows, 'within_deadline': True}]}
        cap_path = directory / 'capture.json'
        ch = write(cap_path, capture)
        return plan_path, cap_path, ph, ch

    def test_five_slots_shuffled_rotated_keyless_and_exclusive(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            plan, capture, ph, ch = self.fixture(directory)
            worksheet, private = directory / 'worksheet.json', directory / 'private.json'
            result = p.project(plan, capture, ph, ch, worksheet, private)
            items = json.loads(worksheet.read_text())['items']
            mapping = json.loads(private.read_text())['mapping']
            source = json.loads(capture.read_text())['jobs'][0]['returned']
            self.assertEqual((result['original_slots'], result['available']), (5, 3))
            self.assertEqual(len(items), 5)
            self.assertEqual(sum('unavailable' in x for x in items), 2)
            self.assertEqual(set(mapping), {x['id'] for x in items})
            for item in items:
                self.assertEqual(len(item['id']), 24)
                self.assertNotIn('expectedAnswer', item)
                self.assertNotIn('explanation', item)
                self.assertNotIn('provenance', item)
                meta = mapping[item['id']]
                if 'choices' in item:
                    row = source[meta['returned_row_index']]
                    self.assertEqual(item['stem'], row['prompt'])
                    self.assertEqual(list(item['choices'].values()),
                                     [row['choices'][i] for i in meta['display_to_source_choice_index']])
                else:
                    self.assertTrue(item['unavailable'])
            with self.assertRaises(RuntimeError):
                p.project(plan, capture, ph, ch, worksheet, private)

    def test_terminal_abort_preserves_five_unavailable_slots(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            plan, capture, ph, _ = self.fixture(directory, 0)
            obj = json.loads(capture.read_text())
            obj['status'] = 'globally_aborted'
            obj['jobs'] = []
            obj['original_jobs'][0]['slots'] = [{'ordinal': i, 'status': 'unattempted'} for i in range(5)]
            ch = write(capture, obj)
            result = p.project(plan, capture, ph, ch, directory / 'w.json', directory / 'm.json')
            self.assertEqual(result['available'], 0)
            self.assertEqual(len(json.loads((directory / 'w.json').read_text())['items']), 5)

    def test_wrong_hash_and_bad_ledger_fail_before_outputs(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            plan, capture, ph, ch = self.fixture(directory)
            worksheet, private = directory / 'w.json', directory / 'm.json'
            with self.assertRaises(RuntimeError):
                p.project(plan, capture, ph, '0'*64, worksheet, private)
            obj = json.loads(capture.read_text())
            obj['original_jobs'][0]['slots'][0]['status'] = 'unfilled'
            ch = write(capture, obj)
            with self.assertRaises(RuntimeError):
                p.project(plan, capture, ph, ch, worksheet, private)
            self.assertFalse(worksheet.exists())
            self.assertFalse(private.exists())

if __name__ == '__main__':
    unittest.main()
