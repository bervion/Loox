# Verification evidence

`evidence-index.yaml` is the machine-readable registry. Artifact files belong in
`quality/verification/evidence/<task-id>/` and must be created by the verification
run, never copied from personal device data.

Imported ledger rows intentionally start as `known`. A row becomes `verified` only
when its `evidence_ids` point to a fresh registry entry for an exact `tested_sha` and
`tested_tree`, with an independent verifier and completed redaction metadata. A canonical
`tested_input_digest` includes app/test/workflow inputs plus ledger semantics while ignoring
only evidence artifacts and status/link fields; any meaningful drift invalidates the receipt.

Evidence may contain synthetic test values, screenshots, `.xcresult` summaries,
snapshot diffs and Maestro reports. It must not contain real item names, passwords,
recovery keys, website history, signing material, tokens or raw production logs.
