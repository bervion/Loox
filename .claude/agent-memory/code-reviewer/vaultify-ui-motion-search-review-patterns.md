---
name: vaultify-ui-motion-search-review-patterns
description: Bug classes from Design DNA Controlled Reveal review (260710) — normalize-pipeline mismatch, operator keyword swallow, overlay bypassing access-gate subtree, task(id:) stale-input
metadata:
  type: project
---

Bug classes found in the Loox Design DNA "Controlled Reveal" UI pass review (branch feat/design-dna-controlled-reveal, 260711):

1. **Normalize-pipeline mismatch (HIGH class)**: `SearchOperators.normalize` diacritic-folds the WHOLE query (operators + free text), but downstream `VaultRepository.search` matches tokens against `VaultItem.searchText` which is only lowercased (VaultItem.swift:100-105). Folded VI tokens ("ngân"→"ngan") never match unfolded haystack → VI search regression. **How to apply:** whenever a tokenizer/normalizer is inserted upstream of an existing matcher, verify both sides use the SAME normalization (empirically confirmed with Foundation folding test). Unit tests on parse() alone don't catch it — need pipeline-level test (folded token vs real searchText).

2. **Operator keyword swallow**: bare common words ("security", "recovery", "code", "note", "card", "mã") consumed as operators by `SearchOperators.parse`, so plain-text queries that used to match item titles now filter by category/signal instead → zero results. The code's own doc-comment claims "operators never accidentally swallow a real search term" but recognized keywords always swallow. Watch for grammar features that reinterpret previously-literal input.

3. **Overlay bypassing gated subtree**: ItemDetailScreen's `BottomCopyPasswordCluster` overlay reads `item.passwordField?.value` at screen level, OUTSIDE `SharedAccessGateView` (INV-01 online gate for shared projections). Only accidentally safe: its `visible` flag depends on a GeometryReader preference emitted INSIDE the gate's content. Check every new screen-level overlay/toolbar action that touches secret values for shared-projection paths (`item.sharedOrigin != nil`). Verified `markUsed` no-ops for shared ids (guards on `store.record(id:)` — no upsert fallback).

4. **`.task(id:)` stale-input**: GlyphResolveText keys its task on `isRevealed` only; if `text` changes while revealed, `resolvedCount` goes stale (longer value → permanent trailing mask dots). Key task on ALL inputs the async work reads.

5. Verified idioms (safe, reusable): `withTransaction(disablesAnimations: true)` DOES suppress `.animation(_:value:)` modifiers (Apple-documented) — RootView immediate-lock path relies on it; `ClipboardService.copy` fires `Haptics.success()` internally, so any new copy-feedback view adding its own haptic double-buzzes; localization sweep verification recipe = diff xcstrings added/removed keys, cross-grep removed keys against all Swift sources, scan catalog for missing `vi`.
