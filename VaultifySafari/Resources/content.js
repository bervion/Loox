// Content-script endpoint for classify/fill. Runs ONLY in the top frame
// (cross-origin iframe fill is denied in v1: a hostile embedded frame must
// never receive vault values, and the manifest keeps all_frames off as a
// second lock). Messages arrive exclusively from this extension's background
// page via tabs.sendMessage — a web page cannot address runtime.onMessage.
//
// SECURITY: this script never requests vault data. It answers `classifyPage`
// with attribute-derived counts only (no field values, no user-typed
// content), and executes `fillFields` with values the background page
// obtained through the popup-authorized native flow. Classification is
// re-run at fill moment so a mutated or navigated-within page never receives
// values into stale or re-purposed elements. Nothing is logged.
(function () {
  "use strict";

  if (window.top !== window) return;

  // Stable per-load field ids: opaque integers via WeakMap, so no CSS
  // selector or DOM detail is ever serialized off the page.
  const fieldIds = new WeakMap();
  let nextFieldId = 1;

  function idFor(element) {
    let id = fieldIds.get(element);
    if (!id) {
      id = nextFieldId;
      nextFieldId += 1;
      fieldIds.set(element, id);
    }
    return id;
  }

  function labelTextFor(element) {
    if (element.labels && element.labels.length) {
      return Array.from(element.labels).map((l) => l.textContent || "").join(" ");
    }
    const wrapping = element.closest("label");
    return wrapping ? (wrapping.textContent || "") : "";
  }

  // Attribute-only descriptors: never a value property.
  function collectFields() {
    const elements = Array.from(document.querySelectorAll("input, select, textarea"));
    const forms = Array.from(document.forms);
    const items = [];
    for (const el of elements) {
      const tag = el.tagName.toLowerCase();
      if (tag === "input") {
        const type = (el.type || "text").toLowerCase();
        if (type === "hidden" || type === "password" || type === "checkbox"
            || type === "radio" || type === "submit" || type === "button"
            || type === "file" || type === "image" || type === "reset") continue;
      }
      items.push({
        element: el,
        descriptor: {
          id: idFor(el),
          tag,
          type: tag === "input" ? (el.type || "text") : "",
          inputmode: el.getAttribute("inputmode") || "",
          autocomplete: el.getAttribute("autocomplete") || "",
          name: el.getAttribute("name") || "",
          elementId: el.id || "",
          placeholder: el.getAttribute("placeholder") || "",
          label: labelTextFor(el).slice(0, 200),
          ariaLabel: el.getAttribute("aria-label") || "",
          maxLength: typeof el.maxLength === "number" && el.maxLength > 0 ? el.maxLength : null,
          form: el.form ? forms.indexOf(el.form) : null,
        },
      });
    }
    return items;
  }

  function classifyCurrentPage() {
    const items = collectFields();
    const classifications = globalThis.LooxFieldClassifier.classify(
      items.map((item) => item.descriptor),
    );
    const byId = new Map(items.map((item) => [item.descriptor.id, item.element]));
    return classifications.map((entry) => ({
      id: entry.id,
      key: entry.key,
      category: entry.category,
      tier: entry.tier,
      element: byId.get(entry.id) || null,
    }));
  }

  function handleClassify() {
    if (location.protocol !== "https:") {
      return { ok: false, error: "insecurePage" };
    }
    const summary = globalThis.LooxFieldClassifier.summarize(classifyCurrentPage());
    // Signup-assist hint for the popup: page type only, never field details.
    summary.pageType = globalThis.LooxSignupDetector.scan(document).pageType;
    return { ok: true, data: summary };
  }

  // Generated-password delivery (popup-authorized, background-constructed).
  // The value is a freshly generated password — never vault data — but it
  // runs the same gauntlet as any fill: https, origin pin, and signup
  // detection re-run AT FILL MOMENT so a page that mutated since the popup
  // classified it never receives the value into repurposed fields. The
  // fill-engine password path additionally re-checks visibility, editability,
  // and that each target is still a password input.
  function handleFillGeneratedPassword(message) {
    if (location.protocol !== "https:") return { ok: false, error: "insecurePage" };
    if (typeof message.origin !== "string" || message.origin !== location.origin) {
      return { ok: false, error: "originMismatch" };
    }
    const password = message.password;
    if (typeof password !== "string" || !password || password.length > 512) {
      return { ok: false, error: "malformedMessage" };
    }
    const scan = globalThis.LooxSignupDetector.scan(document);
    if (scan.pageType !== "signup" && scan.pageType !== "changePassword") {
      return { ok: true, data: { filled: 0, skipped: 0 } };
    }
    const entries = scan.newPasswordElements.map((element, index) => ({
      id: index + 1,
      element,
    }));
    const report = globalThis.LooxFillEngine.fillPasswordAll(entries, password);
    const filled = report.filter((r) => r.status === "filled").length;
    return { ok: true, data: { filled, skipped: report.length - filled } };
  }

  function handleFill(message) {
    // Belt checks; the background page already pinned tab id and origin.
    if (location.protocol !== "https:") return { ok: false, error: "insecurePage" };
    if (typeof message.origin !== "string" || message.origin !== location.origin) {
      return { ok: false, error: "originMismatch" };
    }
    const values = message.values;
    if (!values || typeof values !== "object") {
      return { ok: false, error: "malformedMessage" };
    }
    const category = message.category === "card" ? "card" : "identity";
    const targets = classifyCurrentPage().filter(
      (entry) => entry.category === category && entry.element,
    );
    const report = globalThis.LooxFillEngine.fillAll(targets, values);
    const filled = report.filter((r) => r.status === "filled").length;
    return { ok: true, data: { filled, skipped: report.length - filled } };
  }

  browser.runtime.onMessage.addListener((message) => {
    if (!message || typeof message.cmd !== "string") return undefined;
    if (message.cmd === "classifyPage") {
      return Promise.resolve(handleClassify());
    }
    if (message.cmd === "fillFields") {
      return Promise.resolve(handleFill(message));
    }
    if (message.cmd === "fillGeneratedPassword") {
      return Promise.resolve(handleFillGeneratedPassword(message));
    }
    return undefined;
  });
})();
