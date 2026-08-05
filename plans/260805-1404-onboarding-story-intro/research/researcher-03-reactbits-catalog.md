# ReactBits Catalog — visual/behavioral reference for SwiftUI story screen

Sources: reactbits.dev sitemap + `/llms.txt` (full catalog w/ one-liners; component pages themselves are client-rendered, unfetchable) + GitHub `DavidHDev/react-bits` demo prop tables (exact behavior for MagicRings, RippleDistortion, ScrollExpand, MagicBento, FluidGlass, BubbleMenu). We borrow VISUAL IDEAS only — implement natively (SwiftUI Canvas/TimelineView/Metal shaders/`layerEffect`, iOS 17.3 floor).

Story beats legend: **chaos** (scattered passwords), **danger** (breach), **order** (vault organizes), **relief** (simplicity/autofill), **magic** (encryption/reveal).

## A. User-named components (10)

### 1. Bubble Menu — Components (`/components/bubble-menu`)
Fixed round logo bubble + round hamburger bubble; on tap the menu items pop in as pill/bubble shapes with staggered elastic overshoot (back-out ease) and slight per-item rotation offsets, hamburger lines morph to X. Closing reverses with quick shrink. Props: menuBg, content color, staggered reveal, fixed positioning.
Beat: **relief/playful order** — features popping into place one by one.

### 2. Ripple (two candidates)
- **Ripple Distortion** — Animations (`/animations/ripple-distortion`). An image behaves as a water surface: pointer motion lays down ripples (brushSize px, spacing between drops) that displace/refract the picture with concentric swells (`rings`), chromatic red/blue `dispersion`, a `glint` sheen on ripple shoulders, optional `tint` on disturbed water; each ripple grows `spread`× its size and dies over `fade` seconds. Clicks splash bigger (`clickStrength`); grayscale mode reads on tone alone.
Beat: **danger/chaos** — surface of order disturbed by touch; also great tap-feedback magic.
- **Ripple Grid** — Backgrounds (`/backgrounds/ripple-grid`). Grid of dots/lines continuously animating a radial ripple wave; calm, self-running.
Beat: **order** — steady heartbeat background.

### 3. List = Animated List — Components (`/components/animated-list`)
Vertical list where items enter with staggered slide+fade+scale; while scrolling, items near top/bottom edges fade/shrink under gradient masks so the list feels like a living column; supports arrow-key selection highlight and hover states.
Beat: **order** — credentials filing themselves into a neat vault list.

### 4. Card family — Components
- **Tilted Card** (`/components/tilted-card`): 3D perspective tilt tracks pointer, subtle scale-up, caption tooltip follows cursor; springs back on leave. Beat: **magic** (precious object).
- **Spotlight Card** (`/components/spotlight-card`): dark card, radial spotlight gradient centered at pointer inside the card, fades on exit; spotlightColor prop. Beat: **magic/reveal**.
- **Card Swap** (`/components/card-swap`): stacked cards periodically animate swapping positions with smooth layout spring. Beat: **order**.
- **Decay Card** (`/components/decay-card`): hover parallax that disintegrates/smears card content like decay. Beat: **danger**.
- **Bounce Cards** (`/components/bounce-cards`): cards bounce in on mount, overlapping fan. Beat: **relief** entrance.
- **Profile Card** (`/components/profile-card`): holographic glare + 3D hover tilt. Beat: **magic**.

### 5. Aura = Aurora — Backgrounds (`/backgrounds/aurora`)
Full-bleed WebGL aurora: vertical curtains of gradient light (configurable colorStops) undulating slowly along the top of the screen, amplitude and blend control softness; non-interactive, hypnotic. Sibling **Soft Aurora** (`/backgrounds/soft-aurora`): 3D Perlin noise + cosine palettes, an even softer nebula wash.
Beat: **magic/relief** — serene closing state after chaos.

### 6. Liquid Glass = Fluid Glass — Components (`/components/fluid-glass`)
Three.js glass object in lens / bar / cube mode gliding after the cursor, refracting whatever content scrolls beneath it (material props: ior, thickness, transmission, chromatic aberration); bar mode is a glass navbar with navItems. Content stays sharp outside, warped inside the glass.
Beat: **magic** — "looking through the vault's glass". SwiftUI cousin: iOS 26 Liquid Glass / `layerEffect` distortion; also see **Glass Surface** below.

### 7. Scroll Expand — Animations (`/animations/scroll-expand`)
Pinned stage: a rounded media frame (image or looping muted video) rests at startWidth/startHeight % with a headline held over it and a small scroll hint; scrolling scrubs the frame growing to full bleed (corner radius startRadius→endRadius, media zoom eases back to 1), title lifts away, a gradient scrim fades in, overlay children fade in at full bleed, frame holds pinned for holdDistance then releases. `smoothing` adds follow lag vs locking to scrollbar.
Beat: **transition/immersion** — a story panel swallowing the screen between beats.

### 8. Blur Text — Text Animations (`/text-animations/blur-text`)
Text split by words or letters; each segment starts blurred (~8-10px) and offset from top or bottom, then staggers into sharp, in-place focus (configurable per-segment delay, step duration, easing); fires when scrolled into view.
Beat: **relief/reveal** — clarity emerging from fog; ideal for the story's key lines. (SwiftUI: per-word `blur`+`offset`+`opacity` with staggered delays — trivial to do natively.)

### 9. Magic Bento — Components (`/components/magic-bento`)
Dark bento grid of feature cards with a purple glow language: a radial spotlight follows the cursor across the whole grid (spotlightRadius), the hovered card gets a border glow oriented toward the cursor, optional floating particle "stars" rise inside the hovered card, optional 3D tilt and magnetism (card translates slightly toward pointer), click spawns a ripple pulse from the tap point. All effects individually toggleable (enableStars/Spotlight/BorderGlow/Tilt/Magnetism/clickEffect, glowColor RGB).
Beat: **order+magic** — feature overview panel; each Vaultify pillar as a glowing bento tile.

### 10. Magic Rings — Animations (`/animations/magic-rings`)
Concentric neon rings (interpolating color→colorTwo) drawn with glow attenuation; rings slowly expand (scaleRate) and cycle fade-in/out, each ring has an exponential angular cutaway (ringGap) so arcs feel rune-like; optional blur bloom + film grain. Pointer: rings shift toward mouse (followMouse+mouseInfluence), per-ring parallax depth, hoverScale swell; clickBurst fires a brightness flash + scale pulse.
Beat: **magic** — encryption sigil/portal; perfect "vault sealing" moment. (SwiftUI: Canvas + TimelineView arcs w/ blur, very doable.)

## B. Standouts for a cinematic security-story intro

### Backgrounds
- **Orb** (`/backgrounds/orb`): floating energy sphere, iridescent swirling shader surface, slow rotation; hover intensifies/distorts swirl toward pointer (hue, hoverIntensity, rotateOnHover, forceHoverState). Beat: **magic** — the "vault core" hero object.
- **Ballpit** (`/backgrounds/ballpit`): 3D physics pit of glossy colored spheres falling, colliding, piling; the cursor is an invisible ball shoving them around (count, gravity, friction, wallBounce, followCursor). Beat: **chaos** — passwords everywhere.
- **Threads** (`/backgrounds/threads`): field of fine horizontal wavy lines undulating like fabric; pointer proximity bends/amplifies the weave (amplitude, distance, mouse toggle). Beat: **order** — strands weaving together.
- **Silk** (`/backgrounds/silk`): smooth silk-cloth waves with soft specular lighting and gentle grain, slow continuous flow, non-interactive (speed, scale, color, noiseIntensity, rotation). Beat: **relief/calm**.
- **Particles** (`/backgrounds/particles`): drifting 3D particle cloud, subtle parallax toward pointer, configurable colors/sizes/alpha. Beat: neutral **magic dust**, any beat.
- **Galaxy** (`/backgrounds/galaxy`): realistic parallax starfield, twinkle, pointer interaction (repulsion/attraction). Beat: **magic/scale**.
- **Hyperspeed** (`/backgrounds/hyperspeed`): hyperspace tunnel of light lines; press-and-hold accelerates, release decelerates. Beat: **transition** chaos→order jump.
- **Lightning** (`/backgrounds/lightning`): procedural branching bolts with glow flicker. Beat: **danger**.
- **Letter Glitch** (`/backgrounds/letter-glitch`): Matrix-style grid of glitching random letters. Beat: **danger/chaos** — breach wall.
- **Faulty Terminal** (`/backgrounds/faulty-terminal`): CRT scanline squares, flicker + noise. Beat: **danger** retro-hacker.
- **Dark Veil** (`/backgrounds/dark-veil`): subtle dark smoke/veil w/ postprocessing. Beat: **danger/mystery** opening.
- **Light Rays** (`/backgrounds/light-rays`): volumetric god-rays from a configurable direction, optional pointer follow. Beat: **relief** — light entering the vault.
- **Beams** (`/backgrounds/beams`): crossing animated light ribbons. Beat: **order/magic**.
- **Prismatic Burst** (`/backgrounds/prismatic-burst`): rays bursting from center, controllable color/amount/distortion. Beat: **climax reveal**.
- **Liquid Ether** (`/backgrounds/liquid-ether`): interactive liquid shader, flowing swirls chase pointer. Beat: **magic**.
- **Dot Field / Dot Grid** (`/backgrounds/dot-field`, `dot-grid`): interactive dot lattice; cursor bulge, glow, sparkle, click wave pulses. Beat: **order** — structured, touch-responsive.
- **Iridescence / Liquid Chrome / Molten Metal**: flowing metallic/iridescent shader surfaces. Beat: **magic/premium**.

### Text animations
- **Decrypted Text** (`/text-animations/decrypted-text`): characters cycle random glyphs then lock into the real text sequentially or randomly (speed, maxIterations, revealDirection, animate on view/hover). Beat: **magic** — literal decryption; signature Vaultify moment.
- **Scrambled Text** (`/text-animations/scrambled-text`): glyphs within a radius of the cursor scramble to random chars with falloff, restore on leave. Beat: **chaos/danger** — text corrupting under touch.
- **Shiny Text** (`/text-animations/shiny-text`): metallic sheen sweeps repeatedly across otherwise static text. Beat: **magic/premium** accents, CTA.
- **Count Up** (`/text-animations/count-up`): number tweens from→to with easing, separators, on-view trigger, callbacks. Beat: **order** — "N passwords secured".
- **Split Text** (`/text-animations/split-text`): chars/words stagger in from offset+opacity with configurable from/to states. Beat: general **entrance** workhorse.
- **Glitch Text** (`/text-animations/glitch-text`): RGB channel split + slice jitter, optional hover-only. Beat: **danger**.
- **Particle Text** (`/text-animations/particle-text`): text assembles from drifting particles, can scatter and reform on demand. Beat: **chaos→order** in one component — strongest single metaphor for the story arc.
- **True Focus** (`/text-animations/true-focus`): a focus frame jumps word-to-word, blurring all others. Beat: **order/emphasis**.
- **Gradual Blur** (`/animations/gradual-blur`): progressive edge-blur overlay that un-blurs on scroll — cinematic reveal. Beat: **relief**.
- **Text Pressure** (`/text-animations/text-pressure`): variable-font weight/width swells near pointer. Beat: **magic** tactile.
- **Falling Text** (`/text-animations/falling-text`): words fall with gravity + bounce, pile up. Beat: **chaos**.

### Interaction garnish (Animations)
- **Click Spark** (`/animations/click-spark`): radial spark lines burst at the tap point and fade. Beat: tap feedback anywhere.
- **Electric Border** (`/animations/electric-border`): jittery electric arcs + glow around a frame, adjustable intensity. Beat: **danger** framing.
- **Laser Flow** (`/animations/laser-flow`): laser beam flows down onto a surface w/ volumetric glow, pointer-reactive. Beat: **danger/magic** scan.
- **Star Border** (`/animations/star-border`): comet/sparkle orbiting an element's border. Beat: **magic** CTA framing.
- **Meta Balls** (`/animations/meta-balls`): liquid blobs follow cursor, merge/separate with implicit-surface smoothness. Beat: **chaos merging into one** — consolidation metaphor.
- **Magnet Lines** (`/animations/magnet-lines`): grid of short line segments all rotating to point at the cursor. Beat: **order** — everything aligning to you.
- **Swarm Cursor** (`/animations/swarm-cursor`): flocking particle swarm chases the pointer, jostles, drifts apart at rest. Beat: **chaos**.
- **Antigravity** (`/animations/antigravity`): 3D particle field repels from cursor. Beat: **danger/repulsion**.
- **Halftone Reveal** (`/animations/halftone-reveal`): halftone dot matrix resolves to sharp content around cursor. Beat: **reveal**.
- **Metallic Paint** (`/animations/metallic-paint`): liquid-metal shader applied to an SVG mark (logo treatment). Beat: **magic** logo moment.
- **Noise** (`/animations/noise`): animated film grain overlay. Beat: texture for **chaos/danger** scenes.
- **Pixel Transition / Pixel Blast** (`/animations/pixel-transition`, `/backgrounds/pixel-blast`): pixel dissolve reveal; exploding pixel bursts. Beat: **transition/impact**.

### Structural components
- **Glass Surface** (`/components/glass-surface`): Apple-style liquid-glass pane via SVG displacement — background refracts with edge distortion + chromatic offsets (red/green/blueOffset), brightness/opacity/blur controls, frosted fallback. Beat: **magic** — closest web analog to iOS 26 Liquid Glass; validates native material use.
- **Carousel** (`/components/carousel`): drag/swipe card carousel w/ spring snap, loop, autoplay, optional round mode, indicator dots. Beat: story **panel pager** candidate.
- **Depth Carousel** (`/components/depth-carousel`): cards recede along a 3D rail w/ perspective; drag, keyboard, auto-advance. Beat: **cinematic pager** alternative.
- **Stack** (`/components/stack`): card deck; drag the top card away and it flies out then cycles to the back with spring + random rotation; tap-to-send-back, autoplay. Beat: story **panel pager** (tactile).
- **Scroll Stack** (`/components/scroll-stack`): scrolling pins cards that pile over one another w/ depth scaling/blur of those beneath. Beat: **order** — layered accumulation.
- **Stepper** (`/components/stepper`): animated multi-step progress w/ active-state transitions. Beat: onboarding progress.
- **Dock** (`/components/dock`): macOS-style proximity magnification of icons. Beat: **relief/playful**.
- **Chroma Grid** (`/components/chroma-grid`): grayscale tiles regain color on hover. Beat: **relief** — color returning.
- **Folder** (`/components/folder`): folder opens to reveal nested papers w/ smooth motion. Beat: **order** — Spaces metaphor.
- **Lanyard** (`/components/lanyard`): 3D badge on a swinging lanyard w/ inertial physics. Beat: **identity** moment.
- **Elastic Slider** (`/components/elastic-slider`): handle stretches elastically, snaps back w/ spring. Beat: playful control.
- **Counter** (`/components/counter`): rolling odometer-style animated digits. Beat: **order** stats.

## C. Full category index (for completeness)
- Text Animations (36): masked-heading, particle-text, split-flap-text, warp-text, stroke-text, depth-text, fold-text, echo-text, text-loop, split-text, blur-text, circular-text, text-type, shuffle, shiny-text, text-pressure, curved-loop, fuzzy-text, gradient-text, falling-text, text-cursor, decrypted-text, true-focus, scroll-float, scroll-reveal, ascii-text, scrambled-text, rotating-text, glitch-text, scroll-velocity, variable-proximity, count-up.
- Animations (36 listed): scroll-expand, elastic-mesh, ripple-distortion, swarm-cursor, halftone-reveal, cursor-grid, animated-content, fade-content, electric-border, orbit-images, pixel-transition, glare-hover, antigravity, logo-loop, target-cursor, magic-rings, laser-flow, magnet-lines, ghost-cursor, gradual-blur, click-spark, magnet, strands, sticker-peel, pixel-trail, cubes, metallic-paint, noise, shape-blur, crosshair, image-trail, ribbons, splash-cursor, meta-balls, blob-cursor, star-border.
- Components (45): depth-carousel, accordion-gallery, morph-slider, drift-wall, specular-button, option-wheel, curved-input, line-sidebar, animated-list, scroll-stack, bubble-menu, magic-bento, circular-gallery, reflective-card, card-nav, stack, fluid-glass, pill-nav, tilted-card, masonry, glass-surface, dome-gallery, chroma-grid, folder, staggered-menu, model-viewer, lanyard, profile-card, dock, gooey-nav, pixel-card, carousel, spotlight-card, border-glow, flying-posters, card-swap, glass-icons, decay-card, flowing-menu, elastic-slider, counter, infinite-menu, stepper, bounce-cards.
- Backgrounds (54): molten-metal, gradient-waves, web-threads, topography, light-tunnel, sliced-waves, acid-squares, scanner, ferrofluid, lightfall, liquid-ether, prism, dark-veil, light-pillar, silk, floating-lines, side-rays, light-rays, pixel-blast, color-bends, evil-eye, line-waves, radar, soft-aurora, aurora, plasma, plasma-wave, particles, gradient-blinds, grainient, grid-scan, beams, pixel-snow, lightning, prismatic-burst, galaxy, dither, faulty-terminal, ripple-grid, dot-field, dot-grid, threads, hyperspeed, iridescence, waves, grid-distortion, ballpit, orb, letter-glitch, grid-motion, shape-grid, liquid-chrome, balatro.

## D. Story-arc mapping suggestion (chaos → danger → order → relief → magic)
1. **Chaos**: Ballpit / Falling Text / Swarm Cursor / Letter Glitch + Noise grain.
2. **Danger**: Lightning / Electric Border / Glitch Text / Scrambled Text / Dark Veil / Faulty Terminal.
3. **Order**: Animated List / Magnet Lines / Particle Text reforming / Threads weaving / Count Up / Scroll Stack.
4. **Relief**: Blur Text resolving / Light Rays / Chroma Grid recoloring / Silk / Gradual Blur lifting.
5. **Magic (seal)**: Magic Rings sigil + Orb core + Decrypted Text + Aurora close + Shiny Text CTA, framed in Glass Surface material.
Pager mechanics: Scroll Expand (scroll-scrubbed immersion) or Stack/Carousel (tactile swipe) as the panel driver.

## Unresolved questions
1. "card" and "list" in the user's naming are ambiguous — assumed Animated List + the card family (tilted/spotlight/card-swap); confirm which card the user saw.
2. "aura" assumed = Aurora (or Soft Aurora); could conceivably mean Orb's aura glow — confirm.
3. "ripple" assumed = Ripple Distortion (animations) with Ripple Grid as alternate; confirm.
4. Component pages are client-rendered; descriptions come from llms.txt + repo prop tables + pre-2026 knowledge of these components — a few newest items (e.g. balatro, evil-eye, ferrofluid) only have one-line descriptions.
5. Performance: several borrowed ideas (physics ballpit, fluid sims) need Metal/SpriteKit on iOS 17.3 floor — feasibility per-effect not yet assessed (separate research task).
6. Reduce Motion: every borrowed effect needs a static/cross-fade fallback per design-dna-standard — not covered here.
