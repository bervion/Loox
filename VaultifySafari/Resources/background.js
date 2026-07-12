// Non-persistent background page (NOT a service worker: iOS Safari permanently
// kills MV3 service workers shortly after install). This page is the single
// message hub: popup and content scripts talk to it via runtime.sendMessage,
// and it alone relays to the native handler.
//
// SECURITY: native requests are rebuilt from scratch so only whitelisted keys
// cross the bridge, and the matching origin ALWAYS comes from the trusted
// browser.tabs API — a sender-supplied origin/URL is never forwarded.
// Vault-touching commands are honored ONLY from the extension's own popup UI,
// with two deliberate inline-menu exceptions: `inlineItems` (session-only
// metadata, locked vault = nothing, never a prompt) and `inlineFillItem`
// (the menu tap; the native session/Face ID still gates the values). Beyond
// those, content.js runs inside every https page and a compromised
// page/renderer context must never be able to pull item lists or field
// values through this hub without the user facing the popup or Face ID.
// `getFillPayload` — the one native command that returns values for
// injection — is NEVER accepted from any sender: this page constructs it
// itself, exclusively inside the two user-tap fill flows below (popup Fill,
// inline-menu tap), bound to the tab it derived the origin from. The payload
// lives in local variables only (never browser.storage, never a long-lived
// global) and is dropped after dispatch or 10 seconds.

const NATIVE_COMMANDS = new Set(["echo", "ping", "status", "listItems", "copyValue"]);
// Vault-reading and diagnostic commands are popup-only: content scripts run
// in every https page and have no legitimate reason to pull vault lists,
// field values, the ACTIVE tab's origin (cross-tab browsing disclosure), or
// even to bounce diagnostics off the native handler.
const POPUP_ONLY_COMMANDS = new Set([
  "listItems", "copyValue", "fillItem", "classifyPage",
  "activeTabOrigin", "echo", "ping", "status", "generatePasswordFill",
  "siteSettings", "setSiteHidden",
]);
// Signup-assist commands from the save overlay, which lives in the page's
// content-script world (top frame only). They move NOTHING from the vault
// toward the page: saveGate returns one boolean about the sender's own
// origin; saveLogin/neverSave carry data AWAY from the page on an explicit
// user tap and are Face-ID-gated natively. The origin ALWAYS comes from the
// trusted sender.tab — a message-supplied origin is never accepted.
const CONTENT_SAVE_COMMANDS = new Set(["saveGate", "saveLogin", "neverSave"]);
// Inline-menu commands from the top-frame content script plus the
// payment-frame announcement. `inlineItems` releases metadata ONLY from the
// session-only native list (a page can never summon Face ID by focusing a
// field); `inlineFillItem` is the menu tap and runs the same authorized
// getFillPayload flow as the popup — Face ID or session gates the values.
// `hideSite` is the menu footer's per-site kill switch: HIDE-only for the
// sender's own host (a page abusing it can only remove OUR UI from itself,
// a strictly exposure-narrowing action; re-enabling is popup-only).
const CONTENT_INLINE_COMMANDS = new Set([
  "inlineItems", "inlineFillItem", "ccFrameHello", "hideSite",
]);
const PROTOCOL_VERSION = 1;
const FILL_DELIVERY_TIMEOUT_MS = 10000;

// Cross-origin iframe fill allowlist: known payment-processor widget hosts,
// card category only. KEEP IN SYNC with `CC_FRAME_HOSTS` in fill-engine.js
// (the in-frame self-check); this copy validates the browser-reported frame
// origin before the background ever addresses the frame.
const CC_FRAME_HOSTS = new Set([
  "js.stripe.com",
  "checkout.stripe.com",
  "pay.google.com",
]);

// Per-tab, memory-only state. Both maps are invalidated on top-level
// navigation and tab close; neither ever touches browser.storage.
//   inlineItemsCache: tabId -> { origin, identities, cards } — METADATA ONLY
//     (titles, ids, brand, last-4), so a focus never re-runs the native list.
//   ccFrameRegistry: tabId -> Map(frameId -> https frame origin) — the
//     allowlisted payment frames that announced themselves, addressed later
//     by explicit frameId (each frame re-verifies its own origin at fill).
const inlineItemsCache = new Map();
const ccFrameRegistry = new Map();

function forgetTabState(tabId) {
  inlineItemsCache.delete(tabId);
  ccFrameRegistry.delete(tabId);
}

browser.tabs.onUpdated.addListener((tabId, changeInfo) => {
  if (changeInfo.status === "loading" || typeof changeInfo.url === "string") {
    forgetTabState(tabId);
  }
});
browser.tabs.onRemoved.addListener(forgetTabState);

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

// The https origin of an allowlisted payment-processor frame URL; null for
// anything else (non-https, non-default port, host off the allowlist).
function allowlistedCCFrameOrigin(url) {
  if (!url) return null;
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  if (parsed.protocol !== "https:" || parsed.port !== "") return null;
  return CC_FRAME_HOSTS.has(parsed.hostname.toLowerCase()) ? parsed.origin : null;
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

// Registered allowlisted payment frames of a tab as [frameId, origin] pairs.
function ccFramesFor(tabId) {
  const frames = ccFrameRegistry.get(tabId);
  return frames ? Array.from(frames.entries()) : [];
}

// Delivers an authorized payload into the tab. Identity fill is strictly a
// top-frame capability (explicit frameId 0 — never a broadcast, so no other
// frame's listener ever sees the values). Card fill ADDITIONALLY addresses
// each registered allowlisted payment frame by explicit frameId, with the
// expected frame origin pinned into the message so the frame self-verifies
// before writing (dual-side check). Returns aggregate counts or null.
async function deliverFill(tab, category, values) {
  const sends = [browser.tabs.sendMessage(tab.id, {
    cmd: "fillFields",
    origin: tab.origin,
    frameOrigin: tab.origin,
    category,
    values,
  }, { frameId: 0 })];
  if (category === "card") {
    for (const [frameId, frameOrigin] of ccFramesFor(tab.id)) {
      sends.push(browser.tabs.sendMessage(tab.id, {
        cmd: "fillFields",
        origin: tab.origin,
        frameOrigin,
        category,
        values,
      }, { frameId }));
    }
  }
  const results = await withTimeout(
    Promise.all(sends.map((send) => send.catch(() => null))),
    FILL_DELIVERY_TIMEOUT_MS,
  ).catch(() => null);
  if (!results) return null;
  let filled = 0;
  let skipped = 0;
  let delivered = false;
  for (const result of results) {
    if (!result || result.ok !== true || !result.data) continue;
    delivered = true;
    filled += Number(result.data.filled) || 0;
    skipped += Number(result.data.skipped) || 0;
  }
  return delivered ? { filled, skipped } : null;
}

// Shared authorized-fill core (popup Fill tap and inline-menu tap): native
// getFillPayload for ONE item, an origin re-check on the pinned tab AFTER
// the (possibly slow, Face ID gated) native round-trip, then delivery. The
// payload lives in locals only and is dropped after dispatch. Only aggregate
// counts ever return toward JS callers, never values.
async function authorizeAndDeliver(tab, itemId, category) {
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
    const counts = await deliverFill(tab, category, values);
    if (!counts) {
      return { v: PROTOCOL_VERSION, ok: false, error: "fillFailed" };
    }
    return { v: PROTOCOL_VERSION, ok: true, data: counts };
  } finally {
    values = null;
  }
}

// Popup "Fill" tap → one of the TWO user surfaces that move field values
// toward a page (the other is the inline menu below; both funnel through
// `authorizeAndDeliver`). Tab-id pinning: the tab id and origin are captured
// BEFORE the native request and re-checked after it — a payload never
// reaches a tab whose origin changed since the user acted. The content
// script re-checks origin again as a belt.
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

  return authorizeAndDeliver(tab, itemId, category);
}

// Inline-menu tap → the second user surface into `authorizeAndDeliver`.
// The origin comes exclusively from the trusted sender tab (top frame only),
// and the sender must be the ACTIVE tab: a hidden background tab must never
// be able to summon Face ID or receive values. The native side still gates
// the payload behind the session/Face ID like every vault operation.
async function handleInlineFillItem(message, sender) {
  const origin = contentSenderOrigin(sender);
  if (!origin) return { v: PROTOCOL_VERSION, ok: false, error: "forbidden" };
  if (!sender.tab.active) return { v: PROTOCOL_VERSION, ok: false, error: "forbidden" };
  const itemId = typeof message.itemId === "string" ? message.itemId : "";
  const category = message.category === "card" || message.category === "identity"
    ? message.category
    : "";
  if (!itemId || !category) return { v: PROTOCOL_VERSION, ok: false, error: "malformedMessage" };
  return authorizeAndDeliver({ id: sender.tab.id, origin }, itemId, category);
}

// Inline-menu metadata: identities and cards ONLY (never logins — the menu
// must never become credential UI), served from the per-tab cache or the
// session-only native list. A locked vault yields `locked: true` and no
// items; focusing a field can never summon Face ID.
async function handleInlineItems(sender) {
  const origin = contentSenderOrigin(sender);
  if (!origin) return { v: PROTOCOL_VERSION, ok: false, error: "forbidden" };
  const tabId = sender.tab.id;
  const cached = inlineItemsCache.get(tabId);
  if (cached && cached.origin === origin) {
    return {
      v: PROTOCOL_VERSION,
      ok: true,
      data: {
        hidden: cached.hidden === true,
        identities: cached.identities,
        cards: cached.cards,
      },
    };
  }
  const reply = await sendNative({ v: PROTOCOL_VERSION, cmd: "listItemsSession", origin });
  if (!reply || reply.ok !== true || !reply.data) {
    if (reply && reply.error === "locked") {
      return {
        v: PROTOCOL_VERSION,
        ok: true,
        data: { locked: true, identities: [], cards: [] },
      };
    }
    if (reply && reply.error === "hiddenSite") {
      // Per-site kill switch, decided natively. Cache the verdict so a
      // hidden host never re-hits native on every focus.
      inlineItemsCache.set(tabId, { origin, hidden: true, identities: [], cards: [] });
      return {
        v: PROTOCOL_VERSION,
        ok: true,
        data: { hidden: true, identities: [], cards: [] },
      };
    }
    return {
      v: PROTOCOL_VERSION,
      ok: false,
      error: reply && reply.error ? String(reply.error) : "nativeError",
    };
  }
  // Rebuild with whitelisted metadata keys only — nothing else crosses
  // toward the page's content-script world.
  const identities = (Array.isArray(reply.data.identities) ? reply.data.identities : [])
    .map((identity) => ({
      id: String(identity.id || ""),
      title: String(identity.title || ""),
    }));
  const cards = (Array.isArray(reply.data.cards) ? reply.data.cards : [])
    .map((card) => ({
      id: String(card.id || ""),
      title: String(card.title || ""),
      brand: String(card.brand || ""),
      last4: String(card.last4 || ""),
    }));
  inlineItemsCache.set(tabId, { origin, identities, cards });
  return { v: PROTOCOL_VERSION, ok: true, data: { identities, cards } };
}

// Payment-frame announcement. EVERYTHING is re-derived from the trusted
// sender: tab id, frame id, and the frame's own URL — the message carries
// nothing. Registration requires an https top-level page and a frame origin
// on the CC allowlist; the registry is bounded as a belt.
const MAX_CC_FRAMES_PER_TAB = 32;
function handleCCFrameHello(sender) {
  if (!sender || !sender.tab || typeof sender.tab.id !== "number"
      || typeof sender.frameId !== "number" || sender.frameId <= 0) {
    return { v: PROTOCOL_VERSION, ok: false, error: "forbidden" };
  }
  if (!httpsOriginOf(sender.tab.url)) {
    return { v: PROTOCOL_VERSION, ok: false, error: "forbidden" };
  }
  const frameOrigin = allowlistedCCFrameOrigin(sender.url);
  if (!frameOrigin) {
    return { v: PROTOCOL_VERSION, ok: false, error: "forbidden" };
  }
  let frames = ccFrameRegistry.get(sender.tab.id);
  if (!frames) {
    frames = new Map();
    ccFrameRegistry.set(sender.tab.id, frames);
  }
  if (frames.size >= MAX_CC_FRAMES_PER_TAB && !frames.has(sender.frameId)) {
    return { v: PROTOCOL_VERSION, ok: false, error: "forbidden" };
  }
  frames.set(sender.frameId, frameOrigin);
  return { v: PROTOCOL_VERSION, ok: true, data: { registered: true } };
}

// Field-map summary (counts per category plus the signup page type, nothing
// else) so the popup can enable its Fill buttons and the signup-assist
// action. Card counts additionally include the registered allowlisted
// payment frames (asked one by one via explicit frameId) so the card Fill
// button lights up on iframe-based checkouts. A page without the content
// script (e.g. loaded before install) simply reports zero fillable fields.
async function handleClassifyPage() {
  const tab = await activeHTTPSTab();
  if (!tab) return { v: PROTOCOL_VERSION, ok: false, error: "unsupportedPage" };
  const topSend = browser.tabs
    .sendMessage(tab.id, { cmd: "classifyPage" }, { frameId: 0 })
    .catch(() => null);
  const frameSends = ccFramesFor(tab.id).map(([frameId, frameOrigin]) =>
    browser.tabs
      .sendMessage(tab.id, { cmd: "classifyFrame", frameOrigin }, { frameId })
      .catch(() => null));
  const [reply, ...frameReplies] = await Promise.all([topSend, ...frameSends]);
  const summary = reply && reply.ok === true && reply.data ? reply.data : {};
  let frameCards = 0;
  for (const frameReply of frameReplies) {
    if (frameReply && frameReply.ok === true && frameReply.data) {
      frameCards += Number(frameReply.data.card) || 0;
    }
  }
  const actionable = summary.pageType === "signup" || summary.pageType === "changePassword";
  return {
    v: PROTOCOL_VERSION,
    ok: true,
    data: {
      identity: Number(summary.identity) || 0,
      card: (Number(summary.card) || 0) + frameCards,
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
      }, { frameId: 0 }),
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

// Per-site kill switch, popup read side: is the extension's in-page UI
// hidden on the active tab's host? Bare hostnames only, never vault data.
async function handleSiteSettings() {
  const tab = await activeHTTPSTab();
  if (!tab) return { v: PROTOCOL_VERSION, ok: false, error: "unsupportedPage" };
  return sendNative({ v: PROTOCOL_VERSION, cmd: "siteSettings", origin: tab.origin });
}

// Per-site kill switch, popup write side (hide AND show live here — the
// popup is the only surface that can re-enable a hidden site). Consent
// binding mirrors handleFillItem: the toggle applies to the origin the
// popup displayed, never to a tab that navigated cross-origin since.
async function handleSetSiteHidden(message) {
  const tab = await activeHTTPSTab();
  if (!tab) return { v: PROTOCOL_VERSION, ok: false, error: "unsupportedPage" };
  const expectedOrigin = typeof message.expectedOrigin === "string"
    ? message.expectedOrigin
    : "";
  if (!expectedOrigin || expectedOrigin !== tab.origin) {
    return { v: PROTOCOL_VERSION, ok: false, error: "tabChanged" };
  }
  const hidden = message.hidden === true;
  // Drop stale inline metadata everywhere so the new verdict is re-fetched.
  inlineItemsCache.clear();
  return sendNative({ v: PROTOCOL_VERSION, cmd: "setSiteHidden", origin: tab.origin, hidden });
}

// Inline-menu footer "Hide on this site": HIDE-only, origin pinned to the
// trusted sender tab. Content scripts can never un-hide a site.
async function handleHideSite(sender) {
  const origin = contentSenderOrigin(sender);
  if (!origin) return { v: PROTOCOL_VERSION, ok: false, error: "forbidden" };
  inlineItemsCache.delete(sender.tab.id);
  return sendNative({ v: PROTOCOL_VERSION, cmd: "setSiteHidden", origin, hidden: true });
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

  if (CONTENT_INLINE_COMMANDS.has(message.cmd)) {
    if (message.cmd === "ccFrameHello") return Promise.resolve(handleCCFrameHello(sender));
    if (message.cmd === "inlineItems") return handleInlineItems(sender);
    if (message.cmd === "hideSite") return handleHideSite(sender);
    return handleInlineFillItem(message, sender);
  }

  if (message.cmd === "siteSettings") {
    return handleSiteSettings();
  }

  if (message.cmd === "setSiteHidden") {
    return handleSetSiteHidden(message);
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
