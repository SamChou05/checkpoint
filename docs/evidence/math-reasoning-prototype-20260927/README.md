# Offline worked-evaluation prototype

This prototype covers the mapped level-2 objective “Evaluate an exact rational expression or explicit bounded condition” with a response format different from choosing a numerical value, counting solutions, or comparing two values. The learner selects the one valid **worked derivation** of a rational expression. The model's entire task is to choose one of six curated scene IDs; code owns all operands, question text, four worked options, literal correct option, and teaching.

Three scenes use multiplication before addition and three use division before addition. The flawed options perform addition first, add fraction numerators and denominators separately, or misuse multiplication/division inside the expression. `Fraction` computes all outcomes exactly. The constructor rejects any scene in which an incorrect method reaches the true result or two methods reach the same result. The tests pin independently calculated results for all six scenes and rotate the correct option across all four positions.

The choice text presents only the two calculation steps. It does not label a method as correct or name its mistake, because such labels would give away the answer without evaluating the arithmetic.

This is **not production-wired**. It has no native provider acceptance check, blind learner review, bank novelty evidence, or live worker qualification. The six scenes may repeat the same solve pattern too often in a larger bank; passing deterministic arithmetic tests alone does not establish level-2 difficulty or adequate cross-question variety.
