# Mascot dialogue art prompts

Created with the built-in image-generation tool on September 6, 2026. Each pose used the canonical `checkpoint-app-icon-source.png` as its identity reference. Final project assets live in `Checkpoint/Assets.xcassets/MascotWave.imageset`, `MascotThink.imageset`, and `MascotCelebrate.imageset`.

## Shared generation prompt

Use case: illustration-story. Asset type: one transparent character sprite for a native iPhone app's friendly video-game-style dialogue. Image 1 is the identity and art-style reference, not a background to preserve. Make ONE isolated full-body pose of this EXACT Checkpoint mascot: rounded brown phone body, cream screen face, warm dark oval eyes, peach blush, tiny smile, sage-green brain top and sage-green short arms, small sage shield with dark checkmark. Preserve its recognizable proportions, rounded illustrated-paper texture, warm cream/brown/sage palette, soft outlines. Center the entire character with generous safe margins, consistent front three-quarter viewpoint, no cropping, character fills about 85% of square canvas. Actual transparent alpha background, no ivory tile, no icon frame, no floor, no text, no letters, no watermark, no other character. High quality at 1024 square, readable at 100 points in UI.

## Pose suffixes

### Wave

Pose: WELCOMING WAVE. Same character smiling with open friendly eyes, one arm raised in a big visible hello wave and the other holding its familiar checkmark shield at its side. Small energetic tilt as if stepping into the conversation. Friendly, grounded, cheerful. Do not add legs if none in reference.

### Think

Pose: THINKING/LISTENING. Same character with a curious attentive expression, one hand touching its chin just under the screen's smile, head/body subtly tilted, eyes looking slightly upward in thought, other arm rests alongside its familiar checkmark shield. The pose must differ clearly from a wave; no raised waving hand. Kind and thoughtful, never sad or worried.

### Celebrate

Pose: DELIGHTED CELEBRATION. Same character with happy curved smiling eyes and a wider tiny smile, one arm stretching upward in a triumphant cheer and the other lifting its familiar checkmark shield proudly, small springing tilt as if giving a happy little hop. Visibly different arms/expression from wave and thinking. No confetti, no floating decorations.

## Final refinement prompt

Each generated pose was the edit target for this exact instruction. The final portraits use a solid background because the initial output baked a checkerboard into an opaque PNG.

Use case: precise-object-edit. Image 1 is the edit target. Preserve this exact character, expression, pose, full uncropped body, illustrated paper texture, palette, shield, face, scale and composition. Replace ONLY the entire gray/white checkerboard backdrop with one uniform flat warm ivory background, hex #F5EEDC. No checkerboard, no floor, no shadow on the background, no vignette, no border, no tile, no texture on the BACKGROUND, no text. The background must be a clean flat solid color suitable for a character portrait in a game dialogue panel. Keep all the mascot's outlined edges clean, no halo. Square canvas.

Wave-only suffix: Also give the mascot two tiny sage-green rounded feet peeking out beneath its body, matching the same paper illustration style; maintain a friendly wave.
