// Node-runnable unit tests for the pure signup detector (dev-only, never
// shipped). Loads the REAL field-classifier.js (for normalize) then
// signup-detector.js and exercises `detect()` with fabricated descriptors.
// Run: node VaultifySafari/DevFixtures/signup-detector-node-tests.mjs
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import assert from "node:assert/strict";

const here = dirname(fileURLToPath(import.meta.url));
for (const file of ["field-classifier.js", "signup-detector.js"]) {
  const source = readFileSync(join(here, "..", "Resources", file), "utf8");
  new Function(source)();
}
const { detect, submitTextMatches } = globalThis.LooxSignupDetector;

function pw(overrides) {
  return {
    id: overrides.id ?? 0,
    autocomplete: "", name: "", elementId: "", placeholder: "",
    label: "", ariaLabel: "", form: 0,
    ...overrides,
  };
}

function run(fields, context) {
  return detect(fields, {
    forms: [{ index: 0, submitText: "", hasUserField: true }],
    pageSubmitText: "",
    ...(context || {}),
  });
}

// --- Tier 1: autocomplete="new-password" is authoritative -------------------

assert.equal(run([pw({ autocomplete: "new-password" })]).pageType, "signup");
assert.equal(run([pw({ autocomplete: "new-password" })]).tier, 1);

// New + confirm pair, both tokened: both are fill targets.
{
  const result = run([
    pw({ id: 0, autocomplete: "new-password" }),
    pw({ id: 1, autocomplete: "new-password", label: "Confirm password" }),
  ]);
  assert.equal(result.pageType, "signup");
  assert.deepEqual(result.newPasswordIds.sort(), [0, 1]);
}

// Confirm field WITHOUT the token still joins the targets by keyword.
{
  const result = run([
    pw({ id: 0, autocomplete: "new-password" }),
    pw({ id: 1, label: "Nhập lại mật khẩu" }),
  ]);
  assert.equal(result.pageType, "signup");
  assert.deepEqual(result.newPasswordIds.sort(), [0, 1]);
}

// current-password + new-password = change-password; current is never a target.
{
  const result = run([
    pw({ id: 0, autocomplete: "current-password" }),
    pw({ id: 1, autocomplete: "new-password" }),
    pw({ id: 2, autocomplete: "new-password", label: "Confirm new password" }),
  ]);
  assert.equal(result.pageType, "changePassword");
  assert.equal(result.tier, 1);
  assert.ok(!result.newPasswordIds.includes(0), "current password is never a fill target");
  assert.deepEqual(result.newPasswordIds.sort(), [1, 2]);
}

// --- Tier 4: multiple password fields in one form ----------------------------

// password + confirm on a form with a user field = signup.
{
  const result = run([
    pw({ id: 0, name: "password" }),
    pw({ id: 1, name: "password_confirm", label: "Confirm password" }),
  ]);
  assert.equal(result.pageType, "signup");
  assert.equal(result.tier, 4);
  assert.deepEqual(result.newPasswordIds.sort(), [0, 1]);
}

// old + new + confirm (three fields) = change-password, old excluded by keyword.
{
  const result = run([
    pw({ id: 0, label: "Current password" }),
    pw({ id: 1, label: "New password" }),
    pw({ id: 2, label: "Confirm new password" }),
  ]);
  assert.equal(result.pageType, "changePassword");
  assert.deepEqual(result.newPasswordIds.sort(), [1, 2]);
}

// VI current-password label ("Mật khẩu hiện tại") excluded the same way.
{
  const result = run([
    pw({ id: 0, label: "Mật khẩu hiện tại" }),
    pw({ id: 1, label: "Mật khẩu mới" }),
  ]);
  assert.equal(result.pageType, "changePassword");
  assert.deepEqual(result.newPasswordIds, [1]);
}

// Userless new+confirm pair (settings page) reads as change, not signup.
{
  const result = detect(
    [pw({ id: 0, label: "New password" }), pw({ id: 1, label: "Confirm password" })],
    { forms: [{ index: 0, submitText: "", hasUserField: false }], pageSubmitText: "" },
  );
  assert.equal(result.pageType, "changePassword");
}

// --- Tier 3: single password + submit label ----------------------------------

function single(submitText) {
  return detect([pw({ id: 0 })], {
    forms: [{ index: 0, submitText, hasUserField: true }],
    pageSubmitText: "",
  });
}

assert.equal(single("Sign up").pageType, "signup");
assert.equal(single("Sign up").tier, 3);
assert.equal(single("Create account").pageType, "signup");
assert.equal(single("Create your account").pageType, "signup");
assert.equal(single("Register").pageType, "signup");
assert.equal(single("Đăng ký").pageType, "signup");
assert.equal(single("Tạo tài khoản").pageType, "signup");
assert.equal(single("Change password").pageType, "changePassword");
assert.equal(single("Đổi mật khẩu").pageType, "changePassword");
assert.equal(single("Đặt lại mật khẩu").pageType, "changePassword");

// Login pages are explicitly NOT actionable — QuickType owns them.
assert.equal(single("Sign in").pageType, "login");
assert.equal(single("Log in").pageType, "login");
assert.equal(single("Đăng nhập").pageType, "login");
assert.deepEqual(single("Sign in").newPasswordIds, []);
{
  const result = detect([pw({ id: 0, autocomplete: "current-password" })], {
    forms: [{ index: 0, submitText: "Sign up", hasUserField: true }],
    pageSubmitText: "",
  });
  assert.equal(result.pageType, "login", "current-password token pins a login even near signup copy");
}

// A lone "new password" field without any label is a reset/change flow.
{
  const result = single("");
  assert.equal(result.pageType, "login");
  const reset = detect([pw({ id: 0, label: "New password" })], {
    forms: [{ index: 0, submitText: "", hasUserField: false }],
    pageSubmitText: "",
  });
  assert.equal(reset.pageType, "changePassword");
}

// --- Honeypot fields (hidden anti-bot inputs) ----------------------------------

// A hidden extra password input on an otherwise-plain login form must not
// inflate the count into a tier-4 two-password "signup".
{
  const result = detect(
    [
      pw({ id: 0, name: "password" }),
      pw({ id: 1, name: "password_confirmation", visible: false }),
    ],
    {
      forms: [{ index: 0, submitText: "Sign in", hasUserField: true }],
      pageSubmitText: "",
    },
  );
  assert.equal(result.pageType, "login",
    "hidden honeypot must not turn a login into a signup");
  assert.deepEqual(result.newPasswordIds, []);
}

// Even a hidden new-password TOKEN is ignored — the user cannot see the field.
{
  const result = detect(
    [pw({ id: 0 }), pw({ id: 1, autocomplete: "new-password", visible: false })],
    {
      forms: [{ index: 0, submitText: "Log in", hasUserField: true }],
      pageSubmitText: "",
    },
  );
  assert.equal(result.pageType, "login");
}

// All password fields hidden: nothing the user can see, nothing to act on.
assert.equal(run([pw({ id: 0, visible: false })]).pageType, "none");

// Explicit visible:true and the absent-flag default behave identically.
{
  const result = run([
    pw({ id: 0, visible: true }),
    pw({ id: 1, label: "Confirm password" }),
  ]);
  assert.equal(result.pageType, "signup");
  assert.deepEqual(result.newPasswordIds.sort(), [0, 1]);
}

// --- Cross-form arbitration ---------------------------------------------------

// A page carrying BOTH a login form and a signup form picks the signup form.
{
  const result = detect(
    [
      pw({ id: 0, form: 0 }),
      pw({ id: 1, form: 1 }),
      pw({ id: 2, form: 1, label: "Confirm password" }),
    ],
    {
      forms: [
        { index: 0, submitText: "Sign in", hasUserField: true },
        { index: 1, submitText: "Sign up", hasUserField: true },
      ],
      pageSubmitText: "",
    },
  );
  assert.equal(result.pageType, "signup");
  assert.equal(result.form, 1);
  assert.deepEqual(result.newPasswordIds.sort(), [1, 2]);
}

// Formless (SPA) password field uses page-level submit text.
{
  const result = detect([pw({ id: 0, form: null })], {
    forms: [],
    pageSubmitText: "Create account",
    pageHasUserField: true,
  });
  assert.equal(result.pageType, "signup");
  assert.equal(result.form, null);
}

// --- Misc ----------------------------------------------------------------------

assert.equal(detect([], {}).pageType, "none");
assert.ok(submitTextMatches("Đăng ký ngay"));
assert.ok(submitTextMatches("Sign Up Free"));
assert.ok(!submitTextMatches("Sign in"));
assert.ok(!submitTextMatches("Đăng nhập"));
// Japanese submit labels: 新規登録 creates an account, ログイン must not.
assert.ok(submitTextMatches("新規登録"));
assert.ok(submitTextMatches("会員登録"));
assert.ok(submitTextMatches("アカウントを作成"));
assert.ok(!submitTextMatches("ログイン"));

// Descriptor results never carry a value slot (API shape guard).
{
  const result = run([pw({ autocomplete: "new-password" })]);
  assert.ok(!("value" in result), "detection output must not have a value slot");
}

console.log("signup-detector node tests: all assertions passed");
