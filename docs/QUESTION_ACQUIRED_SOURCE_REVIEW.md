# Immutable review against acquired references

September 8, 2026. The eval-only `acquired_source_review.py` adapter supplies
captured reference spans to the existing immutable teaching-item audit. It checks
the unchanged stem, choices, main explanation and all four choice explanations.
It does not fetch sources, generate questions, rewrite feedback, stamp inventory
or alter the historical audit contract.

Only successful caller-owned acquisition records with matching text hashes,
lengths and consistent completeness metadata are usable. Explicit selections
retain their exact text and original offsets; at most five records, twelve spans
and 24,000 selected characters are admitted without clipping. Every source's
retrieval, truncation, extraction and omission metadata remains visible. Old
context summaries are excluded from this protocol. Hashes correlate recorded
inputs; they do not authenticate a caller's fabricated acquisition record.

The model returns the existing immutable verdict plus citations for the item,
main explanation and each exact choice's feedback. A citation contains only a
source ID and verbatim quotation. The application requires one unique exact
occurrence in the supplied span and derives character offsets itself, including
the corresponding original-document offsets. It rejects fabricated, ambiguous,
duplicate or out-of-span quotations; no fuzzy matching or model-counted offsets
are used. Missing citation coverage prevents approval. Valid citations cannot
override an uncertain, unsupported, invalid, wrong-key or insufficient-difficulty
verdict. Learner-facing content is unchanged apart from the existing independently
assessed difficulty field.

These are citation-integrity and declared-verdict checks, **not semantic proof**.
An irrelevant exact quotation can still accompany a confidently wrong model
verdict. A test explicitly preserves that limitation. Evidence of omission is
not evidence that an exception does not exist in the source. Full explanations
can reveal the intended answer, so this audit is not answer-blind.

All twelve focused tests pass, including Unicode/overlapping occurrences,
capture mutation, failed retrieval, omission metadata, required field coverage,
unchanged content and existing vetoes. Ruff, whitespace and independent code
review pass. Live factual performance remains unqualified at this milestone;
the caller still must bind every response to its exact frozen request and
independently assess model judgments across fresh learning goals.
