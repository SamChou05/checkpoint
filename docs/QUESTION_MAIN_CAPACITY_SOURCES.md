# Fresh author explanation-capacity source packet

Prepared 2026-09-09 before author calls. The fixture is `backend/bedrock-question-service/evals/fixtures/question_main_capacity.json`. Its three exact goal/source packets are fresh; the broad subjects are not claimed to be previously unseen. Each packet requests two questions at minimum difficulty 3. There are no questions, choices, answer keys, worked examples or arm-specific limits in the fixture.

Only `cases[].payload` is generation input. The raw learner goal and source context must be identical between the two arms. `assessment_scope`, the top-level assessment contract and this document are assessor material, not provider input. This packet does not change runtime limits or prescribe the experiment's main-explanation limits.

## Sources and representation

All six linked pages were read through the web tool on 2026-09-09. Each supplied document identifies itself as an assistant-written selective summary and includes the real source URL. It is not a complete acquired page, a quote, or an independently retrieved evidence record. No source examples or diagrams were copied. `truncated: true` declares intentional abridgement; normalization preserves each supplied summary completely. Subject facts were checked against the sections below before author output existed.

| Goal | Primary instructional source | Checked scope |
| --- | --- | --- |
| SQL | [PostgreSQL 18: Table Expressions](https://www.postgresql.org/docs/18/queries-table-expressions.html) | Qualified joins, outer joins, ON versus WHERE, and the WHERE clause. Match multiplicity and NULL extension are distinct from later filtering. |
| SQL | [PostgreSQL 18: Comparison Functions and Operators](https://www.postgresql.org/docs/18/functions-comparison.html) | Ordinary scalar NULL comparisons, IS NULL, and IS NOT DISTINCT FROM. The versioned URL avoids silently following a future major release. |
| Music | [Open Music Theory: Intervals](https://pressbooks.nebraska.edu/openmusictheory/chapter/intervals/) | Size, quality, augmented/diminished intervals, intervallic inversion and enharmonic equivalence. University of Nebraska-hosted edition; chapter by Chelsey Hamm and Bryn Hughes. |
| Music | [LBCC: Melodic Analysis](https://lbcc.pressbooks.pub/intromtcls/chapter/chapter-8-melodic-analysis/) | Transposition—Changing Keys and How to Transpose Music, including accidentals. Introductory course text by Peter Knapp, Long Beach City College. |
| Photography | [Nikon: A Basic Look at the Basics of Exposure](https://www.nikonusa.com/learn-and-explore/c/tips-and-techniques/a-basic-look-at-the-basics-of-exposure) | Light, More or Less and Timing the Light; stop balance, shutter duration, ISO compensation and qualified noise tradeoffs. Article by Reed Hoffmann. |
| Photography | [Nikon: Understanding Maximum Aperture](https://www.nikonusa.com/learn-and-explore/c/tips-and-techniques/understanding-maximum-aperture) | Opening/f-number relationship, depth of field, shutter-speed tradeoff and maximum-aperture limits. |

The paraphrases include explicit scope qualifications, such as distinguishing logical SQL result semantics from physical execution order and interval inversion from other musical uses of “inversion.” These qualifications narrow the supplied rules; they are not verbatim statements attributed to a page. Music source pages license their instructional content under CC BY-SA 4.0 (Open Music Theory) and CC BY-NC-SA 4.0 (LBCC). No score image or audio is reproduced.

## Prospective assessment caveats

- SQL: inspect the exact rows, matches and constraints. Missing uniqueness declarations cannot be assumed. NULL matching, NULL extension and later filtering have different roles. No PostgreSQL runtime execution was performed during packet preparation.
- Music: independently check inclusive letter distance and pitch distance. Twelve-tone equal temperament is the goal's declared scope, not a claim about every tuning system. Register and direction must be specified when decisive; equivalence of sounding pitches does not establish equivalence of written names.
- Photography: use conventional full-stop arithmetic under stated steady conditions. Nominal f-number labels are rounded. Equal intended brightness does not mean equal collected light, blur, depth of field or noise. A finite equipment range and the requested creative constraints can eliminate otherwise equivalent exposures. These summaries do not support exact sensor-noise, flash, diffraction or universal motion-freezing claims.

The three subjects can support short application tasks with interacting constraints, but requesting level 3 does not establish that generated items attain it. A simple rule lookup remains too easy. Assess all choices and the complete main explanation, not merely agreement with the authored key. The small selected packet cannot establish arbitrary-subject reliability or learning gains.

## Validation and identity

On 2026-09-09, Python 3.12 called the repository's actual `request_contract._normalize_request` on all three payloads. All normalized successfully with `targetCount == 2` and `minimumDifficulty == 3`; each `sourceDocuments` list remained exactly equal to its input. Each goal has two sources, and every source is below 1,000 characters, well below the document/context limits. This was a local data-contract check, not a model-quality test.

File: 10,567 UTF-8 bytes. Byte SHA-256: `7f098d294fb2391a9eae57fb443c9ff00dc3c4539a0ebbef27cac38f5edac9ab`.

Canonical JSON uses sorted keys, separators `(',', ':')`, `ensure_ascii=False`, and UTF-8 without a trailing newline. Fixture canonical SHA-256: `8c5b6c6b2e1721bf48dedc6203c83a8762423649bdfb1f69cfef1164de389bf3`.

| Payload | Canonical bytes | Canonical SHA-256 |
| --- | ---: | --- |
| `sql_outer_join_null_reasoning` | 2,326 | `65eb78787ae6783a16ecf44076cbf843f2c72a5ad11017845ed842e17728a218` |
| `music_interval_transformations` | 2,488 | `7eba87436b0a525528bf1c06d91eb2de45b52edf3617a8306c411fd1801ae9e9` |
| `photography_exposure_tradeoffs` | 2,471 | `51fe04263487328f4150fc5e6ae5554fa9659224846eefb21c0898ff07c36a1b` |

| Supplied source text | UTF-8 bytes | Summary words, excluding label/URL | SHA-256 of exact text |
| --- | ---: | ---: | --- |
| PostgreSQL table expressions | 845 | 109 | `56f9ac42008ab8967c679411939006ba9c931b06f1e45f72fe85fb2f625ce4c2` |
| PostgreSQL comparisons | 676 | 78 | `2f61b7b5d25a8aee24bd6e28ebf3797ace43f5782132bcf2193c802f6296889e` |
| Open Music Theory intervals | 930 | 112 | `b8e0ebc6240fc32d15b108855fe3b21d91dd654043b85713b75897a4f907bf5a` |
| LBCC transposition | 737 | 87 | `8fcf34a56a9502c99f291f537bd5385f6dde80f4c0a9a005f0c04d72b8b82d1f` |
| Nikon exposure basics | 908 | 106 | `69a1bb7167cd32ef75d4e8baa3e44fa6caa9d65f49f55abd14ee1469bd6f731c` |
| Nikon aperture guidance | 766 | 88 | `c21b6f207c5e0e150df5ad04fa4b1f0ba845ea2dfd828e77d34173cec6a1fbfc` |
