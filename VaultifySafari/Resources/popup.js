// Popup: auto-attempts the unlock+list flow on open (native side serves it
// from a short-lived unlocked session when one exists, otherwise Face ID
// fires) → metadata-only item lists for the active tab's https origin, plus
// copy actions for non-secret values. A cancelled unlock falls back to the
// manual Unlock button — never auto-retried within the same popup instance.
// All rendering uses createElement/textContent — vault titles and usernames
// are user data and must never hit innerHTML. Nothing is persisted to
// browser.storage.

const t = (key, substitutions) => browser.i18n.getMessage(key, substitutions);

const STATE_IDS = ["locked", "unlocking", "list", "empty", "unsupported", "error"];
let feedbackTimer = null;

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
  const message = code.startsWith("native:")
    ? t("popup_error_unreachable")
    : t("popup_error_generic");
  document.getElementById("error-message").textContent = message;
  show("error");
}

function handleListFailure(reply) {
  const code = reply && reply.error;
  if (code === "unlockCancelled") { show("locked"); return; }
  if (code === "unsupportedPage" || code === "invalidOrigin") { show("unsupported"); return; }
  showError(reply);
}

// --- Rendering (metadata only; copy buttons for non-secret values) ---

function makeRow(title, subtitle, copyConfig) {
  const row = document.createElement("div");
  row.className = "item-row";

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

  if (copyConfig) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "copy-button";
    button.textContent = t("popup_copy_button");
    button.setAttribute("aria-label", copyConfig.label);
    button.addEventListener("click", copyConfig.action);
    row.appendChild(button);
  }
  return row;
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

function render(data) {
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
        ? { label: t("popup_copy_username_label"),
            action: () => copyToClipboard(String(login.username)) }
        : null,
    ));
    container.appendChild(makeSection("popup_section_logins", rows));
  }

  if (identities.length) {
    const rows = identities.map((identity) => makeRow(
      String(identity.title || ""),
      "",
      { label: t("popup_copy_email_label"),
        action: () => copyItemField(String(identity.id), "email") },
    ));
    container.appendChild(makeSection("popup_section_identities", rows));
  }

  if (cards.length) {
    const rows = cards.map((card) => {
      const brand = String(card.brand || "");
      const last4 = String(card.last4 || "");
      const masked = last4 ? t("popup_card_ending", [last4]) : "";
      const subtitle = [brand, masked].filter(Boolean).join(" ");
      return makeRow(String(card.title || ""), subtitle, null);
    });
    container.appendChild(makeSection("popup_section_cards", rows));
  }

  show("list");
}

// --- Flow ---

async function unlockAndList() {
  show("unlocking");
  const reply = await browser.runtime.sendMessage({ cmd: "listItems" }).catch(() => null);
  if (reply && reply.ok === true) {
    render(reply.data || {});
  } else {
    handleListFailure(reply);
  }
}

async function initialize() {
  localizeStaticText();
  document.getElementById("unlock-button").addEventListener("click", unlockAndList);
  document.getElementById("retry-button").addEventListener("click", unlockAndList);

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
  const hostEl = document.getElementById("site-host");
  hostEl.textContent = new URL(origin).host;
  hostEl.hidden = false;
  // Auto-attempt: within the native session this renders the list with zero
  // prompts; otherwise Face ID fires once. Cancel lands on the manual Unlock
  // button via handleListFailure — no retry loop in this popup instance.
  await unlockAndList();
}

initialize();
