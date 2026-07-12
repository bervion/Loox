// Field-anchored inline suggestion menu. Top frame only. Appears when the
// user focuses a field the classifier marked as an IDENTITY or CARD target
// with tier 1-2 evidence (autocomplete token or input type); keyword-only
// pages keep popup-driven fill so a false anchor never puts UI on a random
// field.
//
// ABSOLUTE RULE (1Password iOS precedent): this menu NEVER renders for
// credential fields. The native Credential Provider / QuickType bar owns
// standard logins — any form holding a visible password input suppresses the
// menu for every field in it, unless the signup detector proves the form is
// account creation / password change (where identity fill is legitimate and
// QuickType offers nothing). Password/username-shaped fields are refused
// outright as a belt.
//
// SECURITY: the menu DOM carries item TITLES and masked card metadata only —
// never a fillable value. Metadata comes from the background's session-only
// list command (locked vault = no menu, and focusing a field can never
// summon Face ID). A tap on a row starts the SAME authorized fill flow as
// the popup (`getFillPayload` natively, Face ID or session, origin pinned by
// the background to this tab); only aggregate counts return here. Rendering
// is a CLOSED shadow root built with createElement/textContent — no
// innerHTML anywhere. The menu never steals focus and never intercepts the
// page's keystrokes (arrow-key handling is scoped to the menu's own panel).
// Nothing is logged.
(function () {
  "use strict";

  if (window.top !== window) return;

  const t = (key, substitutions) => browser.i18n.getMessage(key, substitutions);

  const MAX_ROWS = 5;
  const LOCKED_RETRY_MS = 15000;
  const MENU_WIDTH = 300;
  const DISMISS_AFTER_FILL_MS = 1200;

  const MENU_CSS = [
    ".panel { position: fixed; z-index: 2147483647; box-sizing: border-box;",
    "  background: #ffffff; color: #1c1c1e; border-radius: 14px;",
    "  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.24);",
    "  font-family: -apple-system, system-ui, sans-serif; font-size: 15px;",
    "  padding: 6px; max-height: 300px; overflow-y: auto;",
    "  animation: rise 0.18s ease-out; }",
    "@keyframes rise { from { opacity: 0; transform: translateY(4px); }",
    "  to { opacity: 1; transform: none; } }",
    "@media (prefers-reduced-motion: reduce) { .panel { animation: none; } }",
    "button { appearance: none; border: none; background: transparent;",
    "  display: block; width: 100%; text-align: left; cursor: pointer;",
    "  border-radius: 10px; padding: 10px 12px; min-height: 44px;",
    "  font-size: 15px; color: inherit; box-sizing: border-box; }",
    "button:disabled { opacity: 0.5; }",
    "button:focus-visible { outline: 2px solid #1544fd; outline-offset: -2px; }",
    ".row-title { display: block; font-weight: 500; overflow: hidden;",
    "  text-overflow: ellipsis; white-space: nowrap; }",
    ".row-subtitle { display: block; font-size: 13px; color: #6e6e73;",
    "  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }",
    ".footer { border-top: 1px solid rgba(60, 60, 67, 0.12); margin-top: 4px;",
    "  padding-top: 4px; }",
    ".footer button { color: #1544fd; font-weight: 600; }",
    ".status { margin: 2px 12px 6px; min-height: 16px; font-size: 13px;",
    "  color: #6e6e73; }",
    "@media (prefers-color-scheme: dark) {",
    "  .panel { background: #2c2c2e; color: #f2f2f7; }",
    "  .row-subtitle, .status { color: #98989f; }",
    "  .footer { border-top-color: rgba(84, 84, 88, 0.5); }",
    "  .footer button, button:focus-visible { color: #4d7dff; outline-color: #4d7dff; }",
    "}",
  ].join("\n");

  // --- Eligibility (exported for the node harness) ----------------------------

  // Belt: attribute shapes that read as credential fields, refused before any
  // classifier verdict is even consulted.
  const CREDENTIAL_AUTOCOMPLETE =
    /(^|\s)(username|current-password|new-password|one-time-code)(\s|$)/;

  function isCredentialish(element) {
    const tag = element.tagName ? String(element.tagName).toUpperCase() : "";
    if (tag === "INPUT") {
      const type = (element.type || "").toLowerCase();
      if (type === "password" || type === "hidden") return true;
    }
    const autocomplete = element.getAttribute
      ? (element.getAttribute("autocomplete") || "")
      : "";
    return CREDENTIAL_AUTOCOMPLETE.test(autocomplete.toLowerCase());
  }

  function visiblePasswordFieldsIn(scope) {
    const engine = globalThis.LooxFillEngine;
    return Array.from(scope.querySelectorAll('input[type="password"]'))
      .filter((element) => engine.isVisible(element));
  }

  // The credential-context suppression rule described in the header comment.
  function credentialContextSuppressed(element, scanner, doc) {
    const scope = element.form || doc;
    if (!visiblePasswordFieldsIn(scope).length) return false;
    const scan = scanner.scan(doc);
    const actionable = scan.pageType === "signup" || scan.pageType === "changePassword";
    if (!actionable) return true;
    // The account-creation evidence must belong to the SAME form the focused
    // field sits in — a login form next to a signup form keeps its suppression.
    if (element.form && scan.form && scan.form !== element.form) return true;
    return false;
  }

  // Classifier verdict for a focused element: { key, category } for a
  // tier 1-2 identity/card target, null otherwise. `deps` lets the node
  // harness inject the page-scan/detector/document collaborators.
  function eligibleTarget(element, deps) {
    const d = deps || {
      pageScan: globalThis.LooxPageScan,
      scanner: globalThis.LooxSignupDetector,
      doc: document,
    };
    if (!element || !d.pageScan) return null;
    if (isCredentialish(element)) return null;
    const entry = d.pageScan.classify()
      .find((candidate) => candidate.element === element);
    if (!entry || entry.tier > 2) return null;
    if (entry.category !== "identity" && entry.category !== "card") return null;
    if (credentialContextSuppressed(element, d.scanner, d.doc)) return null;
    return { key: entry.key, category: entry.category };
  }

  // --- Metadata fetch (page-load cache; locked vault backs off) ---------------

  let cachedItems = null;
  let lockedUntil = 0;

  async function fetchItems() {
    if (cachedItems) return cachedItems;
    if (Date.now() < lockedUntil) return null;
    const reply = await browser.runtime
      .sendMessage({ cmd: "inlineItems" })
      .catch(() => null);
    if (!reply || reply.ok !== true || !reply.data) return null;
    if (reply.data.locked === true) {
      lockedUntil = Date.now() + LOCKED_RETRY_MS;
      return null;
    }
    cachedItems = {
      identities: Array.isArray(reply.data.identities) ? reply.data.identities : [],
      cards: Array.isArray(reply.data.cards) ? reply.data.cards : [],
    };
    return cachedItems;
  }

  // --- Menu lifecycle ----------------------------------------------------------

  let menuHost = null;
  let menuShadow = null;
  let menuPanel = null;
  let statusEl = null;
  let anchorEl = null;
  let fillInFlight = false;

  function dismiss() {
    if (menuHost) menuHost.remove();
    menuHost = null;
    menuShadow = null;
    menuPanel = null;
    statusEl = null;
    anchorEl = null;
    window.removeEventListener("scroll", onScroll, true);
    window.removeEventListener("resize", onResize, true);
    document.removeEventListener("pointerdown", onPointerDown, true);
    document.removeEventListener("keydown", onKeyDown, true);
  }

  function positionMenu() {
    if (!menuPanel || !anchorEl) return;
    const rect = anchorEl.getBoundingClientRect();
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;
    const width = Math.min(MENU_WIDTH, viewportWidth - 16);
    const left = Math.min(Math.max(8, rect.left), viewportWidth - width - 8);
    menuPanel.style.width = width + "px";
    menuPanel.style.left = left + "px";
    const spaceBelow = viewportHeight - rect.bottom;
    if (spaceBelow >= 200 || rect.top < 200) {
      menuPanel.style.top = Math.min(rect.bottom + 6, viewportHeight - 8) + "px";
      menuPanel.style.bottom = "auto";
    } else {
      menuPanel.style.bottom = (viewportHeight - rect.top + 6) + "px";
      menuPanel.style.top = "auto";
    }
  }

  function onScroll() {
    if (!anchorEl) return;
    const rect = anchorEl.getBoundingClientRect();
    const offViewport = rect.bottom < 0 || rect.top > window.innerHeight;
    if (offViewport || !globalThis.LooxFillEngine.isVisible(anchorEl)) {
      dismiss();
      return;
    }
    positionMenu();
  }

  function onResize() {
    positionMenu();
  }

  function onPointerDown(event) {
    // Events from inside the closed shadow root retarget to the host.
    if (event.target === menuHost || event.target === anchorEl) return;
    dismiss();
  }

  function onKeyDown(event) {
    // Dismiss on Escape; never preventDefault — the page keeps its keystroke.
    if (event.key === "Escape") dismiss();
  }

  function setStatus(text) {
    if (statusEl) statusEl.textContent = text;
  }

  function setRowsDisabled(disabled) {
    if (!menuPanel) return;
    menuPanel.querySelectorAll("button").forEach((button) => {
      button.disabled = disabled;
    });
  }

  async function fillTapped(itemId, category) {
    if (fillInFlight) return;
    fillInFlight = true;
    setStatus(t("popup_filling"));
    setRowsDisabled(true);
    const reply = await browser.runtime
      .sendMessage({ cmd: "inlineFillItem", itemId, category })
      .catch(() => null);
    fillInFlight = false;
    if (!menuHost) return;
    if (reply && reply.ok === true && reply.data) {
      const filled = Number(reply.data.filled) || 0;
      setStatus(filled > 0 ? t("popup_fill_done", [String(filled)]) : t("popup_fill_none"));
      setTimeout(dismiss, DISMISS_AFTER_FILL_MS);
      return;
    }
    setRowsDisabled(false);
    setStatus(reply && reply.error === "unlockCancelled" ? "" : t("popup_fill_failed"));
  }

  function makeRow(title, subtitle, ariaLabel, action) {
    const button = document.createElement("button");
    button.type = "button";
    button.setAttribute("aria-label", ariaLabel);
    const titleEl = document.createElement("span");
    titleEl.className = "row-title";
    titleEl.textContent = title;
    button.appendChild(titleEl);
    if (subtitle) {
      const subtitleEl = document.createElement("span");
      subtitleEl.className = "row-subtitle";
      subtitleEl.textContent = subtitle;
      button.appendChild(subtitleEl);
    }
    button.addEventListener("click", action);
    return button;
  }

  function cardSubtitle(card) {
    const brand = String(card.brand || "");
    const last4 = String(card.last4 || "");
    const masked = last4 ? t("popup_card_ending", [last4]) : "";
    return [brand, masked].filter(Boolean).join(" ");
  }

  // Arrow keys move between the menu's own rows. Scoped to the panel — the
  // page's keystrokes are never touched.
  function onPanelKeyDown(event) {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return;
    if (!menuPanel || !menuShadow) return;
    const rows = Array.from(menuPanel.querySelectorAll("button:not(:disabled)"));
    if (!rows.length) return;
    const index = rows.indexOf(menuShadow.activeElement);
    const step = event.key === "ArrowDown" ? 1 : -1;
    const next = rows[(index + step + rows.length) % rows.length];
    next.focus();
    event.preventDefault();
  }

  function showMenu(anchor, category, items) {
    dismiss();
    anchorEl = anchor;
    menuHost = document.createElement("div");
    menuShadow = menuHost.attachShadow({ mode: "closed" });

    const style = document.createElement("style");
    style.textContent = MENU_CSS;
    menuShadow.appendChild(style);

    menuPanel = document.createElement("div");
    menuPanel.className = "panel";
    menuPanel.setAttribute("role", "group");
    menuPanel.setAttribute("aria-label", t("inline_menu_label"));
    menuPanel.addEventListener("keydown", onPanelKeyDown);

    for (const item of items.slice(0, MAX_ROWS)) {
      const title = String(item.title || "");
      const subtitle = category === "card" ? cardSubtitle(item) : "";
      menuPanel.appendChild(makeRow(
        title,
        subtitle,
        t("inline_fill_item_label", [title]),
        () => fillTapped(String(item.id), category),
      ));
    }

    statusEl = document.createElement("p");
    statusEl.className = "status";
    menuPanel.appendChild(statusEl);

    const footer = document.createElement("div");
    footer.className = "footer";
    footer.appendChild(makeRow(t("inline_open_app"), "", t("inline_open_app"), () => {
      dismiss();
      // Registered app scheme; a user tap is the required gesture.
      location.href = "vaultify://";
    }));
    menuPanel.appendChild(footer);

    menuShadow.appendChild(menuPanel);
    document.documentElement.appendChild(menuHost);
    positionMenu();

    window.addEventListener("scroll", onScroll, { capture: true, passive: true });
    window.addEventListener("resize", onResize, true);
    document.addEventListener("pointerdown", onPointerDown, true);
    document.addEventListener("keydown", onKeyDown, true);
  }

  async function onFocusIn(event) {
    // Only a real user focus may summon the menu. A synthetic `.focus()` from
    // page script must do nothing: otherwise a hostile page programmatically
    // focuses a card/identity field and reads the menu host's presence/size to
    // learn, with zero interaction, that this is an unlocked vault with cards
    // and identities. Genuine focus (tap, tab, VoiceOver) is always trusted.
    if (!event.isTrusted) return;
    const target = event.target;
    // Focus moving INTO the menu (retargeted to the host) keeps it open.
    if (menuHost && target === menuHost) return;
    if (fillInFlight) return;
    const verdict = eligibleTarget(target);
    if (!verdict) {
      dismiss();
      return;
    }
    const items = await fetchItems();
    // The user may have moved on during the round trip.
    if (!items || document.activeElement !== target) return;
    const matching = verdict.category === "card" ? items.cards : items.identities;
    if (!matching.length) {
      dismiss();
      return;
    }
    showMenu(target, verdict.category, matching);
  }

  document.addEventListener("focusin", onFocusIn, true);
  window.addEventListener("pagehide", dismiss);

  // Node-harness surface (pure eligibility logic only; no menu internals).
  globalThis.LooxInlineMenu = {
    eligibleTarget,
    isCredentialish,
    credentialContextSuppressed,
  };
})();
