# macOS Arc/Dia-Style Onboarding Research

**Date:** 2026-08-05  
**Repo:** Vaultify (Loox password manager)  
**Context:** Evaluating feasibility of full-screen cinematic macOS onboarding for story-intro flow

---

## Executive Summary

Full-screen cinematic onboarding is **technically feasible on macOS 15 with native SwiftUI**, but Arc and Dia don't actually use the "full-screen takeover" pattern widely imagined. Instead, they employ **polished modal workflows with incremental feature discovery**. Recommendation: Build a **discrete step-driven onboarding window** (click/arrow-key advancement) rather than scroll-driven, reuse iOS animation assets where possible, and defer the main app window until complete.

---

## 1. Arc & Dia Onboarding Reality Check

### Arc Browser
- **Status (2025):** Maintenance mode; The Browser Company pivoted focus to Dia.
- **Onboarding Pattern:** Procedural modal with import workflow.
  - Imports bookmarks/history from Safari, Chrome, Edge, Brave if detected.
  - Shows Space template gallery (e.g., Photo Gallery with pinned tab, blue gradient).
  - Arc Max (AI features) can be enabled during onboarding.
  - Multi-profile import support added recently.
- **Cinematic Elements:** None identified. Standard macOS modal UI, not full-screen takeover.

### Dia Browser (The Browser Company's newer product)
- **Launch:** Public beta on Mac (2025).
- **Onboarding Strategy:** Smooth, polished, thoughtful guiding.
  - Imports from installed browser (Safari, Chrome, Edge, Brave).
  - **Skills Walkthrough:** Short feature intro (conversational search, timeline history, contextual assistance).
  - **Memory opt-in:** Privacy-conscious feature discovery.
- **Cinematic Elements:** Polished UX, NOT full-screen immersion. More akin to SaaS onboarding than a movie.
- **Measurement:** Company uses onboarding as rollout control gate (measure usage → refine before wider release).

**Key Finding:** Neither Arc nor Dia uses a true "full-screen cinematic takeover." Both are **pragmatic modal workflows** optimized for feature discovery and data import, not spectacle.

---

## 2. Comparison: Celebrated macOS Onboarding

### Raycast
- **Walkthrough Command:** Built-in guided tour.
- **Pattern:** Modal with sequential task discovery (Action Panel → Calculator → Calendar → Window Management).
- **Notable:** Considered "one of the best onboarding experiences in an app."
- **Technical:** Functional walkthrough, not cinematic.

### CleanShot X
- **Pattern:** Modal with feature-by-feature intro.
- **Integration:** Raycast store listing offers extension access.
- **Cinematic:** No. Focused on clarity, not immersion.

### Notion Calendar (Cron)
- **Onboarding:** Interactive Getting Started tutorial + curated templates.
- **Pattern:** Asks user intent upfront (work/personal/school, role), pre-populates relevant templates.
- **Cinematic:** No. Personalization-driven, not visual spectacle.

### Linear Desktop
- **Expectation:** Clean, minimal onboarding for design-forward app.
- **Actual Details:** Limited in search results, but presumed modal, not full-screen.

**Consensus:** macOS apps prioritize **clarity + import workflow** over **cinematic immersion**. Full-screen takeover is rare, possibly due to:
- Stage Manager disrupting full-screen assumptions.
- User expectation that macOS apps are "just windows," not modal experiences.
- Accessibility/mission control compatibility.

---

## 3. Technical Architecture: SwiftUI Full-Screen Onboarding on macOS 15

### Window Styling (Core APIs)

```swift
// Borderless, titlebar-hidden window
.windowStyle(.hiddenTitleBar)
.windowToolbarStyle(.unified(showsTitle: false))

// Disable resizing (content-size based)
.windowResizability(.contentSize)

// For secondary window: default position + size
.defaultPosition(.topLeading)
```

### Full-Screen Window Implementation

**Option A: Native Full-Screen (Separate NSWindow)**
```swift
Window("Onboarding") {
    OnboardingView()
}
.windowStyle(.hiddenTitleBar)
.windowResizability(.contentSize)
.frame(width: NSScreen.main?.frame.width ?? 1024,
       height: NSScreen.main?.frame.height ?? 768)
```

**Caveats:**
- `.frame()` on a Window scene is fragile; more reliable via NSWindow bridging.
- Esc key automatically exits full-screen on macOS (system-level, cannot override programmatically).
- Must handle multi-display gracefully (NSScreen.main is primary, fallback needed).

**Option B: AppKit Bridge (Recommended for True Full-Screen Control)**
```swift
// Create NSWindow with borderless, full-screen geometry
let window = NSWindow(contentRect: NSScreen.main?.frame ?? .zero,
                      styleMask: [.borderless],
                      backing: .buffered,
                      defer: false)
let view = NSHostingView(rootView: OnboardingView())
window.contentView = view
window.makeKeyAndOrderFront(nil)
```

**Advantages:**
- Precise control over frame, level (kCGFloatingWindowLevelKey for always-on-top).
- Can suppress Esc key via responder chain override.
- Works reliably across macOS versions.

### Conditional Scene Management (Defer Main Window)

```swift
@main
struct VaultifyApp: App {
    @AppStorage("hasCompletedOnboarding") var hasCompleted = false
    
    var body: some Scene {
        if !hasCompleted {
            Window("Onboarding", id: "onboarding") {
                OnboardingWindowView(isComplete: $hasCompleted)
            }
            .windowStyle(.hiddenTitleBar)
        } else {
            WindowGroup {
                MainAppView()
            }
        }
    }
}
```

**Note:** AppStorage checks are evaluated once on launch; subsequent changes don't swap scenes. For true on-demand window management, use `NSApplication.shared.windows` inspection + manual ordering.

### Pagination (No TabView on macOS)

TabView's `.page` style **does not exist on macOS**. Options:

**Option 1: Custom Tab View Replacement**
```swift
struct PagedOnboarding: View {
    @State var currentPage = 0
    let pages: [OnboardingPage]
    
    var body: some View {
        ZStack {
            pages[currentPage].view
                .transition(.asymmetric(insertion: .move(edge: .trailing),
                                       removal: .move(edge: .leading)))
            
            HStack {
                Button("← Back") { currentPage -= 1 }
                    .disabled(currentPage == 0)
                Spacer()
                Button("Next →") { currentPage += 1 }
                    .disabled(currentPage == pages.count - 1)
            }
        }
        .onKeyPress(.leftArrow) { currentPage = max(0, currentPage - 1); return .handled }
        .onKeyPress(.rightArrow) { currentPage = min(pages.count - 1, currentPage + 1); return .handled }
    }
}
```

**Option 2: ScrollView with Paging (Simulated)**
- Possible, but awkward on macOS. Scroll momentum isn't expected for discrete onboarding steps.

### Keyboard Navigation

Arrow keys are **not automatic**. Use `.onKeyPress()` (iOS 18+/macOS 15+):

```swift
.onKeyPress(.rightArrow) {
    advance()
    return .handled
}
.onKeyPress(.leftArrow) {
    goBack()
    return .handled
}
.onKeyPress(.escape) {
    // Custom skip logic; don't rely on Esc exiting full-screen
    showSkipConfirmation = true
    return .handled
}
```

### Esc / Skip Handling

**Problem:** System-level Esc exits full-screen on macOS. Cannot fully suppress.

**Solutions:**
1. **Visible Skip Button** (recommended): Offer explicit "Skip Onboarding" button + keyboard shortcut hint.
2. **Soft Exit:** Esc → confirmation dialog ("Are you sure?") delays exit, gives sense of control.
3. **No Esc Handling:** Accept that Esc exits; design onboarding as non-blocky (user can re-enter later if they choose).

For Loox: **Show Skip button + hide main window until onboarding complete or skipped**. Users see Esc as power-user shortcut, not frustration.

---

## 4. Animation & Visual Patterns

### Layered Animation (Reusable from iOS)

CinematicOnboardingView-SwiftUI demonstrates:
- **Hero images** with full-screen background.
- **Animated overlays** (fade-in text, scale transitions).
- **Staggered reveals** (content appears in sequence).
- **Page transitions:** Fade + scale (smooth, not jarring).

**Swift Implementation:**
```swift
.transition(.asymmetric(
    insertion: .opacity.combined(with: .scale(scale: 0.95)),
    removal: .opacity
))
.animation(.easeInOut(duration: 0.3), value: currentPage)
```

### Gradient Backgrounds

Use semantic color tokens (from Vaultify design system):
```swift
LinearGradient(
    gradient: Gradient(colors: [
        Color(rgb: theme.accentColor).opacity(0.1),
        Color(rgb: theme.surfaceBackground)
    ]),
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```

**Benefit:** Supports light/dark mode switch live (no restart).

### Haptic Feedback on macOS

**Limited:** macOS has no built-in vibration motor. Can use:
- **NSHapticFeedbackManager** (Touch Bar feedback on MacBook Pro).
- **Beep/sound** (deprecated, avoid).
- **Visual feedback only** (animations, color change).

For Loox: Skip haptics on macOS; rely on visual + sound.

### Hold-to-Seal CTA Translation to macOS

**iOS Pattern:** Long-press gesture to confirm vault seal.

**macOS Translation:**
- **Click-to-seal** (standard macOS paradigm).
- **Long-click** (if holding is desired): Use `onLongPressGesture(minimumDuration: 0.5)`.
- **Button with progress ring** (visual feedback over time).

```swift
Button(action: {}) {
    ZStack {
        Circle().stroke(Color.secondary, lineWidth: 2)
        Circle()
            .trim(from: 0, to: holdProgress)
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(-90))
        Image(systemName: "lock.fill")
    }
}
.onLongPressGesture(minimumDuration: 1.0) {
    completeOnboarding()
}
```

---

## 5. Recommended Architecture for Loox

### Phase Structure

1. **Window Management**
   - Use conditional `@AppStorage("hasCompletedOnboarding")` to defer main WindowGroup.
   - Create onboarding `Window("Onboarding")` with `.hiddenTitleBar`.
   - On completion/skip: set AppStorage flag, app relaunch shows main app.

2. **Content Reuse**
   - iOS uses scroll-driven beats; **on macOS, extract beat content into discrete pages**.
   - Reuse gradient backgrounds, typography tokens, icon assets.
   - Adapt "scene" narrative for macOS (one idea per page, 4–6 pages max).

3. **Navigation**
   - **Discrete step buttons** (Back/Next) + arrow key support.
   - **Progress indicator** (dots, slide number).
   - **Skip button** (always visible; not hidden behind Esc).

4. **Visual Language**
   - **Full-screen background:** Gradient or subtle pattern (not video/animation intensive).
   - **Hero animation on enter:** Fade + scale of main content.
   - **Page transitions:** Asymmetric fade (in: fade+scale, out: fade).
   - **Icons:** Polaris system from design system; animated if critical.
   - **Call-to-action:** Click-to-seal button with optional hold progress visual.

5. **Accessibility**
   - Keyboard navigation (arrow keys + Tab to buttons).
   - Dark mode support (automatic via theme system).
   - Reduced motion respect (`.animation(..., value: ...)` checks `accessibilityReduceMotionEnabled`).

### Example Skeletal Code

```swift
// Main app entry
@main
struct VaultifyApp: App {
    @AppStorage("hasCompletedOnboarding") var hasCompleted = false
    
    var body: some Scene {
        if !hasCompleted {
            Window("Onboarding", id: "onboarding") {
                MacOnboardingWindow(isComplete: $hasCompleted)
            }
            .windowStyle(.hiddenTitleBar)
        } else {
            WindowGroup {
                MainAppView()
            }
        }
    }
}

// Onboarding window view
struct MacOnboardingWindow: View {
    @Binding var isComplete: Bool
    @State var currentPage = 0
    let pages = [
        OnboardingPage(title: "Welcome to Loox", icon: "lock.fill"),
        OnboardingPage(title: "Keep Secrets Safe", icon: "shield.fill"),
        // ... more pages
    ]
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(gradient: ..., startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            
            // Content
            VStack(spacing: 40) {
                pages[currentPage].view
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale),
                                           removal: .opacity))
                
                // Controls
                HStack {
                    Button("Back") { currentPage = max(0, currentPage - 1) }
                        .disabled(currentPage == 0)
                    Spacer()
                    Text("\(currentPage + 1) / \(pages.count)")
                    Spacer()
                    if currentPage == pages.count - 1 {
                        Button(action: { isComplete = true }) {
                            Text("Start Using Loox")
                        }
                        .buttonStyle(.primary)
                    } else {
                        Button("Next") { currentPage += 1 }
                            .buttonStyle(.primary)
                    }
                }
                .padding()
            }
            .padding()
        }
        .onKeyPress(.rightArrow) { 
            if currentPage < pages.count - 1 { currentPage += 1 }
            return .handled
        }
        .onKeyPress(.leftArrow) { 
            if currentPage > 0 { currentPage -= 1 }
            return .handled
        }
        .onKeyPress(.escape) {
            // Offer skip instead of immediate exit
            showSkipConfirmation = true
            return .handled
        }
    }
}
```

---

## 6. Trade-offs & Constraints

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| **Full-screen vs windowed** | Windowed (sized to screen) | Full-screen conflicts with Stage Manager; windowed still feels immersive. |
| **Scroll vs discrete steps** | Discrete steps (click/arrows) | macOS UX expects actionable pages, not smooth scroll. Matches onboarding intent better. |
| **Animation complexity** | Moderate (fade/scale/gradient) | Complex 3D/parallax animations feel foreign on macOS; focus on clarity. |
| **Keyboard ESC override** | Accept system behavior, add Skip button | Cannot suppress Esc entirely; design around it. |
| **Hold-to-seal on Mac** | Click-to-seal (with optional hold progress) | macOS has no haptic feedback; long-press is less natural. Click + visual ring is clear. |
| **Deferring main window** | Conditional @AppStorage + scene swap | Simple, no AppKit bridging needed. Re-launch overhead is acceptable for first-run. |
| **Multi-display** | Use NSScreen.main, accept primary display | Onboarding is one-time; targeting primary screen is sufficient. |

---

## 7. Adoption Risk & Maturity

**Risk Level:** LOW

- **SwiftUI window management (macOS 15):** Stable API, well-documented.
- **Keyboard navigation (.onKeyPress):** iOS 18+ / macOS 15+, native.
- **Animation patterns:** Core SwiftUI, no experimental features.
- **No third-party dependencies:** Aligns with Vaultify's constraint (native SwiftUI only).

**Community:** Active; examples exist (CinematicOnboardingView-SwiftUI on GitHub, FlineDev window management guides).

---

## 8. Unresolved Questions

1. **Multi-display behavior:** Should onboarding always open on primary screen, or on the screen with focus? Test required.
2. **Stage Manager interaction:** Does full-screen onboarding window work correctly when Stage Manager is enabled? (Presumed yes, but macOS 15 Stage Manager changes may affect.)
3. **AppKit bridge necessity:** Can pure SwiftUI `.frame()` on a Window scene reliably size to full-screen, or does it require NSWindow bridging? (Hybrid approach worth testing.)
4. **Esc key suppression:** If project decides Esc must not exit, is a custom NSResponder override + window-level event intercept acceptable, or does it break accessibility?
5. **Animated video backgrounds:** If future design calls for video hero backgrounds, does SwiftUI Video playback (iOS 16+) exist on macOS 15, or fallback to GIF/animated PNG?
6. **Re-entry after skip:** Should users be able to re-run onboarding from Settings? (Affects AppStorage design.)

---

## 9. Recommendations Summary

**Proceed with discrete-step macOS onboarding window.** Full-screen cinematic takeover is feasible but unnecessary; polished step-by-step onboarding is more authentic to macOS UX and matches Arc/Dia's actual approach (refined workflows, not spectacle).

**Concrete next steps:**
1. Extract iOS beat content into 4–6 macOS pages.
2. Build custom PageView component (since TabView `.page` isn't available).
3. Implement conditional scene in App entry point.
4. Add arrow-key + Skip button navigation.
5. Use existing Vaultify design tokens (gradients, typography, icons).
6. Test on macOS 15 + Stage Manager; handle multi-display edge case.
7. Measure: track "onboarding completed" events via analytics; iterate on content clarity.

---

## Sources

- [Dia Browser: Smooth Onboarding with Skills Walkthrough](https://medium.com/@theo-james/the-hyped-dia-browser-is-out-but-with-a-huge-problem-42aabcc2e723)
- [Arc Help Center: 2024-2026 Release Notes](https://resources.arc.net/hc/en-us/articles/20498293324823-Arc-for-macOS-2024-2026-Release-Notes)
- [SwiftUI Full-Screen Cover/Overlay on macOS](https://levelup.gitconnected.com/swiftui-macos-full-screen-cover-overlay-7a5bd886d795)
- [Window Management with SwiftUI 4 (FlineDev)](https://www.fline.dev/window-management-on-macos-with-swiftui-4/)
- [Translucent Overlay Windows on macOS (Medium)](https://gaitatzis.medium.com/create-a-translucent-overlay-window-on-macos-in-swift-67d5e000ce90)
- [CinematicOnboardingView-SwiftUI (GitHub)](https://github.com/adamlyttleapps/CinematicOnboardingView-SwiftUI)
- [Raycast: Celebrated macOS Onboarding Walkthrough](https://www.raycast.com/changelog/macos/8)
- [HackingWithSwift: TabView Paging](https://www.hackingwithswift.com/quick-start/swiftui/how-to-create-scrolling-pages-of-content-using-tabviewstyle)
- [Apple Forums: macOS WindowGroup Management](https://developer.apple.com/forums/thread/809046)
- [Haptics Development Guide (Medium)](https://medium.com/geekculture/developer-guide-about-haptics-on-apple-platforms-e0f6b68938d)
