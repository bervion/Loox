// Signup / change-password page detection. Two layers: a pure, DOM-free
// `detect()` over attribute descriptors (node-testable) and a DOM `scan()`
// that builds those descriptors and maps results back to live elements.
// Login pages (a single current password) are deliberately NOT actionable:
// the OS QuickType bar owns standard logins, and this extension never
// renders inline credential UI for them.
//
// Tiered evidence, strongest first:
//   1  autocomplete="new-password" (authoritative WHATWG token)
//   3  single password field + signup/change submit label (EN + VI)
//   4  two or more password fields in one form (new password being set)
//
// Only VISIBLE password fields count: hidden honeypot inputs (anti-bot traps
// commonly planted next to a real login password) must not inflate a plain
// login page into a multi-password "signup". scan() reuses the fill engine's
// visibility gauntlet so detection and fill agree on what the user can see.
//
// SECURITY: descriptors are attribute-only — scan() never reads a field
// value. Values are read elsewhere and only at explicit submit intent
// (save-overlay.js) or written by the authorized generated-password fill.
// Requires field-classifier.js (normalize) and fill-engine.js (isVisible)
// to be loaded first.
(function () {
  "use strict";

  // Submit labels that mark account creation. Diacritics are stripped by
  // normalize(), so one table covers "Đăng ký" and "dang ky". "sign up" is
  // deliberately narrow: it must never match "sign in" / "đăng nhập".
  const SIGNUP_SUBMIT_RE = /(sign[\s_-]*up|register|create[\s_-]*(an[\s_-]*|your[\s_-]*|new[\s_-]*|my[\s_-]*)?account|join[\s_-]*now|dang[\s_-]*ky|tao[\s_-]*tai[\s_-]*khoan)/;
  const CHANGE_SUBMIT_RE = /((change|update|reset)[\s_-]*(my[\s_-]*|your[\s_-]*)?password|(doi|thay[\s_-]*doi|cap[\s_-]*nhat|dat[\s_-]*lai)[\s_-]*mat[\s_-]*khau)/;
  // Field-attribute evidence. "cu\b" (đổi "mật khẩu cũ") needs the boundary
  // so it never fires inside "của".
  const CURRENT_RE = /((current|old|existing)[\s_-]*password|mat[\s_-]*khau[\s_-]*(hien[\s_-]*tai|cu\b))/;
  const CONFIRM_RE = /(confirm|verif|re[\s_-]*type|re[\s_-]*enter|repeat|again|nhap[\s_-]*lai|xac[\s_-]*nhan)/;
  const NEW_RE = /(new[\s_-]*password|mat[\s_-]*khau[\s_-]*moi)/;
  const USER_FIELD_RE = /(user[\s_-]*name|e[\s_-]*mail|dang[\s_-]*nhap|tai[\s_-]*khoan)/;

  function normalize(text) {
    return globalThis.LooxFieldClassifier.normalize(text);
  }

  function textOf(field) {
    return [field.name, field.elementId, field.placeholder, field.label, field.ariaLabel]
      .map(normalize)
      .join(" | ");
  }

  function hasToken(autocomplete, wanted) {
    return normalize(autocomplete).split(/\s+/).includes(wanted);
  }

  // --- Pure detection --------------------------------------------------------

  // fields: [{ id, autocomplete, name, elementId, placeholder, label,
  //            ariaLabel, form, visible }] — password inputs only,
  //            attributes only. `visible: false` marks a field the user
  //            cannot see (honeypot); it never counts toward classification.
  //            Absent means visible (pure callers need not compute it).
  // context: { forms: [{ index, submitText, hasUserField }],
  //            pageSubmitText, pageHasUserField }
  // → { pageType: "none"|"login"|"signup"|"changePassword", tier, form,
  //     newPasswordIds } where `form` is the winning form index (null = no
  //     form) and newPasswordIds name the fields a NEW password belongs in.
  function detect(fields, context) {
    const forms = (context && context.forms) || [];
    const pageSubmitText = normalize((context && context.pageSubmitText) || "");
    const pageHasUserField = Boolean(context && context.pageHasUserField);

    const groups = new Map();
    for (const field of fields || []) {
      // Hidden honeypot fields (even token-bearing ones) are invisible to
      // the user and must be invisible to classification too.
      if (field.visible === false) continue;
      const key = field.form === null || field.form === undefined ? "page" : field.form;
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(field);
    }

    let best = { pageType: "none", tier: 0, form: null, newPasswordIds: [] };
    let bestRank = 0;
    for (const [key, group] of groups) {
      const formInfo = key === "page" ? null : forms.find((f) => f.index === key);
      const submitText = formInfo
        ? normalize(formInfo.submitText || "")
        : pageSubmitText;
      const hasUserField = formInfo ? Boolean(formInfo.hasUserField) : pageHasUserField;
      const result = classifyGroup(group, submitText, hasUserField);
      const rank = rankOf(result);
      if (rank > bestRank) {
        bestRank = rank;
        best = {
          pageType: result.pageType,
          tier: result.tier,
          form: key === "page" ? null : key,
          newPasswordIds: result.newPasswordIds,
        };
      }
    }
    return best;
  }

  function classifyGroup(group, submitText, hasUserField) {
    const infos = group.map((field) => {
      const text = textOf(field);
      return {
        id: field.id,
        isNewToken: hasToken(field.autocomplete, "new-password"),
        isCurrentToken: hasToken(field.autocomplete, "current-password"),
        isCurrentText: CURRENT_RE.test(text),
        isConfirm: CONFIRM_RE.test(text),
        isNewText: NEW_RE.test(text),
      };
    });
    const isCurrent = (info) => info.isCurrentToken
      || (info.isCurrentText && !info.isNewToken);
    const currents = infos.filter(isCurrent);
    const news = infos.filter((info) => info.isNewToken && !info.isCurrentToken);
    const nonCurrent = infos.filter((info) => !isCurrent(info));

    // Tier 1: an explicit new-password token decides the page type. Targets
    // are the token-bearing fields plus confirm/"new password" companions.
    if (news.length) {
      const companions = nonCurrent.filter(
        (info) => info.isNewToken || info.isConfirm || info.isNewText,
      );
      const ids = (companions.length ? companions : news).map((info) => info.id);
      const change = currents.length > 0 || CHANGE_SUBMIT_RE.test(submitText);
      return { pageType: change ? "changePassword" : "signup", tier: 1, newPasswordIds: ids };
    }

    // Tier 4: several password fields in one form means a new password is
    // being set. Old+new+confirm (3 fields), a current-password field, a
    // change-style submit label, or a userless new+confirm pair all read as
    // change-password; otherwise password+confirm on a signup form.
    if (infos.length >= 2) {
      const userlessNewPair = !hasUserField && infos.some((info) => info.isNewText);
      const change = currents.length > 0 || infos.length >= 3
        || CHANGE_SUBMIT_RE.test(submitText) || userlessNewPair;
      const ids = nonCurrent.map((info) => info.id);
      return { pageType: change ? "changePassword" : "signup", tier: 4, newPasswordIds: ids };
    }

    // Tier 3: a single password field is a signup/change only when the
    // surrounding evidence says so; otherwise it is a login and NOT ours.
    if (infos.length === 1) {
      const single = infos[0];
      if (isCurrent(single)) {
        return { pageType: "login", tier: 3, newPasswordIds: [] };
      }
      if (CHANGE_SUBMIT_RE.test(submitText)) {
        return { pageType: "changePassword", tier: 3, newPasswordIds: [single.id] };
      }
      if (SIGNUP_SUBMIT_RE.test(submitText)) {
        return { pageType: "signup", tier: 3, newPasswordIds: [single.id] };
      }
      if (single.isNewText) {
        // A lone "new password" field without a signup label is typically a
        // reset/change flow.
        return { pageType: "changePassword", tier: 3, newPasswordIds: [single.id] };
      }
      return { pageType: "login", tier: 3, newPasswordIds: [] };
    }
    return { pageType: "none", tier: 0, newPasswordIds: [] };
  }

  // Actionable page types win over login/none; among actionable results the
  // stronger (lower) tier wins.
  function rankOf(result) {
    if (result.pageType === "signup" || result.pageType === "changePassword") {
      return 10 + (5 - result.tier);
    }
    return result.pageType === "login" ? 1 : 0;
  }

  // --- DOM scan (attribute-only; no values) ----------------------------------

  function labelTextFor(element) {
    if (element.labels && element.labels.length) {
      return Array.from(element.labels).map((l) => l.textContent || "").join(" ");
    }
    const wrapping = element.closest("label");
    return wrapping ? (wrapping.textContent || "") : "";
  }

  // The fill engine's full visibility gauntlet (display/visibility, own and
  // ancestor opacity, minimum size, off-screen park). Manifest load order
  // guarantees fill-engine.js runs first; if it ever did not, fall open to
  // "visible" — classification is a UX gate, the fill path re-checks
  // visibility itself before any value is written.
  function isVisibleField(element) {
    const engine = globalThis.LooxFillEngine;
    if (engine && typeof engine.isVisible === "function") {
      return engine.isVisible(element);
    }
    return true;
  }

  function descriptorFor(element, index, forms) {
    return {
      id: index,
      autocomplete: element.getAttribute("autocomplete") || "",
      name: element.getAttribute("name") || "",
      elementId: element.id || "",
      placeholder: element.getAttribute("placeholder") || "",
      label: labelTextFor(element).slice(0, 200),
      ariaLabel: element.getAttribute("aria-label") || "",
      form: element.form ? forms.indexOf(element.form) : null,
      visible: isVisibleField(element),
    };
  }

  function buttonText(element) {
    if (element.tagName === "INPUT") return element.getAttribute("value") || "";
    const text = (element.textContent || "") + " " + (element.getAttribute("aria-label") || "");
    return text.slice(0, 300);
  }

  // Label evidence from every button in the form (SPA signup buttons often
  // carry type="button"), bounded so a pathological page cannot balloon it.
  function submitTextOfForm(form) {
    return Array.from(form.querySelectorAll('button, input[type="submit"]'))
      .map(buttonText)
      .join(" | ")
      .slice(0, 600);
  }

  function pageSubmitTextOf(root) {
    return Array.from(root.querySelectorAll("button"))
      .filter((element) => !element.form)
      .map(buttonText)
      .join(" | ")
      .slice(0, 600);
  }

  const SKIPPED_INPUT_TYPES = new Set([
    "password", "hidden", "checkbox", "radio", "submit",
    "button", "file", "image", "reset", "search",
  ]);

  // The username/email input a signup pairs with the new password. Strong
  // evidence (autocomplete token, type=email) wins; keyword text is the
  // fallback. Attribute checks only — the value is read at submit intent.
  function userFieldIn(scope) {
    let fallback = null;
    for (const element of Array.from(scope.querySelectorAll("input"))) {
      const type = (element.type || "text").toLowerCase();
      if (SKIPPED_INPUT_TYPES.has(type)) continue;
      const autocomplete = normalize(element.getAttribute("autocomplete") || "");
      if (/\b(username|email)\b/.test(autocomplete)) return element;
      if (type === "email") return element;
      if (!fallback) {
        const text = normalize([
          element.getAttribute("name") || "",
          element.id || "",
          element.getAttribute("placeholder") || "",
          labelTextFor(element),
          element.getAttribute("aria-label") || "",
        ].join(" | "));
        if (USER_FIELD_RE.test(text)) fallback = element;
      }
    }
    return fallback;
  }

  function emptyScan(pageType, tier) {
    return {
      pageType: pageType || "none",
      tier: tier || 0,
      form: null,
      newPasswordElements: [],
      usernameElement: null,
    };
  }

  // Classifies the live page and maps the winning descriptors back to
  // elements. Re-run at every decision moment (classification, fill, submit
  // intent) so a mutated page never acts on stale detection.
  function scan(doc) {
    const root = doc || document;
    const passwordEls = Array.from(root.querySelectorAll('input[type="password"]'));
    if (!passwordEls.length) return emptyScan();
    const forms = Array.from(root.querySelectorAll("form"));
    const fields = passwordEls.map((element, index) => descriptorFor(element, index, forms));
    const formInfos = forms.map((form, index) => ({
      index,
      submitText: submitTextOfForm(form),
      hasUserField: Boolean(userFieldIn(form)),
    }));
    const result = detect(fields, {
      forms: formInfos,
      pageSubmitText: pageSubmitTextOf(root),
      pageHasUserField: Boolean(userFieldIn(root)),
    });
    if (result.pageType !== "signup" && result.pageType !== "changePassword") {
      return emptyScan(result.pageType, result.tier);
    }
    const idSet = new Set(result.newPasswordIds);
    const formEl = result.form === null ? null : (forms[result.form] || null);
    return {
      pageType: result.pageType,
      tier: result.tier,
      form: formEl,
      newPasswordElements: passwordEls.filter((_, index) => idSet.has(index)),
      usernameElement: userFieldIn(formEl || root),
    };
  }

  function submitTextMatches(text) {
    const normalized = normalize(text);
    return SIGNUP_SUBMIT_RE.test(normalized) || CHANGE_SUBMIT_RE.test(normalized);
  }

  globalThis.LooxSignupDetector = { detect, scan, submitTextMatches };
})();
