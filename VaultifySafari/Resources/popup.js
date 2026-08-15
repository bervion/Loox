// Popup: auto-attempts the unlock+list flow on open (native side serves it
// from a short-lived unlocked session when one exists, otherwise Face ID
// fires) → metadata-only item lists for the active tab's https origin, plus
// copy actions for non-secret values and Fill actions for identities/cards.
// Fill values never pass through this popup — a Fill tap only names the item
// and category; the background page runs the authorized flow and returns
// aggregate counts. A cancelled unlock falls back to the manual Unlock
// button — never auto-retried within the same popup instance.
// All rendering uses createElement/textContent — vault titles and usernames
// are user data and must never hit innerHTML. Nothing is persisted to
// browser.storage.

const t = (key, substitutions) => browser.i18n.getMessage(key, substitutions);

const STATE_IDS = ["locked", "unlocking", "list", "empty", "unsupported", "error"];
let feedbackTimer = null;
// The https origin this popup showed the user on the site chip. Every Fill
// tap sends it along so the background page can refuse to deliver values to
// a tab that navigated cross-origin after the user last saw the chip.
let displayedOrigin = null;
// Per-site kill switch state for the displayed origin. Hidden sites keep
// popup-driven fill (this popup is an explicit user surface) but get no
// in-page UI: no inline menu, no save overlay.
let siteHidden = false;

function localizeStaticText() {
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    el.textContent = t(el.dataset.i18n);
  });
  document.title = t("popup_title");
}

function show(state) {
  STATE_IDS.forEach((id) => {
    document.getElementById(`state-${id}`).hidden = id !== state;
  });
}

function showFeedback(text) {
  const el = document.getElementById("feedback");
  el.textContent = text;
  if (feedbackTimer) clearTimeout(feedbackTimer);
  feedbackTimer = setTimeout(() => { el.textContent = ""; }, 2000);
}

async function copyToClipboard(value) {
  try {
    await navigator.clipboard.writeText(value);
    showFeedback(t("popup_copied"));
  } catch {
    showFeedback(t("popup_copy_failed"));
  }
}

function showError(reply) {
  const code = reply && reply.error ? String(reply.error) : "";
  let message;
  if (code === "unlockUnavailable") {
    // Face ID has no key to release (never enrolled, or the enrolled set
    // changed). Retrying here can never work — the app's password unlock is
    // the only way back, and it re-provisions the shared key for us.
    message = t("popup_error_unlock_unavailable");
  } else if (code.startsWith("native:")) {
    message = t("popup_error_unreachable");
  } else {
    message = t("popup_error_generic");
  }
  document.getElementById("error-message").textContent = message;
  show("error");
}

function handleListFailure(reply) {
  const code = reply && reply.error;
  if (code === "unlockCancelled") { show("locked"); return; }
  if (code === "unsupportedPage" || code === "invalidOrigin") { show("unsupported"); return; }
  showError(reply);
}

// --- Rendering (metadata only; copy + fill buttons per row) ---

// Letter-avatar contract shared with the app (MonogramAvatar.swift): djb2 over
// unicode scalars in 64-bit signed wrapping arithmetic — BigInt reproduces the
// Swift overflow exactly, so an item keeps the SAME hue here as in its Home
// row. Saturation/brightness (0.58/0.66 HSB) convert to hsl(h, 41%, 47%).
const U64 = (1n << 64n) - 1n;
const S63 = 1n << 63n;
function monogramHue(title) {
  let h = 5381n;
  for (const ch of title) h = ((h << 5n) + h + BigInt(ch.codePointAt(0))) & U64;
  if (h >= S63) h -= 1n << 64n;
  if (h < 0n) h = -h;
  return Number(h % 360n);
}

function monogramInitials(title) {
  const words = title.split(" ").filter(Boolean);
  if (!words.length) return null;
  const first = [...words[0]][0];
  const second = words.length >= 2 ? [...words[1]][0] : "";
  return (first + second).toUpperCase();
}

const SVG_NS = "http://www.w3.org/2000/svg";

// Category glyphs (identity / card) as code-built SVG — createElementNS keeps
// the no-innerHTML contract. Paths sit in a 24x24 unit space and tint via the
// CSS category variables; the faint second shape gives the app's duotone read.
const GLYPH_PATHS = {
  identity: [
    { d: "M12 12a4.2 4.2 0 1 0 0-8.4 4.2 4.2 0 0 0 0 8.4Z", opacity: "1" },
    { d: "M12 13.8c-4.1 0-7.4 2.3-7.4 5.2 0 .9.7 1.6 1.6 1.6h11.6c.9 0 1.6-.7 1.6-1.6 0-2.9-3.3-5.2-7.4-5.2Z", opacity: "0.45" },
  ],
  card: [
    { d: "M2.8 8.2c0-1.7 1.3-3 3-3h12.4c1.7 0 3 1.3 3 3v.9H2.8v-.9Z", opacity: "1" },
    { d: "M2.8 11h18.4v4.8c0 1.7-1.3 3-3 3H5.8c-1.7 0-3-1.3-3-3V11Zm2.6 4.1h5v1.4h-5v-1.4Z", opacity: "0.45" },
  ],
};

// The row's leading avatar: logins wear the title monogram (or a neutral tile
// for empty titles), identities and cards wear their category glyph — the same
// visual language the app's vault rows speak.
function makeIcon(kind, title) {
  const icon = document.createElement("div");
  icon.className = "item-icon";
  if (kind === "login") {
    const initials = monogramInitials(title);
    const tile = document.createElement("span");
    tile.className = "mono-tile";
    if (initials) {
      tile.style.background = `hsl(${monogramHue(title)}, 41%, 47%)`;
      tile.textContent = initials;
    } else {
      tile.classList.add("empty");
    }
    icon.appendChild(tile);
    return icon;
  }
  const svg = document.createElementNS(SVG_NS, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("class", `glyph glyph-${kind}`);
  svg.setAttribute("aria-hidden", "true");
  for (const shape of GLYPH_PATHS[kind] || []) {
    const path = document.createElementNS(SVG_NS, "path");
    path.setAttribute("d", shape.d);
    path.setAttribute("fill", "currentColor");
    path.setAttribute("fill-opacity", shape.opacity);
    svg.appendChild(path);
  }
  icon.appendChild(svg);
  return icon;
}

function makeRow(title, subtitle, buttons, iconKind) {
  const row = document.createElement("div");
  row.className = "item-row";

  if (iconKind) row.appendChild(makeIcon(iconKind, title));

  const text = document.createElement("div");
  text.className = "item-text";
  const titleEl = document.createElement("p");
  titleEl.className = "item-title";
  titleEl.textContent = title;
  text.appendChild(titleEl);
  if (subtitle) {
    const subEl = document.createElement("p");
    subEl.className = "item-subtitle";
    subEl.textContent = subtitle;
    text.appendChild(subEl);
  }
  row.appendChild(text);

  (buttons || []).forEach((config) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = config.className;
    button.textContent = config.text;
    button.setAttribute("aria-label", config.label);
    if (config.disabled) {
      button.disabled = true;
    } else {
      button.addEventListener("click", config.action);
    }
    row.appendChild(button);
  });
  return row;
}

function copyButton(label, action) {
  return { className: "copy-button", text: t("popup_copy_button"), label, action };
}

// Fill is offered only when the classifier found at least one matching field
// on the page — a disabled button communicates "nothing to fill here". The
// tap kicks off the background's authorized fill flow; only aggregate counts
// ever come back to this popup.
function fillButton(labelKey, itemId, category, enabled) {
  return {
    className: "fill-button",
    text: t("popup_fill_button"),
    label: t(labelKey),
    disabled: !enabled,
    action: () => fillItem(itemId, category),
  };
}

async function fillItem(itemId, category) {
  showFeedback(t("popup_filling"));
  const reply = await browser.runtime
    .sendMessage({ cmd: "fillItem", itemId, category, expectedOrigin: displayedOrigin })
    .catch(() => null);
  if (reply && reply.ok === true && reply.data) {
    const filled = Number(reply.data.filled) || 0;
    showFeedback(filled > 0 ? t("popup_fill_done", [String(filled)]) : t("popup_fill_none"));
  } else if (reply && reply.error === "unlockCancelled") {
    showFeedback("");
  } else {
    showFeedback(t("popup_fill_failed"));
  }
}

// Counts of fillable fields per category on the active page plus the signup
// page type; zeros/none when the page has none (or the content script is not
// reachable).
async function fetchFillSummary() {
  const reply = await browser.runtime
    .sendMessage({ cmd: "classifyPage" })
    .catch(() => null);
  if (reply && reply.ok === true && reply.data) {
    return {
      identity: Number(reply.data.identity) || 0,
      card: Number(reply.data.card) || 0,
      pageType: typeof reply.data.pageType === "string" ? reply.data.pageType : "none",
    };
  }
  return { identity: 0, card: 0, pageType: "none" };
}

// Signup assist: the "Use generated password" button shows only when the
// content script classified the page as a signup/change-password form.
function setSignupAssist(pageType) {
  const visible = pageType === "signup" || pageType === "changePassword";
  document.getElementById("signup-assist").hidden = !visible;
}

// Fill a freshly generated strong password into the page's new-password
// fields. The password is generated natively and never touches this popup —
// the background page routes it straight to the content script and only
// aggregate counts come back.
async function fillGeneratedPassword() {
  showFeedback(t("popup_filling"));
  const reply = await browser.runtime
    .sendMessage({ cmd: "generatePasswordFill", expectedOrigin: displayedOrigin })
    .catch(() => null);
  if (reply && reply.ok === true && reply.data) {
    const filled = Number(reply.data.filled) || 0;
    showFeedback(filled > 0 ? t("popup_fill_done", [String(filled)]) : t("popup_fill_none"));
  } else {
    showFeedback(t("popup_fill_failed"));
  }
}

// --- Per-site kill switch ("Hide on this site") ---

function renderSiteToggle() {
  document.getElementById("site-settings").hidden = false;
  document.getElementById("site-hidden-hint").hidden = !siteHidden;
  document.getElementById("site-toggle-button").textContent = siteHidden
    ? t("popup_show_site_button")
    : t("popup_hide_site_button");
}

// Reads the stored per-host flag for the displayed origin. The footer stays
// hidden until the state is known — no toggle renders on an unknown state.
async function initializeSiteToggle() {
  const reply = await browser.runtime
    .sendMessage({ cmd: "siteSettings" })
    .catch(() => null);
  if (!reply || reply.ok !== true || !reply.data) return;
  siteHidden = reply.data.hidden === true;
  renderSiteToggle();
}

async function toggleSiteHidden() {
  const button = document.getElementById("site-toggle-button");
  button.disabled = true;
  const reply = await browser.runtime
    .sendMessage({
      cmd: "setSiteHidden",
      hidden: !siteHidden,
      expectedOrigin: displayedOrigin,
    })
    .catch(() => null);
  button.disabled = false;
  if (reply && reply.ok === true && reply.data) {
    siteHidden = reply.data.hidden === true;
    renderSiteToggle();
  } else {
    showFeedback(t("popup_error_generic"));
  }
}

function makeSection(titleKey, rows) {
  const section = document.createElement("section");
  section.className = "item-section";
  const heading = document.createElement("h2");
  heading.textContent = t(titleKey);
  section.appendChild(heading);
  rows.forEach((row) => section.appendChild(row));
  return section;
}

// Copying an identity email goes back through the native handler (served from
// the native session when valid, otherwise another Face ID prompt). The value
// is whitelisted natively — only non-secret kinds are ever released.
async function copyItemField(itemId, fieldKind) {
  const reply = await browser.runtime
    .sendMessage({ cmd: "copyValue", itemId, fieldKind })
    .catch(() => null);
  if (reply && reply.ok === true && reply.data && typeof reply.data.value === "string") {
    await copyToClipboard(reply.data.value);
  } else if (reply && reply.error === "unlockCancelled") {
    showFeedback("");
  } else {
    showFeedback(t("popup_copy_failed"));
  }
}

function render(data, fillSummary) {
  const logins = Array.isArray(data.logins) ? data.logins : [];
  const identities = Array.isArray(data.identities) ? data.identities : [];
  const cards = Array.isArray(data.cards) ? data.cards : [];
  if (!logins.length && !identities.length && !cards.length) {
    show("empty");
    return;
  }

  const container = document.getElementById("sections");
  container.textContent = "";

  if (logins.length) {
    const rows = logins.map((login) => makeRow(
      String(login.title || ""),
      String(login.username || ""),
      login.username
        ? [copyButton(t("popup_copy_username_label"),
                      () => copyToClipboard(String(login.username)))]
        : [],
      "login",
    ));
    container.appendChild(makeSection("popup_section_logins", rows));
  }

  if (identities.length) {
    const rows = identities.map((identity) => makeRow(
      String(identity.title || ""),
      "",
      [
        fillButton("popup_fill_identity_label", String(identity.id), "identity",
                   fillSummary.identity > 0),
        copyButton(t("popup_copy_email_label"),
                   () => copyItemField(String(identity.id), "email")),
      ],
      "identity",
    ));
    container.appendChild(makeSection("popup_section_identities", rows));
  }

  if (cards.length) {
    const rows = cards.map((card) => {
      const brand = String(card.brand || "");
      const last4 = String(card.last4 || "");
      const masked = last4 ? t("popup_card_ending", [last4]) : "";
      const subtitle = [brand, masked].filter(Boolean).join(" ");
      return makeRow(String(card.title || ""), subtitle, [
        fillButton("popup_fill_card_label", String(card.id), "card",
                   fillSummary.card > 0),
      ], "card");
    });
    container.appendChild(makeSection("popup_section_cards", rows));
  }

  show("list");
}

// --- Flow ---

async function unlockAndList() {
  show("unlocking");
  setSignupAssist("none");
  const reply = await browser.runtime.sendMessage({ cmd: "listItems" }).catch(() => null);
  if (reply && reply.ok === true) {
    const fillSummary = await fetchFillSummary();
    setSignupAssist(fillSummary.pageType);
    render(reply.data || {}, fillSummary);
  } else {
    handleListFailure(reply);
  }
}

async function initialize() {
  localizeStaticText();
  document.getElementById("unlock-button").addEventListener("click", unlockAndList);
  document.getElementById("retry-button").addEventListener("click", unlockAndList);
  document.getElementById("generate-button").addEventListener("click", fillGeneratedPassword);
  document.getElementById("site-toggle-button").addEventListener("click", toggleSiteHidden);

  const originReply = await browser.runtime
    .sendMessage({ cmd: "activeTabOrigin" })
    .catch(() => null);
  if (!originReply || originReply.ok !== true) {
    showError(originReply);
    return;
  }
  const origin = originReply.data && originReply.data.origin;
  if (!origin) {
    show("unsupported");
    return;
  }
  displayedOrigin = origin;
  const hostEl = document.getElementById("site-host");
  hostEl.textContent = new URL(origin).host;
  hostEl.hidden = false;
  // The per-site toggle loads alongside the list (independent flows; the
  // toggle is metadata-only and never blocks on the unlock).
  initializeSiteToggle();
  // Auto-attempt: within the native session this renders the list with zero
  // prompts; otherwise Face ID fires once. Cancel lands on the manual Unlock
  // button via handleListFailure — no retry loop in this popup instance.
  await unlockAndList();
}

initialize();
