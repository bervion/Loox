// Node-runnable tests for the fill engine's safety gauntlet (dev-only, never
// shipped). Executes the REAL fill-engine.js against stub elements that
// mirror the traps in hidden-field-exfiltration-trap.html, plus the shapes a
// legitimate checkout produces (below the fold, horizontally scrolled).
// Run: node VaultifySafari/DevFixtures/fill-engine-node-tests.mjs
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert/strict";

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, "..", "Resources", "fill-engine.js"), "utf8");

// --- Minimal browser-environment stubs -------------------------------------

globalThis.location = { protocol: "https:" };
globalThis.window = { scrollX: 0, scrollY: 0 };
globalThis.getComputedStyle = (el) => el.computedStyle;
globalThis.Event = class {
  constructor(type, options) {
    this.type = type;
    this.bubbles = Boolean(options && options.bubbles);
  }
};
// No native value descriptor on the stubs: setNativeValue falls back to a
// plain `el.value =` assignment, which is what the assertions observe.
globalThis.HTMLInputElement = { prototype: {} };
globalThis.HTMLTextAreaElement = { prototype: {} };

// Evaluate the engine exactly the way the content-script world would.
new Function(source)();
const { fillAll } = globalThis.LooxFillEngine;

// --- Stub element factory ----------------------------------------------------

function makeElement(overrides = {}) {
  const rect = {
    left: 10, top: 10, width: 150, height: 20,
    ...(overrides.rect || {}),
  };
  rect.right = rect.right ?? rect.left + rect.width;
  rect.bottom = rect.bottom ?? rect.top + rect.height;
  return {
    tagName: "INPUT",
    type: "text",
    value: "",
    disabled: false,
    readOnly: false,
    isConnected: true,
    maxLength: -1,
    parentElement: null,
    offsetParent: {},
    computedStyle: {
      display: "block", visibility: "visible", opacity: "1", position: "static",
      ...(overrides.computedStyle || {}),
    },
    getBoundingClientRect: () => rect,
    getAttribute: () => "",
    focus: () => {},
    dispatchEvent: () => {},
    ...Object.fromEntries(Object.entries(overrides)
      .filter(([k]) => k !== "rect" && k !== "computedStyle")),
  };
}

// Wraps an element in ancestor divs; opacities[0] is the nearest ancestor.
function wrapInAncestors(el, opacities) {
  let child = el;
  for (const opacity of opacities) {
    const parent = makeElement({
      tagName: "DIV",
      computedStyle: { display: "block", visibility: "visible",
                       opacity: String(opacity), position: "static" },
    });
    child.parentElement = parent;
    child = parent;
  }
  return el;
}

function fillOne(el, key = "email", tier = 1, values = { email: "user@example.com" }) {
  const report = fillAll([{ id: 1, key, tier, element: el }], values);
  return report[0];
}

// --- Baseline: a visible, editable field fills -------------------------------

{
  const el = makeElement();
  const result = fillOne(el);
  assert.equal(result.status, "filled");
  assert.equal(el.value, "user@example.com");
}

// --- Trap fixture shapes: every one must be rejected as notVisible -----------

// offscreen_pan: position:absolute; left:-9999px (the fixture's named trap).
{
  const el = makeElement({ rect: { left: -9999, top: 10 } });
  const result = fillOne(el, "ccNumber", 1, { ccNumber: "4111111111111111" });
  assert.equal(result.status, "skipped", "offscreen_pan must not fill");
  assert.equal(result.reason, "notVisible");
  assert.equal(el.value, "");
}

// offscreen_top_pan: parked entirely above the document start.
{
  const el = makeElement({ rect: { left: 10, top: -9999 } });
  const result = fillOne(el, "ccNumber", 1, { ccNumber: "4111111111111111" });
  assert.equal(result.status, "skipped", "above-document field must not fill");
  assert.equal(result.reason, "notVisible");
}

// fixed_offscreen_pan: position:fixed pins to the viewport; off-viewport top
// is never visible regardless of scroll.
{
  const el = makeElement({
    rect: { left: 10, top: -9999 },
    computedStyle: { position: "fixed" },
    offsetParent: null,
  });
  globalThis.window = { scrollX: 0, scrollY: 20000 };
  const result = fillOne(el, "ccNumber", 1, { ccNumber: "4111111111111111" });
  globalThis.window = { scrollX: 0, scrollY: 0 };
  assert.equal(result.status, "skipped", "fixed off-viewport field must not fill");
  assert.equal(result.reason, "notVisible");
}

// ghost_email: direct opacity:0 ancestor (child's own computed opacity is 1).
{
  const el = wrapInAncestors(makeElement(), [0]);
  const result = fillOne(el);
  assert.equal(result.status, "skipped", "opacity-0 ancestor must not fill");
  assert.equal(result.reason, "notVisible");
  assert.equal(el.value, "");
}

// deep_ghost_pan: near-zero opacity ancestor several levels up.
{
  const el = wrapInAncestors(makeElement(), [1, 1, 0.01]);
  const result = fillOne(el, "ccNumber", 1, { ccNumber: "4111111111111111" });
  assert.equal(result.status, "skipped", "near-zero deep ancestor must not fill");
  assert.equal(result.reason, "notVisible");
}

// Own-element near-zero opacity (pre-existing check still holds).
{
  const el = makeElement({ computedStyle: { opacity: "0.05" } });
  assert.equal(fillOne(el).reason, "notVisible");
}

// display:none and 1x1 shrink traps (pre-existing checks still hold).
{
  const el = makeElement({ computedStyle: { display: "none" }, offsetParent: null });
  assert.equal(fillOne(el).reason, "notVisible");
}
{
  const el = makeElement({ rect: { width: 1, height: 1 } });
  assert.equal(fillOne(el).reason, "notVisible");
}

// --- Legitimate shapes: the off-screen guard must NOT reject these -----------

// Below the fold: positive document coordinates far beyond the viewport.
{
  const el = makeElement({ rect: { left: 10, top: 5000 } });
  const result = fillOne(el);
  assert.equal(result.status, "filled", "below-the-fold field must still fill");
}

// Scrolled document: viewport coords are negative but document coords are
// positive (user scrolled past the field). Must still fill.
{
  const el = makeElement({ rect: { left: 10, top: -400 } });
  globalThis.window = { scrollX: 0, scrollY: 600 };
  const result = fillOne(el);
  globalThis.window = { scrollX: 0, scrollY: 0 };
  assert.equal(result.status, "filled", "scrolled-past field must still fill");
}

// Horizontally scrolled document: same rule on the x axis.
{
  const el = makeElement({ rect: { left: -4930, top: 10 } });
  globalThis.window = { scrollX: 5000, scrollY: 0 };
  const result = fillOne(el);
  globalThis.window = { scrollX: 0, scrollY: 0 };
  assert.equal(result.status, "filled", "horizontally scrolled field must still fill");
}

// Visible position:fixed field (e.g. a sticky checkout bar) still fills.
{
  const el = makeElement({
    computedStyle: { position: "fixed" },
    offsetParent: null,
  });
  assert.equal(fillOne(el).status, "filled", "visible fixed field must still fill");
}

// checkVisibility layer: exact-zero opacity beyond the manual walk's depth.
{
  const el = wrapInAncestors(makeElement(), [1, 1, 1, 1, 1, 1, 1, 1, 1, 0]);
  el.checkVisibility = () => false; // what a real engine reports for this chain
  const result = fillOne(el);
  assert.equal(result.status, "skipped", "checkVisibility=false must not fill");
  assert.equal(result.reason, "notVisible");
}

// Exported isVisible (shared with the signup detector's honeypot filter):
// the same gauntlet answers directly, so a hidden password honeypot reads
// as not visible while a normal field reads as visible.
{
  const { isVisible } = globalThis.LooxFillEngine;
  assert.equal(typeof isVisible, "function", "isVisible must stay exported");
  const honeypot = makeElement({
    type: "password",
    computedStyle: { display: "none" },
    offsetParent: null,
  });
  assert.equal(isVisible(honeypot), false, "display:none honeypot is not visible");
  assert.equal(isVisible(makeElement({ type: "password" })), true);
}

// --- ccFrameOriginAllowed: the in-frame half of the iframe CC gate ------------

{
  const { ccFrameOriginAllowed } = globalThis.LooxFillEngine;
  assert.equal(typeof ccFrameOriginAllowed, "function",
               "ccFrameOriginAllowed must stay exported");

  // Allowlisted payment-processor origins pass.
  assert.equal(ccFrameOriginAllowed("https://js.stripe.com"), true);
  assert.equal(ccFrameOriginAllowed("https://checkout.stripe.com"), true);
  assert.equal(ccFrameOriginAllowed("https://pay.google.com"), true);
  // Host comparison is case-insensitive (URL lowercases the hostname).
  assert.equal(ccFrameOriginAllowed("https://JS.STRIPE.COM"), true);

  // Everything else is refused: off-list hosts, scheme downgrades,
  // non-default ports, lookalike subdomains, subdomain wildcards, garbage.
  assert.equal(ccFrameOriginAllowed("https://evil.com"), false);
  assert.equal(ccFrameOriginAllowed("http://js.stripe.com"), false);
  assert.equal(ccFrameOriginAllowed("https://js.stripe.com:8443"), false);
  assert.equal(ccFrameOriginAllowed("https://js.stripe.com.evil.com"), false);
  assert.equal(ccFrameOriginAllowed("https://sub.js.stripe.com"), false);
  assert.equal(ccFrameOriginAllowed("https://stripe.com"), false);
  assert.equal(ccFrameOriginAllowed("not a url"), false);
  assert.equal(ccFrameOriginAllowed(""), false);
  assert.equal(ccFrameOriginAllowed(null), false);
  assert.equal(ccFrameOriginAllowed(undefined), false);
}

console.log("fill-engine node tests: all assertions passed");
