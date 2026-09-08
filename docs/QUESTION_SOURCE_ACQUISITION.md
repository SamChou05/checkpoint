# Inspectable public-source acquisition

September 8, 2026. The evidence path needs actual retrieved text rather than
model-written summaries or quotations. `source_acquisition.py` adds a bounded
public HTTPS fetcher. It is not wired into production generation in this milestone.

Each successful capture records the requested and final URL, fragment, redirect
trace, retrieval time, MIME type and decoding choice, body and extracted-text
hashes, exact retained text, and explicit truncation/representation limitations.
HTML extraction preserves text nodes and inserts block/table separators; it
does not reproduce browser layout, generated content, media or CSS visibility.
Plain-text decoding preserves meaningful whitespace. Neither capture success
nor a hash establishes source authority or factual correctness.

Requests use HTTPS on port 443. Every destination and redirect must resolve only
to public addresses; the connection pins a validated address while TLS checks
the requested hostname. The fetcher sends no cookies, authentication or arbitrary
caller headers, follows at most four redirects, accepts only identity-encoded
HTML/XHTML/plain text, and bounds each body to 1 MiB. Extraction retains at most
120,000 characters and marks omissions. Failed or partial retrieval produces no
usable evidence text.

Connect/TLS/reads share a 30-second I/O budget with a ten-second per-operation
ceiling. Blocking platform DNS is **not** interruptible by this adapter: an
overdue return fails before connecting. Extraction and local persistence also
have no hard wall-time guarantee. A worker integration must account for this
limitation; it cannot claim a hard end-to-end deadline from these settings.

`evals/checkpoint_source_capture.py` records up to five explicitly selected URLs,
the implementation hash and prospective bounds, writing each dispatch before
fetching. File and directory synchronization precede the next action. It never
overwrites an earlier capture, retries, resumes an interrupted capture, invokes
a model or certifies a question. Full captures stay local unless redistribution
of the source material is permitted.

## Initial live qualification, declared before capture

Fetch each of these four URLs once with the defaults, preserve failures and
truncation, and inspect the resulting text. No replacement URL or larger allowance
will be substituted inside this run:

- [W3C dated CSS Grid draft](https://www.w3.org/TR/2025/CRD-css-grid-1-20250326/#auto-placement-algo): a large versioned technical document and fragment.
- [CPython 3.14 control-flow reference source](https://raw.githubusercontent.com/python/cpython/v3.14.0/Doc/tutorial/controlflow.rst): plain text containing code and indentation.
- [National Archives Declaration transcription](https://www.archives.gov/founding-docs/declaration-transcript): a historical document within a navigation-heavy page.
- [NASA Space Place seasons explanation](https://spaceplace.nasa.gov/seasons/en/): explanatory science HTML with images not represented by extraction.

These caller-selected references test acquisition across representations and
subjects. They do not measure automatic source discovery, source-selection
quality, question correctness, difficulty, production throughput or learning.
Subsequent model evaluations must bind exact selected spans and all teaching
fields to the capture, preserve omissions, and assess factual results separately
from citation integrity.

## Observed results and a general parser fix

The first four-source capture completed with three acquired documents and one
extraction failure. CPython retained 41,300 characters, the Archives page 14,854,
and NASA 5,782. None was truncated. The CPython decoded UTF-8 text hashes to the
same value as the response body, preserving its literal whitespace. Individual
fetches took approximately 0.29–0.41 seconds in this small run; this is not a
latency guarantee. [Capture summary](evidence/public-source-acquisition-20260908.json)
retains all four outcomes and the hash/location of the full local capture.

The W3C failure exposed a general HTML handling bug: HTML permits an omitted
closing head tag, but the text parser kept treating the subsequent body as head
content. One separately recorded diagnostic fetch returned the exact same
957,488-byte body hash as the failed capture. It was the specification itself,
not an access challenge. The fix recognizes ordinary body boundaries while
continuing to omit nested inert content; no domain-specific branch was added.

Offline reprocessing of those same bytes with the fixed parser now retains
120,000 characters and correctly marks the extraction truncated. This is a
reparse, **not** another successful live fetch or a replacement for the original
failure. [Reparse record](evidence/public-source-head-reparse-20260908.json).
The 19 focused source tests and four capture tests pass. The earlier full backend
run passed 811 tests with one existing optional-runtime skip before this two-test
HTML fix. Production generation remains unchanged.
