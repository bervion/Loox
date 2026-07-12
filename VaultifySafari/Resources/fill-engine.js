// Writes authorized fill values into classified fields. Every write runs the
// full safety gauntlet AT FILL MOMENT (the page owns the DOM and may have
// mutated since classification):
//   1. https page (belt; the background page verified the origin too).
//   2. Element visible: rendered, opacity above 0.1, at least 10x10 px, not
//      display:none / visibility:hidden — hidden fields are the classic
//      credential-exfiltration trap and never receive a value.
//   3. Element editable: connected, not disabled or readonly.
//   4. Top frame only (enforced by content.js before this engine runs; the
//      manifest keeps all_frames off).
//   5. Card number / security code additionally require strong evidence:
//      an <input> classified from autocomplete or type (tiers 1-2), or a
//      keyword match corroborated by a plausible maxlength (13-19 for a PAN,
//      3-4 for a code). Never a textarea, never a select.
//
// Values reach the page through the native value setter plus synthetic
// input/change events so framework-controlled inputs (React, Vue) keep the
// value instead of silently reverting. No value is ever logged or included
// in the returned fill report.
(function () {
  "use strict";

  const CC_SECRET_KEYS = new Set(["ccNumber", "ccCsc"]);

  function pageIsHTTPS() {
    return location.protocol === "https:";
  }

  function isVisible(el) {
    if (!el.isConnected) return false;
    const style = getComputedStyle(el);
    if (style.display === "none" || style.visibility === "hidden") return false;
    if (parseFloat(style.opacity) <= 0.1) return false;
    const rect = el.getBoundingClientRect();
    if (rect.width < 10 || rect.height < 10) return false;
    // offsetParent is null for display:none subtrees; position:fixed elements
    // legitimately have no offsetParent, so allow those through on rect size.
    return el.offsetParent !== null || style.position === "fixed";
  }

  function isEditable(el) {
    return !el.disabled && !el.readOnly;
  }

  function inputTypeAllowed(el) {
    if (el.tagName !== "INPUT") return true;
    const type = (el.type || "text").toLowerCase();
    // Belt: the classifier already refuses these, but the DOM may have
    // changed the type attribute since classification.
    return type !== "hidden" && type !== "password";
  }

  function ccEvidenceStrongEnough(entry, el) {
    if (!CC_SECRET_KEYS.has(entry.key)) return true;
    if (el.tagName !== "INPUT") return false;
    if (entry.tier <= 2) return true;
    const max = el.maxLength;
    if (typeof max !== "number" || max <= 0) return false;
    return entry.key === "ccNumber" ? (max >= 13 && max <= 19) : (max >= 3 && max <= 4);
  }

  // Framework-safe write: the native prototype setter bypasses a framework's
  // own value property, then input/change events let its state catch up.
  function setNativeValue(el, value) {
    const proto = el.tagName === "TEXTAREA"
      ? HTMLTextAreaElement.prototype
      : HTMLInputElement.prototype;
    const descriptor = Object.getOwnPropertyDescriptor(proto, "value");
    try { el.focus({ preventScroll: true }); } catch { /* focus is best-effort */ }
    if (descriptor && descriptor.set) {
      descriptor.set.call(el, value);
    } else {
      el.value = value;
    }
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
  }

  // Select fill: match an option by value or visible text against any of the
  // candidate spellings ("09", "9" for a month; "2027", "27" for a year).
  function fillSelect(el, candidates) {
    const wanted = candidates.map((c) => String(c).toLowerCase());
    for (const option of Array.from(el.options)) {
      const value = String(option.value).trim().toLowerCase();
      const text = String(option.textContent).trim().toLowerCase();
      if (wanted.includes(value) || wanted.includes(text)) {
        el.value = option.value;
        el.dispatchEvent(new Event("change", { bubbles: true }));
        return true;
      }
    }
    return false;
  }

  function expiryForTarget(el, values) {
    const month = values.ccExpMonth || "";
    const year4 = values.ccExpYear || "";
    if (!month || !year4) return values.ccExp || null;
    const year2 = year4.slice(-2);
    const hints = ((el.getAttribute("placeholder") || "") + " "
      + (el.getAttribute("pattern") || "")).toLowerCase();
    const max = el.maxLength;
    if (max === 4) return month + year2;
    if (max === 6) return month + year4;
    if (max === 7 || hints.includes("yyyy")) return month + "/" + year4;
    return month + "/" + year2;
  }

  function selectCandidates(key, values) {
    if (key === "ccExpMonth") {
      const month = values.ccExpMonth || "";
      return month ? [month, String(parseInt(month, 10))] : [];
    }
    const year4 = values.ccExpYear || "";
    return year4 ? [year4, year4.slice(-2)] : [];
  }

  function valueForInput(key, values, el) {
    if (key === "ccExp") return expiryForTarget(el, values);
    if (key === "ccExpMonth") return values.ccExpMonth || null;
    if (key === "ccExpYear") {
      const year4 = values.ccExpYear || "";
      if (!year4) return null;
      return el.maxLength === 2 ? year4.slice(-2) : year4;
    }
    // A multiline address collapses for single-line inputs.
    if (key === "address" && el.tagName === "INPUT") {
      return String(values.address || "").replace(/\s*\n+\s*/g, ", ") || null;
    }
    return values[key] || null;
  }

  // entries: [{ id, key, tier, element }]; values: canonical key → value.
  // Returns a per-field report of { id, key, status, reason? } — never values.
  function fillAll(entries, values) {
    const report = [];
    const httpsOK = pageIsHTTPS();
    for (const entry of entries) {
      const el = entry.element;
      const result = { id: entry.id, key: entry.key, status: "skipped" };
      report.push(result);
      if (!httpsOK) { result.reason = "insecurePage"; continue; }
      if (!el || !el.isConnected) { result.reason = "gone"; continue; }
      if (!isVisible(el)) { result.reason = "notVisible"; continue; }
      if (!isEditable(el)) { result.reason = "notEditable"; continue; }
      if (!inputTypeAllowed(el)) { result.reason = "typeNotAllowed"; continue; }
      if (!ccEvidenceStrongEnough(entry, el)) { result.reason = "lowEvidence"; continue; }

      if (el.tagName === "SELECT") {
        const candidates = selectCandidates(entry.key, values);
        if (!candidates.length) { result.reason = "noValue"; continue; }
        result.status = fillSelect(el, candidates) ? "filled" : "skipped";
        if (result.status === "skipped") result.reason = "noMatchingOption";
        continue;
      }

      const value = valueForInput(entry.key, values, el);
      if (!value) { result.reason = "noValue"; continue; }
      setNativeValue(el, value);
      result.status = "filled";
    }
    return report;
  }

  globalThis.LooxFillEngine = { fillAll };
})();
