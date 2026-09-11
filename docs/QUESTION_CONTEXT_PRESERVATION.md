# Preserve quiz subject and objective context

This extracts the deterministic context fixes from PR #7 onto the current main
branch. Goal titles, targets, focus, current level, question directives and topic
examples retain literal spacing, code indentation, Unicode, signs and musical
keys through app encoding, backend normalization and provider requests. Existing
transport/control cleanup and size/type bounds still apply. Optional skill-name
suggestions are omitted when distinct subject examples collide under the existing
skill identity rules; the full goal remains available to skill-map inference.

Optional candidate objective labels now reach the solver and final reviewer.
An inferred objective ID may have no definition in the supplied skill map, so
discarding its label previously removed the checker's only description of the
intended objective. Author keys, private feedback and numeric difficulty remain
hidden at their existing boundaries. Candidate correlation and all acceptance
gates remain unchanged.

Regression tests inspect literal input/output preservation, both native and
legacy provider request payloads, inference/evolution and generation/repair
paths, and objective correlation after solver filtering. They verify data flow
and admission rules; scripted replies do not establish model accuracy.

PR #7's shared source-use instructions and author/solver output-order changes
remain outside this extraction. The combined prompt candidate still needs fresh
full-workflow question-quality qualification. This change leaves every system
prompt, native schema, model/deployment setting and verification revision
unchanged, and performs no deployment.

The extracted backend passes all 1,042 unit tests under Python 3.12, with no
failures or skips, plus Ruff and compileall. A direct comparison with main
confirms that all 37 rendered prompt/configuration values match exactly across
the supported author variants, both feedback modes and six native schemas.
The three app regressions cover encoded requests, literal targets and topic
identity collisions. After integration with Saddle & Ink, the full signed iOS
simulator suite passed 1,031 tests with zero failures and one opt-in walkthrough
skipped. The Release simulator build and Xcode static analysis also passed.
SAM validation/build, all three packaged native SDK checks, deployment-script
tests and `git diff --check` passed. This validates the combined code and package,
without making a new claim about live model accuracy or physical-device behavior.
