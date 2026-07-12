// In-page save-new-login prompt (signup assist). Top frame only.
//
// SECURITY: credential values are captured ONLY at explicit submit intent
// (a trusted form submit or submit-button click) — never on keystroke, never
// on a timer. They live in closure memory with a 60-second TTL and travel to
// the native side exclusively when the user taps Save. The prompt renders in
// a CLOSED shadow root built entirely with createElement/textContent — no
// innerHTML anywhere near user data — and the captured password never enters
// the DOM (only the editable title/username appear, as input .value
// properties, never attributes). The background page suppresses the whole
// flow when the OS-native save sheet owns saving (iOS 26.2+) or the user
// opted this host out; both facts are decided natively, and this script
// never learns more than a single boolean. Nothing is logged.
(function () {
  "use strict";

  if (window.top !== window) return;

  const t = (key) => browser.i18n.getMessage(key);
  const VALUE_TTL_MS = 60000;
  const SCROLL_DISMISS_PX = 240;
  const MAX_SECRET_LENGTH = 512;
  const MAX_TITLE_LENGTH = 120;

  const OVERLAY_CSS = [
    ".card { position: fixed; left: 12px; right: 12px; bottom: 12px;",
    "  z-index: 2147483647; box-sizing: border-box;",
    "  background: #ffffff; color: #1c1c1e; border-radius: 16px;",
    "  padding: 16px; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.28);",
    "  font-family: -apple-system, system-ui, sans-serif; font-size: 15px; }",
    ".title { margin: 0; font-size: 16px; font-weight: 600; }",
    ".site { margin: 4px 0 12px; font-size: 13px; color: #6e6e73;",
    "  word-break: break-all; }",
    ".field { display: block; margin-bottom: 10px; }",
    ".field span { display: block; font-size: 12px; color: #6e6e73;",
    "  margin-bottom: 4px; }",
    ".field input { box-sizing: border-box; width: 100%; min-height: 40px;",
    "  border: 1px solid rgba(60, 60, 67, 0.24); border-radius: 10px;",
    "  padding: 8px 10px; font-size: 15px; background: inherit; color: inherit; }",
    ".row { display: flex; gap: 8px; margin-top: 4px; }",
    "button { appearance: none; border: none; border-radius: 12px;",
    "  min-height: 44px; padding: 10px 14px; font-size: 15px; font-weight: 600;",
    "  cursor: pointer; }",
    "button:disabled { opacity: 0.5; }",
    ".primary { flex: 1; background: #1544fd; color: #ffffff; }",
    ".secondary { flex: 1; background: rgba(60, 60, 67, 0.1); color: inherit; }",
    ".tertiary { width: 100%; margin-top: 8px; background: transparent;",
    "  color: #6e6e73; font-weight: 500; }",
    ".status { margin: 8px 0 0; min-height: 18px; font-size: 13px;",
    "  color: #6e6e73; text-align: center; }",
    "@media (prefers-color-scheme: dark) {",
    "  .card { background: #2c2c2e; color: #f2f2f7; }",
    "  .site, .field span, .status, .tertiary { color: #98989f; }",
    "  .field input { border-color: rgba(84, 84, 88, 0.5); }",
    "  .secondary { background: rgba(120, 120, 128, 0.24); }",
    "  .primary { background: #4d7dff; }",
    "}",
  ].join("\n");

  let captured = null;     // { username, password } — closure memory only
  let overlayHost = null;
  let ttlTimer = null;
  let gateInFlight = false;
  let anchorScrollY = 0;

  function clearCaptured() {
    if (captured) captured.password = "";
    captured = null;
    if (ttlTimer) {
      clearTimeout(ttlTimer);
      ttlTimer = null;
    }
  }

  function removeOverlay() {
    if (overlayHost) {
      overlayHost.remove();
      overlayHost = null;
    }
    window.removeEventListener("scroll", onScroll, true);
  }

  function dismiss() {
    removeOverlay();
    clearCaptured();
  }

  function onScroll() {
    if (Math.abs(window.scrollY - anchorScrollY) > SCROLL_DISMISS_PX) dismiss();
  }

  // --- Submit-intent capture --------------------------------------------------

  function captureAtIntent(formCandidate) {
    if (location.protocol !== "https:") return;
    if (overlayHost) return; // already prompting for this submission
    const scan = globalThis.LooxSignupDetector.scan(document);
    if (scan.pageType !== "signup" && scan.pageType !== "changePassword") return;
    // An intent aimed at a specific form must be the detected signup form.
    if (formCandidate && scan.form && formCandidate !== scan.form) return;
    const passwordEl = scan.newPasswordElements.find(
      (el) => el && typeof el.value === "string" && el.value.length > 0,
    );
    if (!passwordEl) return;
    const username = scan.usernameElement
      ? String(scan.usernameElement.value || "")
      : "";
    clearCaptured();
    captured = {
      username: username.slice(0, MAX_SECRET_LENGTH),
      password: String(passwordEl.value).slice(0, MAX_SECRET_LENGTH),
    };
    ttlTimer = setTimeout(dismiss, VALUE_TTL_MS);
    requestGateAndShow();
  }

  // Native gate: overlay renders only when the OS-native save sheet is NOT
  // active on this device and the host is not opted out. The check runs per
  // intent (no caching) so a "Never for this site" tap holds immediately.
  async function requestGateAndShow() {
    if (gateInFlight) return;
    gateInFlight = true;
    const reply = await browser.runtime.sendMessage({ cmd: "saveGate" }).catch(() => null);
    gateInFlight = false;
    if (!captured) return; // TTL or navigation raced the round trip
    const offered = reply && reply.ok === true && reply.data && reply.data.offer === true;
    if (!offered) {
      clearCaptured();
      return;
    }
    showOverlay();
  }

  document.addEventListener("submit", (event) => {
    if (!event.isTrusted) return;
    const form = event.target instanceof HTMLFormElement ? event.target : null;
    captureAtIntent(form);
  }, true);

  // SPA fallback: fetch-based signups fire no submit event. A trusted click
  // on a submit button — or any button whose label reads as signup/change —
  // is the intent.
  document.addEventListener("click", (event) => {
    if (!event.isTrusted) return;
    const target = event.target;
    if (!target || typeof target.closest !== "function") return;
    const button = target.closest('button, input[type="submit"]');
    if (!button) return;
    const form = button.form || button.closest("form");
    const type = (button.getAttribute("type")
      || (button.tagName === "BUTTON" ? "submit" : "")).toLowerCase();
    const text = button.tagName === "INPUT"
      ? (button.getAttribute("value") || "")
      : (button.textContent || "") + " " + (button.getAttribute("aria-label") || "");
    const submitLike = (form && type === "submit")
      || globalThis.LooxSignupDetector.submitTextMatches(text.slice(0, 300));
    if (!submitLike) return;
    captureAtIntent(form || null);
  }, true);

  window.addEventListener("pagehide", dismiss);

  // --- Overlay UI (closed shadow root; createElement/textContent only) --------

  function makeButton(label, className, handler) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = className;
    button.textContent = label;
    button.addEventListener("click", handler);
    return button;
  }

  function makeField(labelText, value) {
    const wrap = document.createElement("label");
    wrap.className = "field";
    const caption = document.createElement("span");
    caption.textContent = labelText;
    const input = document.createElement("input");
    input.type = "text";
    input.autocomplete = "off";
    input.spellcheck = false;
    input.value = value; // property assignment — never a DOM attribute
    wrap.appendChild(caption);
    wrap.appendChild(input);
    return { wrap, input };
  }

  function showOverlay() {
    removeOverlay();
    overlayHost = document.createElement("div");
    const shadow = overlayHost.attachShadow({ mode: "closed" });

    const style = document.createElement("style");
    style.textContent = OVERLAY_CSS;
    shadow.appendChild(style);

    const card = document.createElement("div");
    card.className = "card";

    const heading = document.createElement("p");
    heading.className = "title";
    heading.textContent = t("save_overlay_title");
    card.appendChild(heading);

    const site = document.createElement("p");
    site.className = "site";
    site.textContent = location.host;
    card.appendChild(site);

    const titleField = makeField(t("save_overlay_title_label"), location.host);
    const userField = makeField(t("save_overlay_username_label"), captured.username);
    card.appendChild(titleField.wrap);
    card.appendChild(userField.wrap);

    const status = document.createElement("p");
    status.className = "status";

    const save = makeButton(t("save_overlay_save"), "primary", () => {
      saveTapped(titleField.input, userField.input, status, [save, notNow, never]);
    });
    const notNow = makeButton(t("save_overlay_not_now"), "secondary", dismiss);
    const never = makeButton(t("save_overlay_never"), "tertiary", neverTapped);

    const row = document.createElement("div");
    row.className = "row";
    row.appendChild(save);
    row.appendChild(notNow);
    card.appendChild(row);
    card.appendChild(never);
    card.appendChild(status);

    shadow.appendChild(card);
    document.documentElement.appendChild(overlayHost);

    // Never steal focus; dismiss quietly when the user scrolls away.
    anchorScrollY = window.scrollY;
    window.addEventListener("scroll", onScroll, true);
  }

  // Save tap: the ONLY moment the captured password leaves this script. The
  // background page pins the origin to this tab (trusted sender.tab); the
  // native side re-validates and gates the write behind Face ID.
  async function saveTapped(titleInput, userInput, statusEl, buttons) {
    if (!captured) {
      dismiss();
      return;
    }
    buttons.forEach((button) => { button.disabled = true; });
    statusEl.textContent = "";
    const reply = await browser.runtime.sendMessage({
      cmd: "saveLogin",
      username: String(userInput.value || "").slice(0, MAX_SECRET_LENGTH),
      password: captured.password,
      title: String(titleInput.value || "").slice(0, MAX_TITLE_LENGTH),
    }).catch(() => null);
    if (reply && reply.ok === true) {
      clearCaptured();
      statusEl.textContent = t("save_overlay_saved");
      setTimeout(dismiss, 1600);
      return;
    }
    buttons.forEach((button) => { button.disabled = false; });
    const code = reply && reply.error ? String(reply.error) : "";
    if (code === "duplicate") {
      statusEl.textContent = t("save_overlay_duplicate");
    } else if (code === "unlockCancelled") {
      statusEl.textContent = "";
    } else {
      statusEl.textContent = t("save_overlay_failed");
    }
  }

  function neverTapped() {
    // Host-only opt-out, stored natively; fire and forget.
    browser.runtime.sendMessage({ cmd: "neverSave" }).catch(() => null);
    dismiss();
  }
})();
