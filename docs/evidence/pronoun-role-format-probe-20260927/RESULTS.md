# Pronoun role-map format: two blind-reviewed candidates

The [keyless worksheet](worksheet.json), SHA-256
`8dc06af7d3581cae627fe2570b8b186b7b7b8609bfb6309df45a8434e5d96685`,
contains two proposed standard-English formats that ask learners to map
quoted first- and second-person pronouns to named speakers, addressees,
actions, and owners. PR-01 keeps one speaker across two proposed actions;
PR-02 changes speakers between turns and requires resetting the reference of
“my.” The intended keys and proofs stayed outside Git in a mode-600 private
map until both independent reviews were locked.

[Reviewer A](review-a.json) (SHA-256
`e605b41115c24da8a42d878ddc03333a8b6ef32a3a55a3659e4f80a2c0554f52`)
and [reviewer B](review-b.json) (SHA-256
`4fddb93d14c11dcd081ddd5494b766061f87547bc4b48a32cd1510263587c4f5`)
both independently selected **PR-01 B** and **PR-02 C**, matching the private
map, with no second defensible answer. Both rated PR-01 difficulty **3/5** and
PR-02 **2/5** and found **all 12/12** within-item choice pairs materially
different role claims. They found no unsupported completed-action inference:
the dialogue states a plan or offer, not that the actions happened.

Both reviewers judged the one-speaker and speaker-shift mechanisms different
enough to coexist in a small mixed bank, while warning that many role-map
questions with the same four-choice presentation would become formulaic.
This is a successful **offline idea probe**, not a compiled task family, live
author acceptance, five-question worker result, or repeated-bank qualification.
The current mapped provider contract still supports only agreement scenes;
adding pronoun reference needs a new closed task contract, compiler, private
proof/provenance, schema and prompt acceptance, and new bank review.
