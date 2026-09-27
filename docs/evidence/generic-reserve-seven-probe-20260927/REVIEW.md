# Exact-hash trial review

An independent read-only reviewer initially rejected the prelaunch plan at
SHA-256 `14210c0a82ebc3a6ff6b40bdfc0e9f4ce83898497a49bf8142bd661e70c82cf6`:
the machine gate could label five difficulty-1 rows ready for content review.
That unlaunched plan was preserved outside Git and cannot satisfy the current
review lock. No AWS call was made for it.

The corrected plan is frozen at SHA-256
`771538ec09d7e88d0e555020c20806d4b0a9bab40dfe58aea31631ee9ddae12d`;
its harness is frozen at
`251e3a100b55a51343f862f7ade012e73b90dfbd23c29bb05b1ba0c0e902e290`.
The independent reviewer checked source and wire pins, account/profile and
credential boundaries, seven original row identities, earliest-five survivor
selection, no retry/top-up, six durable call reservations, one SDK attempt per
call, 240-second deadline, capture redaction, and the corrected key,
choice, difficulty, policy, and completion gates. The reviewer gave **GO for
one bounded AWS trial only**. The parent agent independently ran the
socket-free preflight (10 tests, zero provider calls), checked these hashes,
and set the matching `review-approval.json` lock. A live worker result still
requires two locked answer-blind content reviews before qualification.
