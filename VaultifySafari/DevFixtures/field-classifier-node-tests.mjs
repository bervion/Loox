// Node-runnable unit tests for the pure classifier (dev-only, never shipped).
// Run: node VaultifySafari/DevFixtures/field-classifier-node-tests.mjs
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert/strict";

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(
  join(here, "..", "Resources", "field-classifier.js"), "utf8");
// The classifier registers itself on globalThis (browser pattern); evaluate
// it here the same way the content script environment would.
new Function(source)();
const { classify, summarize, normalize } = globalThis.LooxFieldClassifier;

function d(overrides) {
  return {
    id: overrides.id ?? 1,
    tag: "input", type: "text", inputmode: "", autocomplete: "",
    name: "", elementId: "", placeholder: "", label: "", ariaLabel: "",
    maxLength: null, form: 0,
    ...overrides,
  };
}

function keyOf(descriptor) {
  const result = classify([descriptor]);
  return result.length ? result[0].key : null;
}

function tierOf(descriptor) {
  const result = classify([descriptor]);
  return result.length ? result[0].tier : null;
}

// --- normalize ---
assert.equal(normalize("Số Thẻ"), "so the");
assert.equal(normalize("Địa chỉ"), "dia chi");
assert.equal(normalize("Điện Thoại"), "dien thoai");

// --- Tier 1: autocomplete is authoritative ---
assert.equal(keyOf(d({ autocomplete: "cc-number", name: "random_x1" })), "ccNumber");
assert.equal(tierOf(d({ autocomplete: "cc-number" })), 1);
assert.equal(keyOf(d({ autocomplete: "shipping street-address" })), "address");
assert.equal(keyOf(d({ autocomplete: "given-name" })), "givenName");
assert.equal(keyOf(d({ autocomplete: "section-blue billing cc-exp-month", tag: "select" })), "ccExpMonth");
assert.equal(keyOf(d({ autocomplete: "off", name: "email" })), "email", "autocomplete=off falls through to lower tiers");

// --- Tier 2: input type / inputmode ---
assert.equal(keyOf(d({ type: "email" })), "email");
assert.equal(tierOf(d({ type: "email" })), 2);
assert.equal(keyOf(d({ type: "tel" })), "phone");
assert.equal(keyOf(d({ inputmode: "email" })), "email");

// --- Tier 3: EN keywords ---
assert.equal(keyOf(d({ name: "card_number" })), "ccNumber");
assert.equal(keyOf(d({ placeholder: "Name on card" })), "ccName");
assert.equal(keyOf(d({ label: "Security code" })), "ccCsc");
assert.equal(keyOf(d({ name: "cvv" })), "ccCsc");
assert.equal(keyOf(d({ name: "exp-date" })), "ccExp");
assert.equal(keyOf(d({ label: "First name" })), "givenName");
assert.equal(keyOf(d({ label: "Last name" })), "familyName");
assert.equal(keyOf(d({ label: "Email address" })), "email", "email wins over address");
assert.equal(keyOf(d({ label: "Street address" })), "address");
assert.equal(keyOf(d({ label: "Full name" })), "fullName");
assert.equal(keyOf(d({ name: "mobile" })), "phone");

// --- Tier 3: VI keywords (diacritics and stripped forms) ---
assert.equal(keyOf(d({ label: "Họ và tên" })), "fullName");
assert.equal(keyOf(d({ name: "ho-ten" })), "fullName");
assert.equal(keyOf(d({ label: "Số thẻ" })), "ccNumber");
assert.equal(keyOf(d({ label: "Chủ thẻ" })), "ccName");
assert.equal(keyOf(d({ label: "Mã bảo mật" })), "ccCsc");
assert.equal(keyOf(d({ label: "Ngày hết hạn" })), "ccExp");
assert.equal(keyOf(d({ label: "Số điện thoại" })), "phone");
assert.equal(keyOf(d({ label: "Địa chỉ giao hàng" })), "address");
assert.equal(keyOf(d({ label: "Họ" })), "familyName", "single VI token matches whole tokens only");
assert.equal(keyOf(d({ label: "Tên" })), "givenName");

// --- Exclusions: never misfire on username/search/password fields ---
assert.equal(keyOf(d({ label: "Tên đăng nhập" })), null, "username, not a given name");
assert.equal(keyOf(d({ name: "username" })), null);
assert.equal(keyOf(d({ name: "search", placeholder: "Search addresses" })), null);
assert.equal(keyOf(d({ label: "Tài khoản email" })), null, "account field excluded");
assert.equal(keyOf(d({ name: "phone" })), "phone", "sanity: phone itself still matches");
assert.equal(keyOf(d({ type: "hidden", autocomplete: "cc-number" })), null, "hidden inputs are never targets");
assert.equal(keyOf(d({ type: "password", name: "email" })), null, "password inputs are never targets");

// --- Tag constraints ---
assert.equal(keyOf(d({ tag: "textarea", label: "Địa chỉ" })), "address");
assert.equal(keyOf(d({ tag: "textarea", autocomplete: "cc-number" })), null, "PAN never targets a textarea");
assert.equal(keyOf(d({ tag: "select", name: "exp_month" })), "ccExpMonth");
assert.equal(keyOf(d({ tag: "select", name: "email" })), null, "selects only carry expiry parts");

// --- Tier 4: form context upgrades generic name to cardholder ---
{
  const results = classify([
    d({ id: 1, name: "name", placeholder: "Full name", form: 2 }),
    d({ id: 2, autocomplete: "cc-number", form: 2 }),
  ]);
  const nameEntry = results.find((r) => r.id === 1);
  assert.equal(nameEntry.key, "ccName");
  assert.equal(nameEntry.category, "card");
  assert.equal(nameEntry.tier, 4);
}
{
  const results = classify([
    d({ id: 1, name: "name", placeholder: "Full name", form: 1 }),
    d({ id: 2, autocomplete: "cc-number", form: 2 }),
  ]);
  assert.equal(results.find((r) => r.id === 1).key, "fullName",
    "different form: no cardholder upgrade");
}

// --- Summary counts ---
{
  const summary = summarize(classify([
    d({ id: 1, autocomplete: "email" }),
    d({ id: 2, autocomplete: "tel" }),
    d({ id: 3, autocomplete: "cc-number" }),
  ]));
  assert.deepEqual(summary, { identity: 2, card: 1 });
}

// --- Descriptors never carry values (API shape guard) ---
{
  const results = classify([d({ id: 9, autocomplete: "cc-number" })]);
  assert.ok(!("value" in results[0]), "classification output must not have a value slot");
}

console.log("field-classifier node tests: all assertions passed");
