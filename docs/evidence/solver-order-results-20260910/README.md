# September 10 solver-order evidence

See [the results report](../../QUESTION_SOLVER_ORDER_RESULTS.md) and the frozen
[protocol](../../QUESTION_SOLVER_ORDER_PROTOCOL.md). This is one partially
completed fixed diagnostic, not a second plan or a replacement execution.

- `capture.json`: byte-for-byte copy of the original terminal capture; 27
  completed responses, one dispatched timeout with unknown remote completion
  and usage, four unattempted requests. All local workers were cleaned up.
- `replay.py`: offline reproduction using the source-bound provider adapter,
  request builder and validators; networking is forbidden while replaying.
- `mechanical-results.json`, `mapping.json`: exact recorded verdict/gate counts
  and identity mapping, including unavailable slots.
- `rationale-packet-{a,b}.json`: opaque IDs, exact subjects and reasons, with
  arm/repeat/key/declared verdicts hidden; presentation order normalized.
- `judgments-{a,b}.json`: declared verdicts withheld until each assessor saved
  its rationale assessment.
- `rationale-assessment-{a,b}.json`, `consistency-assessment-{a,b}.json`: original
  independent assistant assessments, retained unchanged. Assessor A reviewed 36
  responses, B reviewed 37. Reasons were assessed before verdicts were revealed.
- `join_assessments.py`, `assessed-results.json`: coverage/identity-checked join
  of frozen assessments with arm labels, including input byte hashes, reading
  disagreements, ambiguous cases and paired/subject denominators.

Reproduce using the exact source snapshot bound by the capture and Python
3.12.11 with boto3/botocore 1.43.91. The verified local runtime and checkout are:

```sh
/tmp/checkpoint-native-qualification-venv/bin/python \
  docs/evidence/solver-order-results-20260910/replay.py \
  --checkout /tmp/checkpoint-goal-context-preservation-20260910 \
  --capture docs/evidence/solver-order-results-20260910/capture.json \
  --directory /tmp/new-solver-order-offline-replay

/tmp/checkpoint-native-qualification-venv/bin/python \
  docs/evidence/solver-order-results-20260910/join_assessments.py \
  --directory docs/evidence/solver-order-results-20260910 \
  --output /tmp/new-solver-order-assessment-join.json
```

Use fresh output paths; scripts refuse overwriting. Compare the rebuilt
mechanical results, mapping, packets and assessment join against this archive.
The replay checks source and plan identity before adapting any response. New
production prompt changes require the historical checkout for reproduction;
never weaken that guard or relabel these responses as output of later source.

No AWS credentials are needed for either script. Nothing here authorizes
restarting the paid trial or bypassing its original execution claim. The
unobserved timeout usage is not estimated as zero. Results contain synthetic
evaluation subjects, not learner activity or production data.
