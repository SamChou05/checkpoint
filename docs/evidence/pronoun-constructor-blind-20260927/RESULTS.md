# Pronoun-role constructor: blind review result

**Decision: retain as a standalone prototype; do not wire it into the mapped
author or claim bank variety.** The 16 frozen scene/order variants from
`88810ca` have exactly one code-owned key and four meaningfully different
role-map choices each. Two independent reviewers, given only the keyless
worksheet, both selected the intended key for all 16 items, rated every item
difficulty 2, and judged all 96 within-item choice pairs meaningfully
different. The private key map was opened only after both reviews were saved
and hashed. It is outside Git; its SHA-256 is
`2750e4db1c926cbdb19ff6e8fa3734c8937ed8bfc7b5cb437622b8c72aa16748`.

The same two reviews independently identified **56 of 120 cross-item pairs**
as strong repeats, with identical pair sets: every pair among Q01–Q08 and
every pair among Q09–Q16. Reordering clauses or dialogue does not change the
underlying role-map decision or answer format. Thus 16 exact, uniquely keyed
variants are only two substantive formats, not 16 diverse questions for a
repeated bank. The original worksheet SHA-256 is
`2641430f0893596b79dbc937f3dd6791aadefa4138122b12655cfe53d5aa0ebe`;
the independent locked review hashes are
`0451744953abc0d3dbfb3e801c7f84c897fd2f391c516907b7a4ee72d8f0807b`
and
`8df8b98f6c4f9db7e4f920002b2ea2409bde90ea8981464121acdff5b8ce7504`.

Both reviewers also found that Q01–Q08's original prompt described the
addressee's action in a temporal clause as if it were an independent proposal.
Commit `a644840` changed only that prompt to ask who **would** act *if the
actions occur*. The choices and key remain byte-identical. In separate
keyless targeted reviews of the eight amended prompts, both reviewers found
the claim now conditional and the one-key role map clear. Their review hashes
are `5916f327e6306c50e847a503144ff7c03f93bc67ca0a06cfa6476e73ef65e9d7`
and `2727f73868a74dc791e4b4360911998ada086eeca461729d7fd12ea91dd5377f`.
The repaired prompt worksheet SHA-256 is
`b3c6b2d8338ed277064838969877f1ee5c844523136d46da483a196afe8aeab6`.
The strong-repeat finding is unchanged.

This was an offline code-owned content test. It did not exercise a Bedrock
author schema, the full solver/reviewer worker, or a mixed 20/40/80-item bank.
The constructor stays outside production routing. The result supports adding
new substantive response mechanisms, not inflating the scene list for either
existing role-map template.
