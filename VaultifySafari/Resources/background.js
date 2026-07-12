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
// Vault-reading and diagnostic commands are popup-only: content scripts run
// in every https page and have no legitimate reason to pull vault lists,
// field values, the ACTIVE tab's origin (cross-tab browsing disclosure), or
// even to bounce diagnostics off the native handler.
const POPUP_ONLY_COMMANDS = new Set([
  "listItems", "copyValue", "fillItem", "classifyPage",
  "activeTabOrigin", "echo", "ping", "status", "generatePasswordFill",
]);
// Signup-assist commands from the save overlay, which lives in the page's
// content-script world (top frame only). They move NOTHING from the vault
// toward the page: saveGate returns one boolean about the sender's own
// origin; saveLogin/neverSave carry data AWAY from the page on an explicit
// user tap and are Face-ID-gated natively. The origin ALWAYS comes from the
// trusted sender.tab — a message-supplied origin is never accepted.
const CONTENT_SAVE_COMMANDS = new Set(["saveGate", "saveLogin", "neverSave"]);
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

// The https origin of the TOP-LEVEL page a content-script message came from;
// null for popup/extension senders, sub-frames, and non-https pages. Derived
// exclusively from the browser-supplied sender — never from message fields.
function contentSenderOrigin(sender) {
  if (!sender || !sender.tab || typeof sender.tab.id !== "number") return null;
  if (typeof sender.frameId === "number" && sender.frameId !== 0) return null;
  const tabOrigin = httpsOriginOf(sender.tab.url);
  if (!tabOrigin) return null;
  // Belt: when the browser also reports the script's own frame URL, it must
  // agree with the tab's top-level origin.
  if (typeof sender.url === "string" && sender.url.length > 0
      && httpsOriginOf(sender.url) !== tabOrigin) {
    return null;
  }
  return tabOrigin;
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

// Field-map summary (counts per category plus the signup page type, nothing
// else) so the popup can enable its Fill buttons and the signup-assist
// action. A page without the content script (e.g. loaded before install)
// simply reports zero fillable fields.
async function handleClassifyPage() {
  const tab = await activeHTTPSTab();
  if (!tab) return { v: PROTOCOL_VERSION, ok: false, error: "unsupportedPage" };
  const reply = await browser.tabs
    .sendMessage(tab.id, { cmd: "classifyPage" })
    .catch(() => null);
  const summary = reply && reply.ok === true && reply.data ? reply.data : {};
  const actionable = summary.pageType === "signup" || summary.pageType === "changePassword";
  return {
    v: PROTOCOL_VERSION,
    ok: true,
    data: {
      identity: Number(summary.identity) || 0,
      card: Number(summary.card) || 0,
      pageType: actionable ? summary.pageType : "none",
    },
  };
}

// Popup "Use generated password" tap → native generation → fill into the
// page's new-password fields. Mirrors handleFillItem's authorization: origin
// consent binding to what the popup displayed, tab-id pinning, an origin
// re-check after the native round trip, and the value living only in locals
// until dispatch. Only aggregate counts return to the popup.
async function handleGeneratePasswordFill(message) {
  const tab = await activeHTTPSTab();
  if (!tab) return { v: PROTOCOL_VERSION, ok: false, error: "unsupportedPage" };

  const expectedOrigin = typeof message.expectedOrigin === "string"
    ? message.expectedOrigin
    : "";
  if (!expectedOrigin || expectedOrigin !== tab.origin) {
    return { v: PROTOCOL_VERSION, ok: false, error: "tabChanged" };
  }

  const reply = await sendNative({ v: PROTOCOL_VERSION, cmd: "generatePassword" });
  if (!reply || reply.ok !== true || !reply.data
      || typeof reply.data.password !== "string" || !reply.data.password) {
    return reply && reply.error
      ? { v: PROTOCOL_VERSION, ok: false, error: String(reply.error) }
      : { v: PROTOCOL_VERSION, ok: false, error: "nativeError" };
  }

  let password = reply.data.password;
  reply.data.password = null;
  try {
    const current = await browser.tabs.get(tab.id).catch(() => null);
    if (!current || httpsOriginOf(current.url) !== tab.origin) {
      return { v: PROTOCOL_VERSION, ok: false, error: "tabChanged" };
    }
    const result = await withTimeout(
      browser.tabs.sendMessage(tab.id, {
        cmd: "fillGeneratedPassword",
        origin: tab.origin,
        password,
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
    password = null;
  }
}

// Signup-assist gate: may the content script offer its save overlay for the
// sender's page? Decided natively (iOS 26.2+ native-save suppression + the
// user's never-save list); exactly one boolean flows back.
async function handleSaveGate(sender) {
  const origin = contentSenderOrigin(sender);
  if (!origin) return { v: PROTOCOL_VERSION, ok: false, error: "forbidden" };
  const reply = await sendNative({ v: PROTOCOL_VERSION, cmd: "saveGate", origin });
  const offer = Boolean(reply && reply.ok === true && reply.data
    && reply.data.offer === true);
  return { v: PROTOCOL_VERSION, ok: true, data: { offer } };
}

// Save tap in the overlay → native write (Face ID gated). Values were
// captured at submit intent and cross toward native ONLY here; the request
// is rebuilt so exactly the whitelisted keys go over the bridge, with the
// origin pinned to the trusted sender tab.
async function handleSaveLogin(message, sender) {
  const origin = contentSenderOrigin(sender);
  if (!origin) return { v: PROTOCOL_VERSION, ok: false, error: "forbidden" };
  const password = typeof message.password === "string" ? message.password : "";
  if (!password || password.length > 512) {
    return { v: PROTOCOL_VERSION, ok: false, error: "malformedMessage" };
  }
  const username = typeof message.username === "string"
    ? message.username.slice(0, 512)
    : "";
  const title = typeof message.title === "string" ? message.title.slice(0, 120) : "";
  const reply = await sendNative({
    v: PROTOCOL_VERSION,
    cmd: "saveLogin",
    origin,
    username,
    password,
    title,
  });
  if (reply && reply.ok === true) {
    const itemId = reply.data && typeof reply.data.itemId === "string"
      ? reply.data.itemId
      : "";
    return { v: PROTOCOL_VERSION, ok: true, data: { itemId } };
  }
  return {
    v: PROTOCOL_VERSION,
    ok: false,
    error: reply && reply.error ? String(reply.error) : "nativeError",
  };
}

// "Never for this site": host-only opt-out stored natively.
async function handleNeverSave(sender) {
  const origin = contentSenderOrigin(sender);
  if (!origin) return { v: PROTOCOL_VERSION, ok: false, error: "forbidden" };
  return sendNative({ v: PROTOCOL_VERSION, cmd: "neverSave", origin });
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

  if (CONTENT_SAVE_COMMANDS.has(message.cmd)) {
    if (message.cmd === "saveGate") return handleSaveGate(sender);
    if (message.cmd === "saveLogin") return handleSaveLogin(message, sender);
    return handleNeverSave(sender);
  }

  if (message.cmd === "fillItem") {
    return handleFillItem(message);
  }

  if (message.cmd === "generatePasswordFill") {
    return handleGeneratePasswordFill(message);
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
