// Non-persistent background page (NOT a service worker: iOS Safari permanently
// kills MV3 service workers shortly after install). This page is the single
// message hub: popup and content scripts talk to it via runtime.sendMessage,
// and it alone relays to the native handler.
//
// SECURITY: native requests are rebuilt from scratch so only whitelisted keys
// cross the bridge, and the matching origin ALWAYS comes from the trusted
// browser.tabs API — a sender-supplied origin/URL is never forwarded.
// Vault-touching commands are honored ONLY from the extension's own popup UI:
// content.js runs inside every https page, and a compromised page/renderer
// context must never be able to pull item lists or field values through this
// hub without the user facing the popup. `getFillPayload` — the one native
// command that returns values for injection — is NEVER accepted from any
// sender: this page constructs it itself, exclusively inside the
// popup-initiated fill flow below, bound to the tab it derived the origin
// from. The payload lives in local variables only (never browser.storage,
// never a long-lived global) and is dropped after dispatch or 10 seconds.

const NATIVE_COMMANDS = new Set(["echo", "ping", "status", "listItems", "copyValue"]);
// Every command this hub understands is popup-only: content scripts run in
// every https page and have no legitimate reason to pull vault lists, field
// values, the ACTIVE tab's origin (cross-tab browsing disclosure), or even to
// bounce diagnostics off the native handler.
const POPUP_ONLY_COMMANDS = new Set([
  "listItems", "copyValue", "fillItem", "classifyPage",
  "activeTabOrigin", "echo", "ping", "status",
]);
const PROTOCOL_VERSION = 1;
const FILL_DELIVERY_TIMEOUT_MS = 10000;

// True only for messages from our own extension pages (the popup). Content
// scripts always carry the web page tab they run in; when the browser also
// supplies a sender URL, require it to be an extension-internal page rather
// than any web origin.
function isPopupSender(sender) {
  if (!sender || sender.tab) return false;
  if (typeof sender.url === "string" && sender.url.length > 0) {
    return sender.url.startsWith(browser.runtime.getURL(""));
  }
  return true;
}

function httpsOriginOf(url) {
  if (!url) return null;
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" ? parsed.origin : null;
  } catch {
    return null;
  }
}

// Active tab with a well-formed https page; null otherwise (http, reader
// mode, about:/extension pages, no tab).
async function activeHTTPSTab() {
  const tabs = await browser.tabs.query({ active: true, currentWindow: true });
  const tab = tabs && tabs[0];
  if (!tab || typeof tab.id !== "number") return null;
  const origin = httpsOriginOf(tab.url);
  return origin ? { id: tab.id, origin } : null;
}

function sendNative(request) {
  // On iOS the application id argument is ignored; messages always route to
  // this appex's own native handler.
  return browser.runtime
    .sendNativeMessage("application.id", request)
    .catch((error) => ({ v: PROTOCOL_VERSION, ok: false, error: `native:${String(error)}` }));
}

function reject(code) {
  return Promise.resolve({ v: PROTOCOL_VERSION, ok: false, error: code });
}

function withTimeout(promise, ms) {
  return Promise.race([
    promise,
    new Promise((_, timeout) => setTimeout(() => timeout(new Error("timeout")), ms)),
  ]);
}

// Popup "Fill" tap → the ONLY path that moves field values toward a page.
// Tab-id pinning: the tab id and origin are captured BEFORE the native
// request, and the tab's origin is re-checked AFTER the (possibly slow, Face
// ID gated) native round-trip — a payload never reaches a tab whose origin
// changed since the user acted. The content script re-checks origin again as
// a belt. Only aggregate fill counts return to the popup, never values.
async function handleFillItem(message) {
  const itemId = typeof message.itemId === "string" ? message.itemId : "";
  const category = message.category === "card" || message.category === "identity"
    ? message.category
    : "";
  if (!itemId || !category) return { v: PROTOCOL_VERSION, ok: false, error: "malformedMessage" };

  const tab = await activeHTTPSTab();
  if (!tab) return { v: PROTOCOL_VERSION, ok: false, error: "unsupportedPage" };

  // Consent binding: the user approved the origin the POPUP DISPLAYED on its
  // site chip. If the page navigated cross-origin while the popup was open,
  // the freshly derived origin no longer matches what the user saw — abort
  // before any native request. Comparing a popup-supplied value against the
  // trusted tabs-API origin can only narrow the fill, never widen it.
  const expectedOrigin = typeof message.expectedOrigin === "string"
    ? message.expectedOrigin
    : "";
  if (!expectedOrigin || expectedOrigin !== tab.origin) {
    return { v: PROTOCOL_VERSION, ok: false, error: "tabChanged" };
  }

  const reply = await sendNative({
    v: PROTOCOL_VERSION,
    cmd: "getFillPayload",
    origin: tab.origin,
    itemId,
    category,
  });
  if (!reply || reply.ok !== true || !reply.data || typeof reply.data.values !== "object") {
    return reply && reply.error
      ? { v: PROTOCOL_VERSION, ok: false, error: String(reply.error) }
      : { v: PROTOCOL_VERSION, ok: false, error: "nativeError" };
  }

  let values = reply.data.values;
  reply.data.values = null;
  try {
    const current = await browser.tabs.get(tab.id).catch(() => null);
    if (!current || httpsOriginOf(current.url) !== tab.origin) {
      return { v: PROTOCOL_VERSION, ok: false, error: "tabChanged" };
    }
    const result = await withTimeout(
      browser.tabs.sendMessage(tab.id, {
        cmd: "fillFields",
        origin: tab.origin,
        category,
        values,
      }),
      FILL_DELIVERY_TIMEOUT_MS,
    ).catch(() => null);
    if (!result || result.ok !== true || !result.data) {
      return { v: PROTOCOL_VERSION, ok: false, error: "fillFailed" };
    }
    return {
      v: PROTOCOL_VERSION,
      ok: true,
      data: {
        filled: Number(result.data.filled) || 0,
        skipped: Number(result.data.skipped) || 0,
      },
    };
  } finally {
    values = null;
  }
}

// Field-map summary (counts per category, nothing else) so the popup can
// enable its Fill buttons. A page without the content script (e.g. loaded
// before install) simply reports zero fillable fields.
async function handleClassifyPage() {
  const tab = await activeHTTPSTab();
  if (!tab) return { v: PROTOCOL_VERSION, ok: false, error: "unsupportedPage" };
  const reply = await browser.tabs
    .sendMessage(tab.id, { cmd: "classifyPage" })
    .catch(() => null);
  const summary = reply && reply.ok === true && reply.data ? reply.data : {};
  return {
    v: PROTOCOL_VERSION,
    ok: true,
    data: {
      identity: Number(summary.identity) || 0,
      card: Number(summary.card) || 0,
    },
  };
}

browser.runtime.onMessage.addListener((message, sender) => {
  if (!message || typeof message.cmd !== "string") {
    return reject("malformedMessage");
  }

  if (POPUP_ONLY_COMMANDS.has(message.cmd) && !isPopupSender(sender)) {
    return reject("forbidden");
  }

  // Local (non-native) query so the popup can render the site chip and the
  // unsupported-page state without touching the vault.
  if (message.cmd === "activeTabOrigin") {
    return activeHTTPSTab().then((tab) => ({
      v: PROTOCOL_VERSION,
      ok: true,
      data: { origin: tab ? tab.origin : null },
    }));
  }

  if (message.cmd === "fillItem") {
    return handleFillItem(message);
  }

  if (message.cmd === "classifyPage") {
    return handleClassifyPage();
  }

  if (!NATIVE_COMMANDS.has(message.cmd)) {
    return reject("unknownCommand");
  }

  if (message.cmd === "listItems") {
    return (async () => {
      const tab = await activeHTTPSTab();
      if (!tab) return { v: PROTOCOL_VERSION, ok: false, error: "unsupportedPage" };
      return sendNative({ v: PROTOCOL_VERSION, cmd: "listItems", origin: tab.origin });
    })();
  }

  if (message.cmd === "copyValue") {
    return sendNative({
      v: PROTOCOL_VERSION,
      cmd: "copyValue",
      itemId: typeof message.itemId === "string" ? message.itemId : "",
      fieldKind: typeof message.fieldKind === "string" ? message.fieldKind : "",
    });
  }

  // echo / ping / status: stateless diagnostics.
  return sendNative({
    v: PROTOCOL_VERSION,
    cmd: message.cmd,
    payload: typeof message.payload === "string" ? message.payload : "",
  });
});
