# Independent structural and provenance audit

Reviewed the native author v3 → fixed-slot complete-choice solver v3 → default
reviewer v1 integration. No blocking deterministic admission or provenance defect
was found. This is a code and offline-test audit, not live semantic qualification.

- Four author slots map to the exact selected text. Solver slots are independently
  derived from the prompt and exact choice texts, without using the author's key
  or list position. Decoding restores trusted texts without accepting model echoes.
- Strict JSON, types, closed slot shapes, complete pair coverage and batch indexes
  are validated before admission. Duplicate or missing records fail the batch.
  Uncertain, equivalent, unsupported or mismatched answers cannot pass their
  corresponding gates. Remaining items and solver records receive matching dense
  indexes before final review.
- Policy 4 is assigned only after slot/pair checks and successful final review.
  Legacy complete-choice review retains policy 2; authored-teaching review retains
  policy 3. Caller stamps cannot promote a question. Stored policy 1–3 inventory
  is retired when a claim requires 4, without rewriting its content; a stale claim
  replay conflicts instead of acquiring a newer stamp.
- The final reviewer intentionally retains its existing choice ordering and
  receives the independent solver's judgments. Key-independent slot ordering is
  an independent-solver property, not a claim of a wholly blinded final reviewer.

Independent checks passed: 18 complete-choice pair/slot tests, 11 admission tests,
20 policy/inventory tests, and 6 goal/objective context tests (55 total). The two
context fixture files were updated to exercise native author v3 and solver v3;
legacy repair and authored solver v1 coverage remain intact. Ruff and
`git diff --check` passed for the fixture update.

The four-call slot trial still had incorrect semantic pair labels: the enforced
shape cannot make a model's declarations true. The six-domain plan with SHA-256
`0c25a18ee3da9fa9d1174e59e36a0be51db750a69578c377917b97497ab6c562`
was not dispatched and is superseded. This audit does not qualify that plan or
claim the current semantic candidate is ready for release. Any revised candidate
requires its own frozen trial and full-pipeline review.
