# Count-five outer identity trial

**Structural identity passed 2/2; semantic qualification failed.** Both responses
returned exactly the five required object keys. The adapter restored indexes 0–4
without dropping, filling, or repairing rows. All positive answer and feedback
bytes survived unchanged. The same original inputs previously produced the
schema-valid but unusable v1 envelopes `[-1,-1]` and `[-1,0,1,2,3,4]`.

Exactly two calls ran, taking 61.837 and 48.586 seconds within the 75-second read
limit. There were no warmups, retries, timeout increases or replacements. One
adaptive reasoning block per call was excluded from the saved capture, including
signatures. This tests the count-five grammar only; the first latency does not
isolate grammar compilation from inference or network time.

All eight unambiguous valid controls were retained. Both predeclared ambiguous
controls were incorrectly accepted under the frozen criterion: the bus question
omits "minimum", so both 25 and 26 rides make the pass cheaper; the concrete
question does not specify whether its parts are mass or volume. The intended
answers remain arithmetically correct under their extra interpretations.

The fruit-punch feedback still incorrectly says multiplying nine by three
inverts the 5:3 ratio. The inverse factor is 3/5, which would yield 5.4, not 27.
The soup feedback additionally calls unspecified ounces a volume, a unit-label
uncertainty recorded separately from definite arithmetic errors. There are six
complete-content passes under the frozen uncertainty-fails rule, or seven if
that unit wording is read favorably; neither interpretation changes failure.

All ten responses have exact feedback coverage, bounded feedback, matching author
keys, and difficulty 2–3. Those structural declarations do not establish unique
correctness or sound teaching. `audit.json` preserves every item-level judgment.

This supports integrating an outer identity contract while retaining all local
checks. It does not qualify the semantic pipeline, every possible batch count,
or deployment. Existing v1/v2 schemas and production routing were not changed by
this experiment. The closed outer contract deliberately leaves choice-feedback
identity and free answer text to existing local checks.

Capture SHA-256: `e5abb909fc2eddf2dd99af59ba743b16fb8776f24f4fbcde6917767c032df523`.
