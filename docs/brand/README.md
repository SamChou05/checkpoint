# Checkpoint Brand Assets

[checkpoint-app-icon-source.png](checkpoint-app-icon-source.png) is the canonical full-resolution app-icon master. Keep the [shipping 1024-pixel copy](../../Checkpoint/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png) byte-identical when updating it.

The unchanged 240-pixel [ShieldMascot.png](../../ShieldConfigurationExtension/ShieldMascot.png) is shared by the main app's guided First Win experience and the Screen Time shield extension. Keep it in both targets so the same mascot remains visible across the handoff.


## Dialogue portraits

The initial experience uses three matching portraits generated with the built-in image tool from the canonical app icon. They are bundled in the main app catalog as [MascotWave](../../Checkpoint/Assets.xcassets/MascotWave.imageset/MascotWave.png), [MascotThink](../../Checkpoint/Assets.xcassets/MascotThink.imageset/MascotThink.png), and [MascotCelebrate](../../Checkpoint/Assets.xcassets/MascotCelebrate.imageset/MascotCelebrate.png). The existing app and shield icons are unchanged.

The portraits have a warm ivory background and are displayed in softly rounded character frames. The image provider rendered the initial transparency request as an opaque checkerboard; those drafts were discarded from app use and the final portraits were refined with a solid background.

[Generation and refinement prompts](mascot-dialogue-prompts.md) preserve the production art instructions.
