# Additional English agreement reasoning family

This candidate adds a relative-clause agreement family to English slot 3. The
plural antecedent of *who* controls one verb, while singular *one* controls the
other. Four closed scenes and two clause orders yield eight new exact stems;
the closed compiler supplies four distinct ordered pairs, one key, and
choice-specific feedback. Neither the model nor a user-supplied phrase controls
the key. The selector now balances mechanism counts before scene variants.

The offline [40/80 bank comparison](run.py) reuses the saved 3:2 source seed,
compiler, proof, history projection, and duplicate gate. It makes no provider
call or real bank write:

| Bank items | Unique exact stems | Baseline same-slot/family pairs | Candidate pairs | Slot 3 candidate family uses |
| ---: | ---: | ---: | ---: | --- |
| 40 | 40 | 60 | 55 | proximity 3, inversion 3, relative 2 |
| 80 | 80 | 280 | 259 | proximity 6, inversion 5, relative 5 |

The improvement is structural: 21 fewer same-family pairs at 80. It does not
prove semantic distance or live worker yield. Slot 4 still exhausts after 80
items, so the bank-wide capacity problem remains. Independent blind review and
a full-worker refill are still required before route qualification.

Those rows are the isolated English-only comparison against the frozen
two-family baseline. After the separate numeric repertoire change was combined
on `main`, the same current-source replay reports 40 pairs at 40 items and
196 pairs at 80 items. The [reusable capacity gate](../../MAPPED_BANK_CAPACITY_GATE.md)
records the per-slot family use and the remaining exact-stem headroom.

The compact mapped native schema grows from 1,802 to 1,880 bytes (SHA-256
`7dee4a1847503afedeb15e58afa8b0bb791af1ea71966c04ae6e86f3152e4ee0`).
The non-family mapped agreement schema grows from 2,904 to 2,982 bytes
(SHA-256 `5fde195cf2fffeff4b0b6f5035def6a68a497e12b0a2f6d09cd4ad7c1a774c47`).
Both stay below the local 3,000-byte contract bound. With the numeric expansion
integrated, the mapped-family schema is 1,966 bytes (SHA-256
`ea9ebbe2e1cf7e594371991dd16059b0251938649db966c4d5fb334fde8058cc`).
The changed schemas have new transport names; native provider acceptance for
these combined schema bytes has not been measured.
