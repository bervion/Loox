// Pure, DOM-free classification of form-field descriptors into fill targets.
// Tiered evidence, strongest first: (1) WHATWG autocomplete tokens,
// (2) input type / inputmode, (3) name/id/placeholder/label/aria-label
// keyword tables covering English AND Vietnamese (diacritic-insensitive),
// (4) form context (a generic name field inside a form that also holds a
// card-number field is the cardholder name).
//
// SECURITY: descriptors carry attributes only — never a user-typed value —
// so classification leaks nothing from the page. The fill engine re-checks
// everything at fill moment; classification alone authorizes nothing.
(function () {
  "use strict";

  const CARD_KEYS = new Set(["ccName", "ccNumber", "ccExp", "ccExpMonth", "ccExpYear", "ccCsc"]);

  // Tier 1: autocomplete tokens (authoritative per the WHATWG autofill spec).
  const AUTOCOMPLETE_KEYS = {
    "name": "fullName",
    "given-name": "givenName",
    "family-name": "familyName",
    "email": "email",
    "tel": "phone",
    "tel-national": "phone",
    "street-address": "address",
    "address-line1": "address",
    "cc-name": "ccName",
    "cc-number": "ccNumber",
    "cc-exp": "ccExp",
    "cc-exp-month": "ccExpMonth",
    "cc-exp-year": "ccExpYear",
    "cc-csc": "ccCsc",
  };

  // Fields that are clearly something else: never classify these as fill
  // targets even when a keyword matches ("Tên đăng nhập" is a username, not
  // a given name; search boxes match almost anything).
  // `[\s_-]*` between words because attribute text mixes spaces, dashes, and
  // underscores freely ("card_number", "so-dien-thoai", "Name on card").
  const EXCLUDE = /(user[\s_-]*name|\blogin\b|dang[\s_-]*nhap|tai[\s_-]*khoan|account|password|mat[\s_-]*khau|search|tim[\s_-]*kiem|\botp\b|captcha)/;

  // Tier 3: ordered keyword rules on normalized (lowercased, diacritics
  // stripped) attribute text. Order is load-bearing: card rules run before
  // identity rules ("cardholder name" must not read as a plain name field)
  // and email before address ("email address").
  const TEXT_RULES = [
    { key: "ccName", re: /(card[\s_-]*holder|holder[\s_-]*name|name[\s_-]*on[\s_-]*card|chu[\s_-]*the|ten[\s_-]*(tren|in)[\s_-]*the)/ },
    { key: "ccNumber", re: /(card[\s_-]*(number|num|no)\b|cc[\s_-]*num|\bpan\b|so[\s_-]*the)/ },
    { key: "ccCsc", re: /(\bcvc\b|\bcvv\b|\bcsc\b|\bcid\b|security[\s_-]*code|ma[\s_-]*bao[\s_-]*mat|ma[\s_-]*an[\s_-]*ninh)/ },
    { key: "ccExpMonth", re: /(exp\w*[\s_-]*month|thang[\s_-]*het[\s_-]*han|exp[\s_-]*mm\b)/ },
    { key: "ccExpYear", re: /(exp\w*[\s_-]*year|nam[\s_-]*het[\s_-]*han|exp[\s_-]*yy(yy)?\b)/ },
    { key: "ccExp", re: /(expir|exp[\s_-]+date|\bexp\b|valid[\s_-]*(thru|through|until)|het[\s_-]*han|mm[\s_-]*[/-][\s_-]*yy)/ },
    { key: "email", re: /(e[\s_-]*mail|thu[\s_-]*dien[\s_-]*tu)/ },
    { key: "phone", re: /(phone|mobile|\btel\b|dien[\s_-]*thoai|\bsdt\b|di[\s_-]*dong)/ },
    { key: "address", re: /(address|\bstreet\b|dia[\s_-]*chi)/ },
    { key: "fullName", re: /(full[\s_-]*name|your[\s_-]*name|ho[\s_-]*va[\s_-]*ten|ho[\s_-]*ten)/ },
    { key: "givenName", re: /(first[\s_-]*name|given[\s_-]*name|\bforename\b)/ },
    { key: "familyName", re: /(last[\s_-]*name|family[\s_-]*name|surname)/ },
  ];

  // Vietnamese single-word labels ("Họ", "Tên") are too short for substring
  // matching ("phone" contains "ho"), so they match whole tokens only.
  const VI_TOKEN_RULES = [
    { key: "familyName", token: "ho" },
    { key: "givenName", token: "ten" },
  ];

  // Input types eligible for fill at all. Passwords are NEVER a target of
  // this engine; hidden inputs are the classic exfiltration trap.
  const FILLABLE_INPUT_TYPES = new Set(["", "text", "email", "tel", "number"]);

  // Keys allowed per element tag: card secrets never target a textarea and a
  // select only ever carries expiry parts.
  const SELECT_KEYS = new Set(["ccExpMonth", "ccExpYear"]);
  const TEXTAREA_KEYS = new Set(["address"]);

  // Lowercase and strip Vietnamese diacritics so one table matches both
  // "Số thẻ" and "so the".
  function normalize(text) {
    return String(text || "")
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/đ/g, "d");
  }

  function autocompleteKey(descriptor) {
    const tokens = normalize(descriptor.autocomplete).split(/\s+/);
    for (const token of tokens) {
      if (Object.prototype.hasOwnProperty.call(AUTOCOMPLETE_KEYS, token)) {
        return AUTOCOMPLETE_KEYS[token];
      }
    }
    return null;
  }

  function typeKey(descriptor) {
    if (descriptor.tag !== "input") return null;
    const type = normalize(descriptor.type);
    const inputmode = normalize(descriptor.inputmode);
    if (type === "email" || inputmode === "email") return "email";
    if (type === "tel" || inputmode === "tel") return "phone";
    return null;
  }

  function evidenceText(descriptor) {
    return [descriptor.name, descriptor.elementId, descriptor.placeholder,
            descriptor.label, descriptor.ariaLabel]
      .map(normalize)
      .join(" | ");
  }

  function keywordKey(text) {
    for (const rule of TEXT_RULES) {
      if (rule.re.test(text)) return rule.key;
    }
    const tokens = text.split(/[^a-z0-9]+/).filter(Boolean);
    for (const rule of VI_TOKEN_RULES) {
      if (tokens.includes(rule.token)) return rule.key;
    }
    return null;
  }

  function keyAllowedOn(descriptor, key) {
    if (descriptor.tag === "select") return SELECT_KEYS.has(key);
    if (descriptor.tag === "textarea") return TEXTAREA_KEYS.has(key);
    return FILLABLE_INPUT_TYPES.has(normalize(descriptor.type));
  }

  function classifyOne(descriptor) {
    const text = evidenceText(descriptor);
    const autoKey = autocompleteKey(descriptor);
    if (autoKey && keyAllowedOn(descriptor, autoKey)) {
      return { key: autoKey, tier: 1 };
    }
    if (EXCLUDE.test(text)) return null;
    const byType = typeKey(descriptor);
    if (byType && keyAllowedOn(descriptor, byType)) {
      return { key: byType, tier: 2 };
    }
    const byKeyword = keywordKey(text);
    if (byKeyword && keyAllowedOn(descriptor, byKeyword)) {
      return { key: byKeyword, tier: 3 };
    }
    return null;
  }

  const CONFIDENCE = { 1: 1.0, 2: 0.9, 3: 0.6, 4: 0.5 };

  // descriptors: [{ id, tag, type, inputmode, autocomplete, name, elementId,
  //                 placeholder, label, ariaLabel, maxLength, form }]
  // → [{ id, key, category, tier, confidence, maxLength, tag }]
  function classify(descriptors) {
    const results = [];
    for (const descriptor of descriptors || []) {
      const match = classifyOne(descriptor);
      if (!match) continue;
      results.push({
        id: descriptor.id,
        key: match.key,
        category: CARD_KEYS.has(match.key) ? "card" : "identity",
        tier: match.tier,
        confidence: CONFIDENCE[match.tier],
        maxLength: typeof descriptor.maxLength === "number" ? descriptor.maxLength : null,
        tag: descriptor.tag,
        form: descriptor.form,
      });
    }
    applyFormContext(results);
    return results;
  }

  // Tier 4: inside a form that also holds a card-number field, a generic
  // full-name field is the cardholder name, not an identity target.
  function applyFormContext(results) {
    const cardForms = new Set();
    for (const entry of results) {
      if (entry.key === "ccNumber" && entry.form !== null && entry.form !== undefined) {
        cardForms.add(entry.form);
      }
    }
    for (const entry of results) {
      if (entry.key === "fullName" && cardForms.has(entry.form)) {
        entry.key = "ccName";
        entry.category = "card";
        entry.tier = 4;
        entry.confidence = CONFIDENCE[4];
      }
    }
  }

  // Counts per category so the popup can enable or disable its Fill buttons
  // without ever seeing field details.
  function summarize(classifications) {
    const summary = { identity: 0, card: 0 };
    for (const entry of classifications || []) {
      if (entry.category === "identity") summary.identity += 1;
      if (entry.category === "card") summary.card += 1;
    }
    return summary;
  }

  globalThis.LooxFieldClassifier = { classify, summarize, normalize };
})();
