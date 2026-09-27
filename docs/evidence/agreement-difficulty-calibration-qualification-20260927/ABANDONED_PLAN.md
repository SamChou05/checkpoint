# Superseded prelaunch plan

Commit `97ad6e4` froze plan SHA-256
`a1e44176da5327e2de5f4d1a723e01c80b71dbc77cab4ed96b6479c5802dc707`
with harness SHA-256
`824c090c948ab85127a658e566c938029efed60e257656aac0c317aff44334dd`.
Independent audit marked that plan **NO-GO before any AWS call**. Its prose did
not explicitly account for the execute-time STS identity request, and its
240-second clock started after credential export and execute-time STS. The
old `plan.json` is retained in Git history only; a new hash-pinned plan must
replace it after repairing and re-reviewing the harness. The old plan never
produced a launch precheck or provider capture.

Commit `bdaee5e` froze a repaired plan SHA-256
`7034909ec25b359668bda75946656d31ca3a3c4b76cea93d72fa1c314cb44f56`.
Before launch, a further boundary audit found that rounding elapsed time to
six decimals before comparing it with 240 seconds could credit a tiny
overrun. This second plan is also superseded in Git history, with **no AWS
call or capture**. The next plan compares the raw monotonic duration to the
limit and rounds only the displayed metric.
