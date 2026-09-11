# Saddle & Ink

Approved app-wide direction for Checkpoint. The design should feel like a considered learning instrument: warm paper, espresso ink, quiet typography, and progress that is grounded in stored answers.

## Shared roles

| Role | Day | Evening |
| --- | --- | --- |
| Canvas | `#F2EBDD` | `#191714` |
| Surface | `#FAF7F0` | `#27221D` |
| Raised surface | `#F0E7D9` | `#332B23` |
| Main text | `#29231E` | `#EDE3D4` |
| Secondary text | `#71675A` | `#B7A995` |
| Brand / navigation | `#805A3B` | `#CBA678` |
| Primary action | `#29231E` | `#E3D2BA` |
| Primary action label | `#FAF7F0` | `#29231E` |
| Selection wash | `#E3D2BA` | `#393027` |
| Fine divider | `#D8CDBD` | `#493F34` |

A warm selection wash always has a readable label and an explicit selected symbol or contrasting outline. Fine dividers are decorative separators; interactive boundaries use the stronger control or selection outline. Success remains muted green, review amber, incorrect/destructive red, and informational evidence slate. Brand color must not imply success. Fixed espresso hero surfaces use their dedicated light foregrounds in either appearance.

## Type and surfaces

Use native serif text styles for goals, editorial headings, and large summary metrics. Keep question passages, answers, editable fields, body copy, navigation, and controls in the native sans face. Native text styles and scaled metrics retain Dynamic Type; accessibility layouts may stack controls rather than shrinking labels.

Prefer open sections separated by thin rules. Use warm filled surfaces for inputs, answer choices, and genuinely grouped content. Primary actions are flat, approximately eight-point corners, with a leading label and trailing symbol. No decorative gradient, glow, heavy shadow, metallic border, or artificial material texture is part of this direction.

The compact six-spoke Home beacon is a decorative identity mark. Its neutral spokes do not claim skill mastery; adjacent weekly metrics continue to use actual stored evidence.

## Behavior and ownership

This rollout changes presentation. Preserve goal activation, targeted-skill selection, session preparation, scoring, answer evidence, history scope, protection, membership, and destructive confirmations. Existing learning-map changes are captured in a separate prerequisite commit. The original checkout's uncommitted backend work remains untouched.

Apple-owned purchase, authorization, sharing, and Family Activity Picker surfaces remain native. The Screen Time shield mirrors the palette through the API's available color fields; it cannot use the same SwiftUI layout and typography.

## Validation

Use signed simulator XCTest with parallel testing disabled so App Group tests remain meaningful. Retain the existing contrast requirements: 4.5:1 for normal labels and 3:1 for meaningful control boundaries. Inspect actual native rendering attachments in both appearances, compact widths, long-label states, and accessibility sizes. These fixtures are geometry checks and review evidence, not golden-image comparisons.

Run the full simulator suite, Release simulator build, and static analysis. Check hosted macOS CI on the final PR head. Physical Screen Time shield operation, VoiceOver navigation, and real-device gesture behavior require device validation and must be reported separately from screenshot inspection.
