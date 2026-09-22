# Known-control field expectations — draft review

The new source-bound draft is `known-control-field-expectations-draft.json` (SHA-256 `c86996a0720fe44ba999ee6bd938c3768829fd5f966da6c836ca92677569bce3`). It annotates the exact 24 learner payloads from the frozen `adversarial-plan.json`; their 12 accept and 12 reject decisions remain unchanged. This document authorizes no provider calls and freezes no new trial.

All 24 complete learner-content hashes and all 120 feedback-field hashes match the original evidence. The draft includes original case hashes, unchanged source gold, exact feedback text and field hashes, separate task/answer/teaching judgments, and every original choice-pair judgment. Existing captures, plans, reviews and gold packets were read without modification.

The draft expects 16 supported and 8 unsupported tasks. Its 120 teaching-field judgments are 94 supported, 24 unsupported and 2 uncertain. Of the 144 task-relative choice pairs, 139 are distinct and 5 equivalent. The primary proposed future criterion is all 24 original admission decisions correct with byte-identical accepted content. Task, answer, field-label and private-reason accuracy should be reported separately, so an accidental veto cannot conceal an inaccurate assessment. Previous trials’ all-reasons-perfect criteria remain unchanged.

`Task` assesses the stem and choices separately from the hidden authored key. Thus the even-integer question has a sound task and unique answer B, while its hidden key A and three teaching fields are wrong. Conversely, the duplicate-distractor examples have correct keys and entirely true feedback, but fail task diversity. A model must not obtain credit for correct rejection through an unrelated false accusation.

### Interpretation caveats for root review

- **Bus, 26 rides:** the exact feedback says that 26 satisfies the condition but is not the minimum. Those mathematical statements are true. Its implied use to exclude 26 is unjustified under the defective stem, which never asks for a minimum. The new isolated-field expectation is `uncertain`; the original contextual field audit remains preserved. The task and answer set still decisively require rejection because both 25 and 26 satisfy the literal question.

- **Semicolon before “and”:** the source gold itself notes style sensitivity. The new field expectation and offered-answer assessment retain that uncertainty. B and C are definitely valid distinct constructions, already sufficient to prove the defective question nonunique. The main feedback and C feedback additionally assert a false universal placement rule. The corrected stem explicitly selects second-clause “however,” making B unique without a universal prohibition. Bruce Aune’s [Punctuation and Syntax, Rule R2, printed page 5](https://cse.buffalo.edu/~rapaport/Papers/Papers.by.Others/aune01-punctuation.pdf) describes attachment of a conjunctive adverb to either clause.

- **Triangle:** `answerChoice: none` means no offered length is entailed as the actual third side. Lengths 6, 8 and 10 are all possible because 2 < x < 12; none is determined by the two given sides. The draft does not reinterpret the task as asking for a possible side, add the invented perimeter 18, or relabel the original rejection.

Root confirmed that interpretation-dependent new field labels should stay explicit, while original payloads and overall rejection gold remain immutable. These caveats do not create a route for accepting an uncertain item.

### Per-item coverage

`S` = supported, `U` = unsupported, `?` = uncertain. Feedback columns retain each original choice’s a–d order; answer letters refer to the exact offered strings in the draft. “multiple” and “none” are independent answer-set judgments, not the author’s hidden key.

| Original case | Frozen gate | Task | Answer | Main | a | b | c | d |
|---|---|---|---|---|---|---|---|---|
| familiar_weighted_grade_defective | reject | S | c | U | S | U | S | U |
| familiar_paint_defective | reject | S | b | S | U | S | S | S |
| familiar_paint_sound | accept | S | b | S | S | S | S | S |
| familiar_bus_sound | accept | S | b | S | S | S | S | S |
| familiar_weighted_grade_sound | accept | S | c | S | S | S | S | S |
| familiar_bus_defective | reject | U | multiple | S | ? | S | S | S |
| fresh_causal_evidence_defective | reject | U | none | U | U | U | U | U |
| fresh_parallel_timing_sound | accept | S | b | S | S | S | S | S |
| fresh_parallel_timing_defective | reject | S | b | S | S | S | U | S |
| fresh_causal_evidence_sound | accept | S | a | S | S | S | S | S |
| fresh_signed_square_sound | accept | S | a | S | S | S | S | S |
| fresh_signed_square_defective | reject | U | multiple | S | S | U | S | S |
| supplement_duplicate_wrong_value_defective | reject | U | a | S | S | S | S | S |
| supplement_semicolon_defective | reject | U | multiple | U | S | S | U | ? |
| supplement_duplicate_wrong_value_sound | accept | S | a | S | S | S | S | S |
| supplement_decimal_representation_sound | accept | S | a | S | S | S | S | S |
| supplement_semicolon_sound | accept | S | b | S | S | S | S | S |
| supplement_decimal_representation_defective | reject | U | multiple | U | U | U | U | S |
| rectangle_perimeter_complete | accept | S | a | S | S | S | S | S |
| triangle_missing_perimeter | reject | U | none | U | U | U | U | S |
| necessary_ticket_inference | accept | S | a | S | S | S | S | S |
| text_identifier_leading_zero | accept | S | a | S | S | S | S | S |
| even_integer_converse_error | reject | S | b | U | U | U | S | S |
| editor_duplicate_discard_actions | reject | U | a | S | S | S | S | S |

### Proof and reporting boundaries

Every teaching field has an exact text hash and a concrete independent proof covering its material claims. Calculations include the false paint ratio (15:9 = 5:3), the false reversed weighted mean (70%/30% gives 81.6, not 82.4), the false sequential timing equality (4 + 7 + 3 = 14, not 11), and the invalid evenness converse (n = 2 is a counterexample). The observational controls use alternative explanations consistent with the stated observations; unmeasured factors are not ruled out merely because they were unmeasured.

True calculations do not excuse an invented requirement. The unrestricted half-value question cannot borrow the paired question’s notation restriction; the signed-square question cannot borrow a nonnegative domain; the bus question cannot borrow a minimum requirement; and the triangle cannot borrow a perimeter. Context also determines diversity: exact-text IDs and expressly requested notation distinguish strings that numerical-value tasks may treat as equivalent.

Private explanations from earlier model trials are not learner-field gold. A previously inaccurate rectangle reason does not make the unchanged rectangle learner payload defective. The new proposed decomposition reports private-reason defects independently from learner correctness; it does not retrospectively qualify any failed trial. Difficulty must be declared and reported separately before any new run. These are repeated diagnostic controls, not fresh-worker yield evidence or a universal semantic guarantee.

No provider calls, source edits, learner-text repairs, old-gold edits, or new experimental freeze occurred during this preparation. The failed solver count-map trial remains a separate transport failure with zero model records, so this draft is not evidence that the inactive authored-feedback pipeline is ready to dispatch.

The inactive pure audit module also accepted all 24 handcrafted expectation rows and selected exactly the 12 frozen sound payloads without changing their contents. Exact key/difficulty hiding, all 120 feedback-slot associations and the local reason bounds passed. This is an offline binding and gate check using expected labels, not a provider result or semantic qualification.
