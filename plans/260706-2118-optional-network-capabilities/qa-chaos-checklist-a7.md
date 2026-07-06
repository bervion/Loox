# A7 Chaos QA checklist — Optional Network Capabilities

Exit criterion: **Core Vault behavior unchanged in every scenario.**
Automated (✅ unit) vs manual (📱 device w/ Network Link Conditioner / worker env flips).

| # | Scenario | How | Expected |
|---|----------|-----|----------|
| 1 | Cloudflare DNS unreachable | 📱 block api-relay/api DNS | breaker opens after 3 fails; banners "Temporarily unavailable"; vault untouched |
| 2 | relay API 503 (plain) | 📱 / ✅ `testPlainInfrastructure503IsNeverAnOperatorSignal` | infra failure, NOT operator state |
| 3 | link API 503 (plain) | same path (shared parser) | same |
| 4 | relay down, link healthy | 📱 | Private Email banner only; Share Link fine (✅ independence: `testCapabilitiesFailIndependently…`) |
| 5 | link down, relay healthy | 📱 | inverse |
| 6 | both down | 📱 | two independent banners; launch/unlock/AutoFill unaffected |
| 7–9 | manifest primary down / secondary / both | fetch is silent-fail (✅ dormant tests); secondary = future BE mirror | cache → bundled defaults |
| 10 | cached manifest valid | ✅ `applyCached` path | modes applied on relaunch |
| 11 | cached manifest expired | ✅ verifier `.expired` → cache dropped | fallback defaults |
| 12 | invalid signature | ✅ `testRejectsTamper…` | rejected silently |
| 13 | rollback manifest | ✅ `testAcceptAppliesPolicyAndBlocksRollback` | rejected, state unchanged |
| 14 | fully offline | 📱 airplane mode | records visible; "No Internet Connection"; create gated (✅ resolver offline) |
| 15 | network returns | 📱 | reachability flips → availability recovers, no restart (Observable) |
| 16 | breaker half-open succeeds | ✅ `testBreakerOpens…Escalates` | closed, reset |
| 17 | maintenance → active | 📱 flip `PRIVATE_EMAIL_MODE`; probe on screen open | banner clears without restart |
| 18 | disabled → active | 📱 same | same |
| 19 | enabled → retired | 📱 `retired` env | 410 → retired banner + Review affected accounts; records stay |
| 20 | launch during total optional outage | 📱 | launch/unlock normal (no startup fetch — A0 audit) |
| 21 | AutoFill during outage | 📱 | owned fill works (extension: zero capability/network dependency) |
| 22 | vault unlock during outage | 📱 | normal |

Manual matrix runs on a real device once BE flips env vars per scenario (17–19 need
`wrangler` env changes on staging).
