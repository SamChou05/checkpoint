# Exact-hash review for trial 02

Trial 01 stopped locally after one reservation and **before** Bedrock dispatch:
its per-call pin check rebuilt an offline plan while the live author stage was
patched. [Its immutable capture and postmortem](../generic-reserve-seven-probe-20260927/RESULTS.md)
remain terminal. Trial 02 has a new ID and separate plan/capture paths.

The successor plan SHA-256 is
`6effccce724caaf54285b171d4152c5e6d3162a86d1c492c47a4ec215350013e`;
the harness SHA-256 is
`015e40566d0c6fb65dd36c21ecd5cee97a70d4ba895d7526a8150596c7037ca0`.
An independent read-only reviewer checked those exact bytes, the unchanged
request and author wire, and the new static `production_pin_callback`. A
socket-free regression uses that same callback and real boto3 client metadata
with Converse replaced locally; it completes author, solver, and reviewer in
three fake calls and returns the earliest five rows. The reviewer also checked
the unchanged credential, capture, deadline, six-reservation, key, choice,
difficulty, and fail-closed gates and gave **GO for one trial 02 AWS execution
only**. Root independently reran the 11-test socket-free preflight with zero
provider calls and set the matching `review-approval.json` lock. The result
still needs two locked answer-blind content reviews to qualify.
