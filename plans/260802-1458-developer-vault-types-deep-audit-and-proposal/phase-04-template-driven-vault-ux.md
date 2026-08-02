---
title: "Phase 4: Template-Driven Vault UX"
status: done
---

# Phase 4: Template-Driven Vault UX

## Outcome

Replace the flat MVP item form with a calm, template-driven experience where every type has a clear
protagonist, progressive disclosure, semantic validation, safe primary actions, and meaningful list/search summaries.

## Requirements

- [ ] Searchable New Item picker: search, at most three deduplicated Recent items, one contextual Import
  action, then stable Common/Developer/Personal/Finance/Files families.
- [ ] Template sections and repeatable groups; screens compose Design System components only.
- [ ] Type-specific summaries/actions with high-risk actions gated and visually subordinate.
- [ ] Custom fields remain available but cannot change the behavior of required semantic fields.
- [ ] Search indexes only explicitly allowlisted decrypted metadata; telemetry never receives secret,
  key material, filename, fingerprint, scope, provider account, or other identifying metadata.
- [ ] Full EN/VI plus existing JA catalog continuity and Design DNA acceptance for longest labels.

## UX Contract

- New Item: search plus recent templates; Import inspects only enough to present candidate templates.
  Ambiguous `.p8`/PEM inputs use a disambiguation sheet explaining detected facts and unknown purpose;
  extension or filename never auto-assigns authority.
- Editor: required core section, advanced section collapsed, links/files in dedicated sections, inline local validation.
- Detail: one primary task per type, derived public metadata first, fixed masks for secrets, explicit reveal/export.
- List: semantic subtitle such as provider/environment, SSH algorithm/fingerprint suffix, host/user, or expiry state.
- Search operators: `type:ssh`, `host:github.com`, `env:production`, `expires:<30d`, with no secret-value indexing.
- Unknown/recovery: distinguish unsupported newer schema, corrupt record, temporary decrypt failure, and
  missing artifact. Conceal every unknown value, keep the raw record read-only, and offer only an
  authenticated encrypted recovery export. Conversion creates a copy and preserves the original.
- Errors: one ranked banner; blocking integrity/size errors versus save-anyway parse warnings; focus the
  first invalid field; explicit retry/cancel/offline/sync-pending/download/unavailable/corrupt states.

## File Inventory

- Refactor `ItemTypePickerSheet.swift`, Items add menus, and item creation routing.
- Refactor `ItemEditorScreen.swift`, `LoginEditorSections.swift`, and field row components into registry-driven sections.
- Refactor `ItemDetailScreen.swift` into shared shell plus type action/summary sections.
- Update vault rows, Home/Search results, filters/operators, empty states, and accessibility labels.
- Add reusable Design System components only where existing tokens/components cannot express the contract.
- Update `Localizable.xcstrings` with EN source and VI translation for every new string and preserve the
  existing JA localization coverage.

## Implementation Steps

1. Build lightweight presentation models from template descriptors; UI never switches over every type.
2. Redesign picker IA and test with legacy eight types plus planned developer types. Keep the native tab shell.
3. Implement semantic section renderer, required-field lock, repeatable groups, validation summary, and advanced disclosure.
   “Required” constrains semantic role/removal, not value/label editing; provide Reset Label.
4. For every template, document protagonist, one primary action, one quiet secondary, overflow actions,
   immediate/contextual/management fields, and destructive flow. Implement a guarded-action sheet for
   copy, export, open provider, and link item. Derived snippets inherit the strictest source sensitivity,
   authorization, clipboard expiry, logging, snapshot, and accessibility policy.
5. Implement generic safe renderer for supported-schema unknown IDs with every unknown value masked.
   Unsupported schema gets a concealed placeholder and encrypted recovery flow without typed field decode.
6. Add type-aware row subtitle and safe search projection. Define exact indexed roles, keep the index in
   decrypted memory only, clear it on lock, fold locale/diacritics intentionally, and give unknown roles
   no index projection. Search never includes secret field values.
7. Run adversarial Design DNA pass on smallest/largest supported iPhone plus shared iPad/Mac safety in
   EN/VI with existing JA continuity, across all accessibility modes.

## Verification Matrix

- Snapshot/interaction: picker search/groups/recent; every built-in editor/detail; unknown type fallback.
- Localization: EN/VI key completeness, existing JA continuity, and VI longest-label truncation at accessibility text sizes.
- Accessibility: masked content announces “Hidden value” without length/content; reveal state changes
  retain focus; long keys are not auto-read; fingerprints have grouped values; validation is field-linked;
  progress/cancel/completion announce; every gesture has a named action; plus 44pt, Dynamic Type,
  contrast, Reduce Motion/Transparency.
- Security: masked fixed geometry does not reveal secret length; screenshots/snapshots contain no fixtures' secrets.
- Performance: picker and 1,000-item search remain responsive; no registry work on every row body recomputation.

## Risks and Mitigations

- Type-specific UX can fragment: one shared shell and action vocabulary, descriptors only select composition.
- Too many picker types create cognitive load: family groups, search, recency, and provider presets rather than core types.
- Generic fallback may invite unsafe editing: unsupported-schema fields remain concealed/read-only;
  only encrypted raw recovery export or copy-conversion that preserves the original is offered.

## Success Criteria

- [ ] First-run and repeat-developer task studies define median/P90 for SSH import, API creation, Git
  link, ASC import, and unknown recovery; type selection target is under 10 seconds.
- [ ] At least 90% of top developer-template items require no manual custom field.
- [ ] Every touched screen passes the Design DNA checklist, EN/VI validation, and current JA continuity.
- [ ] Supported-schema unknown IDs remain generically visible; unsupported schema remains recoverable and safe.
