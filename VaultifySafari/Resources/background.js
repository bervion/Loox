// Non-persistent background page (NOT a service worker: iOS Safari permanently
// kills MV3 service workers shortly after install). This page is the single
// message hub: popup and content scripts talk to it via runtime.sendMessage,
// and it alone relays to the native handler. Stateless by design because both
// this page and the native handler process are short-lived.

const NATIVE_COMMANDS = new Set(["echo", "ping"]);

browser.runtime.onMessage.addListener((message) => {
  if (!message || typeof message.cmd !== "string") {
    return Promise.resolve({ ok: false, error: "malformedMessage" });
  }

  if (NATIVE_COMMANDS.has(message.cmd)) {
    // On iOS the application id argument is ignored; messages always route to
    // this appex's own native handler.
    return browser.runtime
      .sendNativeMessage("application.id", message)
      .catch((error) => ({ ok: false, error: `native:${String(error)}` }));
  }

  return Promise.resolve({ ok: false, error: "unknownCommand" });
});
