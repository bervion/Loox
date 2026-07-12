// Non-persistent background page (NOT a service worker: iOS Safari permanently
// kills MV3 service workers shortly after install). This page is the single
// message hub: popup and content scripts talk to it via runtime.sendMessage,
// and it alone relays to the native handler.
//
// SECURITY: native requests are rebuilt from scratch so only whitelisted keys
// cross the bridge, and the matching origin ALWAYS comes from the trusted
// browser.tabs API — a sender-supplied origin/URL is never forwarded.

const NATIVE_COMMANDS = new Set(["echo", "ping", "status", "listItems", "copyValue"]);
const PROTOCOL_VERSION = 1;

// Origin of the active tab when it is a well-formed https page; null otherwise
// (http, reader mode, about:/extension pages, no tab).
async function activeTabHTTPSOrigin() {
  const tabs = await browser.tabs.query({ active: true, currentWindow: true });
  const url = tabs && tabs[0] && tabs[0].url;
  if (!url) return null;
  try {
    const parsed = new URL(url);
    return parsed.protocol === "https:" ? parsed.origin : null;
  } catch {
    return null;
  }
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

browser.runtime.onMessage.addListener((message) => {
  if (!message || typeof message.cmd !== "string") {
    return reject("malformedMessage");
  }

  // Local (non-native) query so the popup can render the site chip and the
  // unsupported-page state without touching the vault.
  if (message.cmd === "activeTabOrigin") {
    return activeTabHTTPSOrigin().then((origin) => ({
      v: PROTOCOL_VERSION,
      ok: true,
      data: { origin },
    }));
  }

  if (!NATIVE_COMMANDS.has(message.cmd)) {
    return reject("unknownCommand");
  }

  if (message.cmd === "listItems") {
    return (async () => {
      const origin = await activeTabHTTPSOrigin();
      if (!origin) return { v: PROTOCOL_VERSION, ok: false, error: "unsupportedPage" };
      return sendNative({ v: PROTOCOL_VERSION, cmd: "listItems", origin });
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
