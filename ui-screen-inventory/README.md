# Checkpoint UI Screen Inventory

This inventory contains 40 simulator-rendered scenarios plus two below-the-fold terminal-state details, covering the 15 app-owned surfaces that can be represented faithfully without a physical iPhone.

- Open `index.html` for the clickable gallery.
- Open `00-all-screens-overview.jpg` for a single contact sheet.
- Open the numbered contact sheets for larger grouped views.
- Full-resolution captures are in `screens/`.

## Coverage

- Screen Time access: initial, denied, and data-erasure recovery
- Goal setup: new and edit
- Home: empty, ready, generating, failed, protected, active break, and weekly activity
- Weekly review
- Progress: empty, building, attention, suggested map, and reviewed map
- Skill Map review and repair
- Settings: Free and Pro/protected
- History: empty and populated
- Help & Feedback: empty and saved notes
- Protected Apps picker
- Plan: Free and Pro
- Reset confirmation
- Checkpoint: unanswered, selected, correct, incorrect, pass, fail, pass/fail completion actions, reflection, and stop-protection challenge
- Generation diagnostics: empty and populated

## Physical-device-only surfaces

The branded iOS shield and real Family Controls behavior require a signed physical-device build. StoreKit purchase confirmation, the system share sheet, and Screen Time authorization are Apple-owned system surfaces and are not simulated in this gallery.

The screenshot fixtures were rendered from an isolated Debug-only scenario harness in a temporary worktree. Production source and persisted app data were not changed.
