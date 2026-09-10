Operational audit passed. Frozen plan `bbebe7e13927aa06bc701bb3745ecc0d5beffea2c75d4b3f07261a9ccf090114` and capture `0809bf2fe0e6b2e071845e487e008c6af2eb119d32311237bca3d58e746536e2` reconstruct exactly without provider clients. All 33 source hashes match committed and current bytes. All 29 calls completed with known usage, confirmed cleanup, exit 0 and no termination.

| Operation | Arm | Calls | Returns / 5 | Result |
|---|---|---:|---:|---|
| excel_reference_copy_constraints | reviewer_written | 6 | 3 | partial_delivery |
| excel_reference_copy_constraints | authored_solution | 5 | 3 | partial_delivery |
| map_scale_distance_resizing | authored_solution | 4 | 0 | call_budget_exhausted |
| map_scale_distance_resizing | reviewer_written | 4 | 0 | call_budget_exhausted |
| food_web_energy_constraints | reviewer_written | 5 | 1 | partial_delivery |
| food_web_energy_constraints | authored_solution | 5 | 0 | no_returned_questions |

Calls: 29/36. Input bytes: 296,063/1,179,648. Known usage: 60,976 input and 33,507 output tokens. Raw author occurrences: 62; returned items: 7/30. These are operational and coverage observations; no semantic assessment was performed.

Exact replay preserves normal content failures and later-operation continuation. Original capture bytes remain unchanged. Detailed call timing, role sequences, parse counts, rejection metrics, hashes and limitations are in `/tmp/checkpoint-delivery-operational-audit-20260909.json`.

Role-specific JSON front ends reject 7 completed responses (zero-based call indexes [5, 7, 14, 16, 18, 20, 28]); all 13 author responses parse, containing 62 raw author occurrences. Role schema failures are additional and remain visible in the runtime rejection metrics.
