# Researcher 04 — Onboarding Benchmarks + Password-Habit Stats

Scope: A) narrative/cinematic mobile onboarding benchmarks (problem-before-product); B) citable stats on insecure password habits for story copy. Date: 2026-08-05.

---

## A. BENCHMARKS

### A1. Password managers (competitive baseline — none sells the problem)

| App | Emotional job | Structure | Lesson to steal |
|---|---|---|---|
| 1Password | Reassure "your secrets are safe" — security-first, trust via ceremony | Step-by-step setup guide; extra security steps (Secret Key) slow beginners; utility-first, no story | Trust rituals work, but Secret Key = cautionary tale: friction w/o narrative payoff overwhelms. Vaultify can out-story all of them |
| Dashlane | Friendly competence; "you can do this" | Balanced: quick setup + interactive tutorial exploring features; beginner-first | Interactive tutorial > static slides; teach by doing |
| Bitwarden | Neutral/utilitarian; speed | Minimalist, near-zero onboarding; user learns by exploration | What NOT to do for consumer story intro; fine for techies only |
| Proton Pass | Calm, frictionless privacy | One screen at a time, clear prompts; immediately pushes 2 setup actions: enable autofill + biometrics | "One idea per screen" + end story with a concrete setup action (autofill/Face ID), not a feature list |

Verdict: category-wide gap — all four onboard the TOOL, none dramatizes the PROBLEM. Story-driven pain-first intro is genuinely differentiated for a password manager.

Sources: designmonks.co best-password-manager-app-designs (2025); security.org / cybernews Proton Pass hands-on reviews (2025-26).

### A2. Story-onboarding masters

**Duolingo** — emotional job: make you feel capable in 60s.
- Structure: ~8-10 beats: mascot welcome → motivation Q ("why are you learning?") → goal commitment → daily-time pick → instant lesson BEFORE signup (delayed registration). Progress bar throughout. Mostly non-skippable but each beat is 1 tap.
- Mechanisms: completion bias — committing to a mission pre-signup raises stickiness; personalization Qs double as segmentation.
- Steal: let user DO the core thing (save 1 password) before any account/paywall ask; ask "why are you here" and echo it back later.
- Sources: goodux.appcues.com/blog/duolingo-user-onboarding; userguiding.com/blog/duolingo-onboarding-ux; theappfuel.com casestudy.

**Headspace** — emotional job: calm, inward reflection; app models its own value during onboarding.
- Structure: 3 questions (~1 min) → personalized routine; SSO to cut friction; breathing moment = product demo inside onboarding.
- Steal: onboarding should FEEL like the product (for Vaultify: quiet, private, unhurried = the vault feeling); ask few Qs but make each about the user's motivation (intrinsic > feature tour).
- Source: goodux.appcues.com/blog/headspaces-mindful-onboarding-sequence.

**Opal (screen time)** — the best pain-first template found.
- Structure: ~12 beats: usage-habit quiz → relatable "X% of users share this habit" social proof → personalized "Focus Report" quantifying YEARS of life lost to phone → years you could SAVE → fist-bump commitment animation → soft paywall.
- Emotional arc: mirror (that's me) → dread (quantified loss) → hope (quantified gain) → commitment ritual → ask.
- Steal: quantify the user's personal exposure ("N accounts, M reused passwords ≈ your blast radius"); a physical commitment gesture; show "you're not alone" stats mid-flow (this is exactly where section B stats belong).
- Sources: mobbin.com Opal iOS flow; screensdesign.com/showcase/opal-screen-time-control; pageflows.com/ios/products/opal.

**Noom** — emotional job: feel understood before being sold.
- Structure: famously long (113-screen web funnel) yet doesn't feel long: every answer gets an empathetic response; vulnerable input (weight) → immediate supportive feedback; education woven into questions; price only AFTER heavy time/emotion investment (sunk-cost + consistency).
- Steal: reciprocity — every question the user answers must give something back (insight, stat, reassurance). "Length isn't the enemy; emptiness is."
- Sources: revenuecat.com/blog/growth/web-to-app-onboarding-funnel; growthwaves.io "113-screen onboarding"; thebehavioralscientist.com Noom critique.

**Arc / Arc Search** — emotional job: delight + being set free early.
- Structure: short; visually rich welcome, import from old browser, personalize, then release into product sooner than expected; easter-egg details (fidget-spinner logo).
- Steal: end the story EARLY — get out of the way once emotion lands; import moment (existing passwords from Keychain/browser) as the bridge from story to value.
- Sources: saasui.design/pattern/onboarding/arc-browser; Mike Bal LinkedIn onboarding breakdown (2024).

**Copilot Money** — ADA finalist 2024 (design polish, motion, native feel). No public teardown of a story intro found; its reputation = craft/animation quality bar, not narrative. Steal: ADA-level motion polish on native SwiftUI is itself the differentiator Apple rewards.
- Sources: apple.com/newsroom 2024 ADA winners; techcrunch.com ADA finalists 2024.

**Riverside** — weak benchmark for this task: mobile onboarding is guest-link/no-account friction removal, not narrative. Skip as a model.

**Blinkist (growth.design case study)** — canonical psychology reference.
- "Psych framework": every beat adds or drains psychological energy. Opens with relatable pain (no time to read) before product. ~35-beat narrative.
- Named principles: build trust before asking for data (their iOS tracking prompt = energy drain); progressive disclosure; endowment effect; every personalization Q creates an obligation to visibly use the answer.
- Steal: audit each story beat for Psych +/-; never ask a permission (notifications/analytics) mid-story.
- Source: growth.design/case-studies/blinkist-user-onboarding.

### A3. Evidence: pain-first / story onboarding → activation & retention

- Reforge 3 activation moments: Setup → Aha → Habit; biggest failure = stopping at Setup. Frame story intro as the emotional on-ramp to Aha (first saved password + first autofill), not a feature tour. (reforge.com retention/activation series)
- Aha within 5 min ↔ ~40% higher 30-day retention (cited to Reforge research by growthpigeon.com — secondary source, treat as directional, verify before quoting publicly).
- Slack 2,000-messages / Facebook 7-friends thresholds: activation metrics correlate with retention; define Vaultify's ("N items saved + autofill enabled"?). (reforge.com, chameleon.io)
- Completion bias: pre-signup mission commitment measurably raises stickiness (GoodUX Duolingo analysis).
- Onboarding personalization survey = "visible promise": products must echo answers back or trust drops (Reforge; growth.design Blinkist).
- Opal/Noom pattern (pain quantification then hope) is the practiced industry standard for pain-first; no public RCT numbers, but both are top-grossing in category — evidence is revealed-preference, not published A/B.

Design implications for Vaultify intro: 5-8 beats; skippable after beat 1 (App Review + respect); one idea per screen; 1-2 stats max as social proof mid-arc; end on action (save first password / enable AutoFill / Face ID), not signup (no account anyway — offline is the twist ending); copy rules: no "!", no em-dash, design for longest VI string.

---

## B. STATS FOR STORY COPY (exact figure + source + year)

### Reuse
- 72% of Gen Z reuse passwords vs 42% of Boomers; 59% of Gen Z reuse an OLD password even when updating an account after that company was breached — Bitwarden World Password Day survey, 2,000+ employed adults, 6 countries (US/UK/AU/DE/FR/JP), 2025. bitwarden.com/blog/a-closer-look-at-password-statistics
- 25% of people globally reuse one password across 11-20+ accounts (31% in US); 32% reuse across 5-10 sites; 48% frequently reuse passwords at work — Bitwarden WPD survey, 2,400 adults, 6 countries, 2024. bitwarden.com/resources/world-password-day-2024
- 62% almost always/mostly reuse a password or variation, while 89% KNOW it's risky — LastPass Psychology of Passwords, 2022. lastpass.com/resources/reports/psychology-of-passwords
- 52% reuse one password on multiple accounts; 13% use ONE password for everything (only 35% unique everywhere) — Google/Harris Poll, 3,000 US adults, 2019 (old but the most-cited figure). services.google.com/fh/files/blogs/google_security_infographic.pdf

### Storage: memory / paper / notes / browser
- 54% rely on memory; 33% on pen and paper — Bitwarden WPD survey 2024 (same as above).
- 41% of US adults always/often WRITE DOWN passwords; 69% feel overwhelmed by how many passwords they track; only 32% use a password manager (49% among 18-29) — Pew Research Center, Oct 2023. pewresearch.org/internet/2023/10/18/how-americans-protect-their-online-data
- 25% save passwords in UNENCRYPTED files or notes on their devices; 41% still rely on memory; browser-based saving is default for ~40-50% — NordPass/Nord Security survey, 7,861 respondents, 8 countries, 2026. nordpass.com/blog/password-decline-research
- 35% memory-only; 17% paper/sticky note; 34% dedicated manager — AllAboutCookies survey, 1,000 US adults, 2026. allaboutcookies.org/password-users-behavior-survey
- Workplace flavor (older, 2021, US n=1,000): 57% keep work passwords on sticky notes (67% have lost one); 62% in a notebook kept next to the device — Keeper Workplace Password Malpractice Report. keepersecurity.com/resources/workplace-password-habits

### Sharing over chat / SMS / email
- 62% of US employees have shared a work password over TEXT or EMAIL — Keeper Workplace Password Malpractice Report, 2021.
- ~32% of respondents share passwords through insecure channels — Bitwarden WPD survey, 2024.
- Gen Z sharing: 25% via text message, 19% via screenshots, 19% verbally — cited in brightdefense.com password statistics roundup (from Bitwarden/EarthWeb data, 2024-25; verify primary before print).
- 51% of US adults share at least one password type (42% video streaming, 8% bank) — AllAboutCookies, 2026.

### Breach / attack scale
- Stolen credentials involved in 32% of ALL breaches; 22% of breaches BEGAN with credential abuse (the no.1 initial vector, ahead of phishing at 16%); 88% of basic web-app attacks used stolen creds; credential stuffing = 19% of daily auth attempts at a major SSO provider; 54% of ransomware victims had creds already in infostealer logs — Verizon DBIR 2025. verizon.com/business/resources/reports/2025-dbir-data-breach-investigations-report.pdf
- Microsoft blocked 7,000 password attacks PER SECOND (up from 6,000/s prior year); password attacks = 99%+ of 600M daily identity attacks; MFA users see 80% fewer compromises — Microsoft Digital Defense Report, 2024. microsoft.com/en-us/security/security-insider/threat-landscape/microsoft-digital-defense-report-2024
- 29% of US adults had identity or login credentials stolen in the past 12 months; password reusers were significantly more likely to be breached; 36% of US adults (~94M) use a password manager; 75%+ of non-users open to one — Security.org annual password manager report, 2024. security.org/digital-safety/password-manager-annual-report
- 55% have ABANDONED an account rather than face a password reset — Bitwarden WPD survey, 2025 (great relatable hook, low fear).
- 36% put personal info that is publicly visible on social media into passwords — Bitwarden WPD, 2024.

### Best copy-ready pairings (pain → hope arc)
1. Mirror beat: "You have more passwords than you can hold" → Pew 2023: 69% overwhelmed; 41% write them down.
2. Habit beat: reuse → Google/Harris 13% one-password-for-everything, or Bitwarden 2024 25% reuse across 11-20+ accounts.
3. Stakes beat: → DBIR 2025 (stolen creds in 32% of breaches) + Microsoft 7,000 attacks/sec.
4. Relatable-pain beat (lighter): Bitwarden 2025: 55% abandoned an account to dodge a reset.
5. VI localization note: all stats are global/US surveys; no Vietnam-specific figures found — phrase as "worldwide" in VI copy, not "at Vietnam".

---

## Unresolved questions
1. Reforge "aha in 5 min = +40% 30-day retention" is a secondary citation (growthpigeon.com) — could not verify against a primary Reforge artifact; do not print without checking.
2. Gen Z sharing-channel split (25% text / 19% screenshots) comes from stats roundups; primary source (Bitwarden 2024 full report PDF) not fetched (403 on press mirrors) — verify before quoting in-app.
3. No Vietnam/Japan-specific password-habit stats found (Bitwarden includes JP in sample but no JP breakouts fetched) — matters for VI/JA story copy credibility.
4. Copilot Money and Riverside yielded no substantive story-onboarding teardowns; consider replacing with Noom/Opal as the named benchmarks in the plan.
5. Mobbin/ScreensDesign have full screen-by-screen recordings of Opal + 1Password behind login — worth a manual look if exact beat counts are needed.
6. Bitwarden 2025 survey full report (memory/pen-paper 2025 refresh) not retrieved; 54%/33% figures are from the 2024 wave.
