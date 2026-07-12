// Node-runnable tests for the inline menu's eligibility + credential
// suppression rules (dev-only, never shipped). Executes the REAL
// inline-menu.js (with the real fill-engine visibility gauntlet) against
// stub elements. The load-bearing assertions encode the ABSOLUTE RULE:
// the menu never renders for credential fields or plain login forms —
// the native Credential Provider / QuickType owns those.
// Run: node VaultifySafari/DevFixtures/inline-menu-node-tests.mjs
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert/strict";

const here = dirname(fileURLToPath(import.meta.url));
const resources = join(here, "..", "Resources");

// --- Minimal browser-environment stubs --------------------------------------

globalThis.location = { protocol: "https:" };
const windowStub = {
  scrollX: 0,
  scrollY: 0,
  innerWidth: 390,
  innerHeight: 800,
  addEventListener: () => {},
  removeEventListener: () => {},
};
windowStub.top = windowStub;
globalThis.window = windowStub;
globalThis.document = {
  addEventListener: () => {},
  removeEventListener: () => {},
  activeElement: null,
  querySelectorAll: () => [],
};
globalThis.browser = {
  i18n: { getMessage: (key) => key },
  runtime: { sendMessage: async () => null },
};
globalThis.getComputedStyle = (el) => el.computedStyle;
globalThis.Event = class {
  constructor(type, options) {
    this.type = type;
    this.bubbles = Boolean(options && options.bubbles);
  }
};
globalThis.HTMLInputElement = { prototype: {} };
globalThis.HTMLTextAreaElement = { prototype: {} };

// Evaluate the REAL scripts the way the content-script world would.
for (const file of ["fill-engine.js", "inline-menu.js"]) {
  new Function(readFileSync(join(resources, file), "utf8"))();
}
const { eligibleTarget, isCredentialish } = globalThis.LooxInlineMenu;
assert.equal(typeof eligibleTarget, "function", "eligibleTarget must be exported");

// --- Stub element / scope factories ------------------------------------------

function makeElement(overrides = {}) {
  const attributes = overrides.attributes || {};
  const rect = { left: 10, top: 10, width: 150, height: 20 };
  rect.right = rect.left + rect.width;
  rect.bottom = rect.top + rect.height;
  return {
    tagName: "INPUT",
    type: "text",
    form: null,
    disabled: false,
    readOnly: false,
    isConnected: true,
    parentElement: null,
    offsetParent: {},
    computedStyle: {
      display: "block", visibility: "visible", opacity: "1", position: "static",
    },
    getBoundingClientRect: () => rect,
    getAttribute: (name) => (name in attributes ? attributes[name] : ""),
    ...Object.fromEntries(Object.entries(overrides).filter(([k]) => k !== "attributes")),
  };
}

// A form (or document) scope holding the given password inputs.
function makeScope(passwordFields = []) {
  return {
    querySelectorAll: (selector) =>
      (selector === 'input[type="password"]' ? passwordFields : []),
  };
}

function visiblePassword() {
  return makeElement({ type: "password" });
}

function hiddenPassword() {
  return makeElement({
    type: "password",
    computedStyle: { display: "none", visibility: "visible", opacity: "1", position: "static" },
    offsetParent: null,
  });
}

// Dependency bundle: classifier verdicts and the signup-scan result are
// injected so each case controls the page shape precisely (the classifier
// and detector have their own harnesses).
function deps(entries, scanResult, doc) {
  return {
    pageScan: { classify: () => entries },
    scanner: { scan: () => scanResult },
    doc: doc || makeScope([]),
  };
}

const NONE = { pageType: "none", form: null };
const LOGIN = { pageType: "login", form: null };

// --- Credential belts: password/username shapes never get a menu -------------

{
  const password = makeElement({ type: "password" });
  assert.equal(isCredentialish(password), true);
  assert.equal(
    eligibleTarget(password, deps(
      [{ element: password, key: "email", category: "identity", tier: 1 }], NONE)),
    null,
    "a password input must never anchor the menu even with a classifier entry");
}

{
  const username = makeElement({ attributes: { autocomplete: "username" } });
  assert.equal(isCredentialish(username), true);
  assert.equal(
    eligibleTarget(username, deps(
      [{ element: username, key: "email", category: "identity", tier: 1 }], NONE)),
    null,
    "autocomplete=username must never anchor the menu");
}

{
  const otp = makeElement({ attributes: { autocomplete: "one-time-code" } });
  assert.equal(isCredentialish(otp), true);
}

// --- Login form suppression: the QuickType-owned surface ----------------------

{
  const form = makeScope([visiblePassword()]);
  const email = makeElement({ type: "email", form });
  const verdict = eligibleTarget(email, deps(
    [{ element: email, key: "email", category: "identity", tier: 2 }], LOGIN));
  assert.equal(verdict, null,
               "an email field inside a login form must show NO inline menu");
}

// Formless login region: page-level visible password, page not actionable.
{
  const email = makeElement({ type: "email", form: null });
  const doc = makeScope([visiblePassword()]);
  const verdict = eligibleTarget(email, deps(
    [{ element: email, key: "email", category: "identity", tier: 2 }], NONE, doc));
  assert.equal(verdict, null,
               "a formless page region with a visible password field is suppressed");
}

// --- Signup exception: account creation keeps identity fill ------------------

{
  const form = makeScope([visiblePassword()]);
  const email = makeElement({ type: "email", form });
  const scan = { pageType: "signup", form };
  const verdict = eligibleTarget(email, deps(
    [{ element: email, key: "email", category: "identity", tier: 2 }], scan));
  assert.deepEqual(verdict, { key: "email", category: "identity" },
                   "identity fields on a detected signup form keep the menu");
}

// A login form NEXT TO a signup form keeps its suppression: the account
// creation evidence belongs to the other form.
{
  const loginForm = makeScope([visiblePassword()]);
  const signupForm = makeScope([visiblePassword()]);
  const email = makeElement({ type: "email", form: loginForm });
  const scan = { pageType: "signup", form: signupForm };
  const verdict = eligibleTarget(email, deps(
    [{ element: email, key: "email", category: "identity", tier: 2 }], scan));
  assert.equal(verdict, null,
               "a login form next to a signup form stays suppressed");
}

// Hidden honeypot passwords do not turn a plain form into a credential form.
{
  const form = makeScope([hiddenPassword()]);
  const email = makeElement({ type: "email", form });
  const verdict = eligibleTarget(email, deps(
    [{ element: email, key: "email", category: "identity", tier: 2 }], NONE));
  assert.deepEqual(verdict, { key: "email", category: "identity" },
                   "an invisible honeypot password must not suppress the menu");
}

// --- Card fields on a checkout (no passwords anywhere) ------------------------

{
  const pan = makeElement({ attributes: { autocomplete: "cc-number" } });
  const verdict = eligibleTarget(pan, deps(
    [{ element: pan, key: "ccNumber", category: "card", tier: 1 }], NONE));
  assert.deepEqual(verdict, { key: "ccNumber", category: "card" },
                   "a tier-1 card field anchors the menu");
}

// --- Evidence floor: keyword-only (tier 3+) never anchors ---------------------

{
  const fuzzy = makeElement({});
  assert.equal(
    eligibleTarget(fuzzy, deps(
      [{ element: fuzzy, key: "address", category: "identity", tier: 3 }], NONE)),
    null,
    "tier-3 keyword-only evidence must not anchor the menu");
}

// Unclassified elements never anchor.
{
  const stray = makeElement({});
  assert.equal(eligibleTarget(stray, deps([], NONE)), null);
}

console.log("inline-menu node tests: all assertions passed");
