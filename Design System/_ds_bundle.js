/* @ds-bundle: {"format":3,"namespace":"VaultifyDesignSystem_ffd0d9","components":[{"name":"Badge","sourcePath":"components/core/Badge.jsx"},{"name":"Button","sourcePath":"components/core/Button.jsx"},{"name":"Card","sourcePath":"components/core/Card.jsx"},{"name":"Field","sourcePath":"components/core/Field.jsx"},{"name":"POLARIS_BASE","sourcePath":"components/core/Icon.jsx"},{"name":"ICON_MAP","sourcePath":"components/core/Icon.jsx"},{"name":"Icon","sourcePath":"components/core/Icon.jsx"},{"name":"IconButton","sourcePath":"components/core/IconButton.jsx"},{"name":"IconTile","sourcePath":"components/core/IconTile.jsx"},{"name":"Row","sourcePath":"components/core/Row.jsx"},{"name":"SectionHeader","sourcePath":"components/core/SectionHeader.jsx"},{"name":"SegmentedControl","sourcePath":"components/core/SegmentedControl.jsx"},{"name":"StrengthMeter","sourcePath":"components/core/StrengthMeter.jsx"},{"name":"Switch","sourcePath":"components/core/Switch.jsx"},{"name":"TabBar","sourcePath":"components/core/TabBar.jsx"}],"sourceHashes":{"components/core/Badge.jsx":"7977b3cbce50","components/core/Button.jsx":"fd968c598b98","components/core/Card.jsx":"96e148581d1e","components/core/Field.jsx":"8b949eea8e57","components/core/Icon.jsx":"b287935e2f51","components/core/IconButton.jsx":"778499dc2251","components/core/IconTile.jsx":"be1ab3823dea","components/core/Row.jsx":"1dfd374f388f","components/core/SectionHeader.jsx":"9cd230e52416","components/core/SegmentedControl.jsx":"afad4373f6d3","components/core/StrengthMeter.jsx":"62e6a0d4a034","components/core/Switch.jsx":"05b02e51a784","components/core/TabBar.jsx":"a577f0d507d8","ui_kits/ios-app/Appearance.jsx":"e4a7eed8c707","ui_kits/ios-app/ItemDetail.jsx":"995e784b513d","ui_kits/ios-app/UnlockScreen.jsx":"27de2e5da906","ui_kits/ios-app/Watchtower.jsx":"6b387930dd59","ui_kits/ios-app/app.jsx":"246fa3e8f33f","ui_kits/ios-app/kit-components.jsx":"1c0b0042dec3"},"inlinedExternals":[],"unexposedExports":[{"name":"fetchIconSvg","sourcePath":"components/core/Icon.jsx"},{"name":"iconUrl","sourcePath":"components/core/Icon.jsx"},{"name":"resolveIcon","sourcePath":"components/core/Icon.jsx"}]} */

(() => {

const __ds_ns = (window.VaultifyDesignSystem_ffd0d9 = window.VaultifyDesignSystem_ffd0d9 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/core/Badge.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Badge — alert dot or compact counter. Non-text contrast safe. */
function Badge({
  count,
  dot = false,
  tone = 'destructive',
  // destructive | accent | neutral | success | warning
  max = 99,
  style,
  ...rest
}) {
  const toneBg = {
    destructive: 'var(--destructive)',
    accent: 'var(--accent)',
    neutral: 'var(--icon-secondary)',
    success: 'var(--success)',
    warning: 'var(--warning)'
  }[tone] || 'var(--destructive)';
  if (dot) {
    return /*#__PURE__*/React.createElement("span", _extends({
      "aria-hidden": "true",
      style: {
        display: 'inline-block',
        width: 8,
        height: 8,
        borderRadius: '50%',
        background: toneBg,
        boxShadow: '0 0 0 2px var(--surface-base)',
        ...style
      }
    }, rest));
  }
  const text = typeof count === 'number' && count > max ? `${max}+` : count;
  return /*#__PURE__*/React.createElement("span", _extends({
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      minWidth: 18,
      height: 18,
      padding: '0 5px',
      borderRadius: 'var(--radius-pill)',
      background: toneBg,
      color: '#fff',
      fontFamily: 'var(--font-text)',
      fontSize: 11,
      fontWeight: 'var(--weight-bold)',
      lineHeight: 1,
      fontVariantNumeric: 'tabular-nums',
      ...style
    }
  }, rest), text);
}
Object.assign(__ds_scope, { Badge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Badge.jsx", error: String((e && e.message) || e) }); }

// components/core/Card.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Card — standard surface container. Use for grouping or affordance,
   not as decoration. Grouped list rows live inside variant="grouped". */
function Card({
  children,
  variant = 'base',
  // base | elevated | grouped | floating
  radius = 'var(--radius-lg)',
  padding = 'var(--space-4)',
  style,
  ...rest
}) {
  const surfaces = {
    base: {
      background: 'var(--surface-base)',
      boxShadow: 'var(--hairline)'
    },
    elevated: {
      background: 'var(--surface-elevated)',
      boxShadow: 'var(--elevation-2)'
    },
    grouped: {
      background: 'var(--surface-base)',
      boxShadow: 'var(--hairline)',
      padding: 0
    },
    floating: {
      background: 'var(--surface-floating)',
      boxShadow: 'var(--elevation-3)',
      backdropFilter: 'blur(20px) saturate(1.6)',
      WebkitBackdropFilter: 'blur(20px) saturate(1.6)'
    }
  };
  const v = surfaces[variant] || surfaces.base;
  return /*#__PURE__*/React.createElement("div", _extends({
    style: {
      borderRadius: radius,
      padding: variant === 'grouped' ? 0 : padding,
      overflow: variant === 'grouped' ? 'hidden' : 'visible',
      ...v,
      ...style
    }
  }, rest), children);
}
Object.assign(__ds_scope, { Card });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Card.jsx", error: String((e && e.message) || e) }); }

// components/core/Icon.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* ============================================================
   Vaultify Icon system
   Renders Shopify Polaris icons (v7.13.0) loaded from the unpkg
   CDN and recolored via CSS mask, so a single semantic color
   token drives the glyph — exactly like an SF Symbols family.

   Use semantic names from ICON_MAP, or pass any Polaris filename
   stem directly (e.g. name="LockMajor").
   ============================================================ */

const POLARIS_BASE = 'https://unpkg.com/@shopify/polaris-icons@7.13.0/dist/svg/';

// Semantic name -> Polaris file stem. Outline + filled where it exists.
const ICON_MAP = {
  // Navigation / tabs
  home: 'HomeMajor',
  'home.fill': 'HomeFilledMinor',
  items: 'CollectionsMajor',
  'items.fill': 'CollectionsFilledMajor',
  watchtower: 'FraudProtectMajor',
  search: 'SearchMinor',
  categories: 'CategoriesMajor',
  // Item types
  login: 'KeyMajor',
  password: 'KeyMajor',
  card: 'CreditCardMajor',
  identity: 'IdentityCardMajor',
  note: 'ContentMinor',
  email: 'EmailMajor',
  website: 'GlobeMajor',
  bank: 'BankMajor',
  wifi: 'GlobeMajor',
  // Actions
  copy: 'DuplicateMinor',
  view: 'ViewMinor',
  hide: 'HideMinor',
  edit: 'EditMinor',
  delete: 'DeleteMinor',
  add: 'AddMajor',
  'add.circle': 'CirclePlusMinor',
  refresh: 'RefreshMajor',
  filter: 'FilterMajor',
  settings: 'SettingsMajor',
  profile: 'CustomersMajor',
  exit: 'ExitMajor',
  more: 'HorizontalDotsMinor',
  share: 'ExportMinor',
  external: 'ExternalMinor',
  // Chevrons / direction
  'chevron.right': 'ChevronRightMinor',
  'chevron.left': 'ChevronLeftMinor',
  'chevron.down': 'ChevronDownMinor',
  'chevron.up': 'ChevronUpMinor',
  // Status
  lock: 'LockMajor',
  unlock: 'KeyMajor',
  success: 'CircleTickMajor',
  alert: 'AlertMinor',
  warning: 'DiamondAlertMajor',
  info: 'InfoMinor',
  favorite: 'FavoriteMajor',
  clock: 'ClockMajor'
};
function resolveIcon(name) {
  return ICON_MAP[name] || name;
}
function iconUrl(name) {
  return `${POLARIS_BASE}${resolveIcon(name)}.svg`;
}

// Fetch + cache raw SVG markup so glyphs render as real DOM SVG
// (recolorable via `fill`, and visible to screenshot/export renderers).
const _svgCache = {};
function fetchIconSvg(url) {
  if (!_svgCache[url]) {
    _svgCache[url] = fetch(url).then(r => r.ok ? r.text() : '').catch(() => '');
  }
  return _svgCache[url];
}
function Icon({
  name,
  size = 'var(--icon-inline)',
  color = 'currentColor',
  decorative = true,
  label,
  style,
  className,
  ...rest
}) {
  const ref = React.useRef(null);
  const url = iconUrl(name);
  const dim = typeof size === 'number' ? `${size}px` : size;
  React.useEffect(() => {
    let alive = true;
    fetchIconSvg(url).then(txt => {
      if (!alive || !ref.current || !txt) return;
      ref.current.innerHTML = txt;
      const svg = ref.current.querySelector('svg');
      if (svg) {
        svg.setAttribute('width', '100%');
        svg.setAttribute('height', '100%');
        svg.style.display = 'block';
        svg.style.fill = color;
      }
    });
    return () => {
      alive = false;
    };
  }, [url, color]);
  return /*#__PURE__*/React.createElement("span", _extends({
    ref: ref,
    role: decorative ? undefined : 'img',
    "aria-hidden": decorative ? 'true' : undefined,
    "aria-label": decorative ? undefined : label || name,
    className: className,
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      flex: '0 0 auto',
      width: dim,
      height: dim,
      color,
      ...style
    }
  }, rest));
}
Object.assign(__ds_scope, { POLARIS_BASE, ICON_MAP, resolveIcon, iconUrl, fetchIconSvg, Icon });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Icon.jsx", error: String((e && e.message) || e) }); }

// components/core/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Button — primary / secondary / ghost / destructive, three sizes.
   Native-feeling press: subtle scale + deepened fill. */
const SIZES = {
  sm: {
    h: 'var(--control-h-sm)',
    px: 14,
    font: 'var(--size-subhead)',
    radius: 'var(--radius-sm)',
    gap: 6
  },
  md: {
    h: 'var(--control-h-md)',
    px: 18,
    font: 'var(--size-body)',
    radius: 'var(--radius-sm)',
    gap: 8
  },
  lg: {
    h: 'var(--control-h-lg)',
    px: 22,
    font: 'var(--size-body)',
    radius: 'var(--radius-md)',
    gap: 8
  }
};
function variantStyle(variant, pressed) {
  switch (variant) {
    case 'secondary':
      return {
        background: pressed ? 'var(--surface-pressed)' : 'var(--surface-base)',
        color: 'var(--text-primary)',
        boxShadow: 'inset 0 0 0 1px var(--separator)'
      };
    case 'ghost':
      return {
        background: pressed ? 'var(--surface-pressed)' : 'transparent',
        color: 'var(--accent)',
        boxShadow: 'none'
      };
    case 'destructive':
      return {
        background: pressed ? 'var(--destructive-soft)' : 'var(--destructive-soft)',
        color: 'var(--destructive)',
        boxShadow: 'none',
        filter: pressed ? 'brightness(0.96)' : 'none'
      };
    case 'primary':
    default:
      return {
        background: pressed ? 'var(--accent-press)' : 'var(--accent)',
        color: 'var(--on-accent)',
        boxShadow: 'none'
      };
  }
}
function Button({
  children,
  variant = 'primary',
  size = 'md',
  fullWidth = false,
  leadingIcon,
  trailingIcon,
  disabled = false,
  type = 'button',
  style,
  onClick,
  ...rest
}) {
  const [pressed, setPressed] = React.useState(false);
  const s = SIZES[size] || SIZES.md;
  const vs = variantStyle(variant, pressed && !disabled);
  return /*#__PURE__*/React.createElement("button", _extends({
    type: type,
    disabled: disabled,
    onClick: onClick,
    onPointerDown: () => setPressed(true),
    onPointerUp: () => setPressed(false),
    onPointerLeave: () => setPressed(false),
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      gap: s.gap,
      width: fullWidth ? '100%' : 'auto',
      minHeight: s.h,
      padding: `0 ${s.px}px`,
      border: 'none',
      borderRadius: s.radius,
      fontFamily: 'var(--font-text)',
      fontSize: s.font,
      fontWeight: 'var(--weight-semibold)',
      letterSpacing: 'var(--tracking-normal)',
      lineHeight: 1,
      cursor: disabled ? 'default' : 'pointer',
      opacity: disabled ? 0.4 : 1,
      transform: pressed && !disabled ? 'scale(var(--press-scale))' : 'scale(1)',
      transition: 'transform var(--dur-fast) var(--ease-standard), background var(--dur-fast) var(--ease-standard)',
      WebkitTapHighlightColor: 'transparent',
      ...vs,
      ...style
    }
  }, rest), leadingIcon && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: leadingIcon,
    size: s.font === 'var(--size-subhead)' ? 16 : 18,
    color: "currentColor"
  }), children, trailingIcon && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: trailingIcon,
    size: s.font === 'var(--size-subhead)' ? 16 : 18,
    color: "currentColor"
  }));
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Button.jsx", error: String((e && e.message) || e) }); }

// components/core/Field.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Field — labeled text input, iOS grouped style.
   Supports leading icon, secure (password) mode with reveal,
   monospace values, and a custom trailing slot (e.g. copy button). */
function Field({
  label,
  value,
  defaultValue,
  onChange,
  placeholder,
  type = 'text',
  leadingIcon,
  secure = false,
  revealable = false,
  mono = false,
  trailing,
  disabled = false,
  readOnly = false,
  style,
  inputStyle,
  ...rest
}) {
  const [revealed, setRevealed] = React.useState(false);
  const isSecure = secure && !revealed;
  const inputType = isSecure ? 'password' : type === 'password' ? 'text' : type;
  return /*#__PURE__*/React.createElement("label", _extends({
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 6,
      opacity: disabled ? 0.5 : 1,
      ...style
    }
  }, rest), label && /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 'var(--size-footnote)',
      fontWeight: 'var(--weight-medium)',
      color: 'var(--text-secondary)',
      paddingLeft: 2
    }
  }, label), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-2)',
      minHeight: 'var(--control-h-lg)',
      padding: '0 var(--space-3)',
      background: 'var(--surface-base)',
      borderRadius: 'var(--radius-sm)',
      boxShadow: 'inset 0 0 0 1px var(--separator)'
    }
  }, leadingIcon && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: leadingIcon,
    size: 20,
    color: "var(--icon-secondary)"
  }), /*#__PURE__*/React.createElement("input", {
    type: inputType,
    value: value,
    defaultValue: defaultValue,
    onChange: onChange,
    placeholder: placeholder,
    disabled: disabled,
    readOnly: readOnly,
    style: {
      flex: 1,
      minWidth: 0,
      border: 'none',
      outline: 'none',
      background: 'transparent',
      color: 'var(--text-primary)',
      fontFamily: mono ? 'var(--font-mono)' : 'var(--font-text)',
      fontSize: 'var(--size-body)',
      letterSpacing: mono && isSecure ? '0.12em' : 'normal',
      fontVariantNumeric: mono ? 'tabular-nums' : 'normal',
      ...inputStyle
    }
  }), revealable && /*#__PURE__*/React.createElement("button", {
    type: "button",
    "aria-label": revealed ? 'Hide' : 'Reveal',
    onClick: () => setRevealed(r => !r),
    style: {
      display: 'inline-flex',
      border: 'none',
      background: 'none',
      padding: 4,
      cursor: 'pointer',
      WebkitTapHighlightColor: 'transparent'
    }
  }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: revealed ? 'hide' : 'view',
    size: 20,
    color: "var(--icon-secondary)"
  })), trailing));
}
Object.assign(__ds_scope, { Field });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Field.jsx", error: String((e && e.message) || e) }); }

// components/core/IconButton.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* IconButton — icon-only control. Always requires `label` (a11y). */
const IB_SIZES = {
  sm: {
    box: 32,
    icon: 18
  },
  md: {
    box: 44,
    icon: 22
  },
  lg: {
    box: 48,
    icon: 24
  }
};
function IconButton({
  name,
  label,
  size = 'md',
  variant = 'plain',
  // plain | filled | tinted
  color = 'var(--icon-primary)',
  disabled = false,
  style,
  onClick,
  ...rest
}) {
  const [pressed, setPressed] = React.useState(false);
  const s = IB_SIZES[size] || IB_SIZES.md;
  const bg = variant === 'filled' ? 'var(--accent)' : variant === 'tinted' ? 'var(--surface-pressed)' : pressed ? 'var(--surface-pressed)' : 'transparent';
  const fg = variant === 'filled' ? 'var(--on-accent)' : color;
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    "aria-label": label,
    disabled: disabled,
    onClick: onClick,
    onPointerDown: () => setPressed(true),
    onPointerUp: () => setPressed(false),
    onPointerLeave: () => setPressed(false),
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      width: s.box,
      height: s.box,
      minWidth: 'var(--hit-min)',
      minHeight: 'var(--hit-min)',
      padding: 0,
      border: 'none',
      borderRadius: variant === 'plain' ? 'var(--radius-sm)' : 'var(--radius-pill)',
      background: bg,
      cursor: disabled ? 'default' : 'pointer',
      opacity: disabled ? 0.4 : 1,
      transform: pressed && !disabled ? 'scale(var(--press-scale))' : 'scale(1)',
      transition: 'transform var(--dur-fast) var(--ease-standard), background var(--dur-fast) var(--ease-standard)',
      WebkitTapHighlightColor: 'transparent',
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: name,
    size: s.icon,
    color: fg
  }));
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/IconButton.jsx", error: String((e && e.message) || e) }); }

// components/core/IconTile.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* IconTile — rounded, tinted square holding a single icon.
   The standard leading element for list rows and item lists. */
function IconTile({
  name,
  tint = 'var(--accent)',
  onTint = 'var(--on-accent)',
  size = 'var(--icon-tile)',
  iconSize,
  radius = 'var(--radius-sm)',
  soft = false,
  // soft = tinted background + colored glyph
  style,
  ...rest
}) {
  const dim = typeof size === 'number' ? `${size}px` : size;
  const glyph = iconSize || `calc(${typeof size === 'number' ? dim : '1px * 0 + ' + dim} * 0.62)`;
  const bg = soft ? `color-mix(in srgb, ${tint} 16%, transparent)` : tint;
  const fg = soft ? tint : onTint;
  return /*#__PURE__*/React.createElement("span", _extends({
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      width: dim,
      height: dim,
      flex: '0 0 auto',
      borderRadius: radius,
      background: bg,
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: name,
    size: iconSize || `calc(${dim} * 0.6)`,
    color: fg
  }));
}
Object.assign(__ds_scope, { IconTile });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/IconTile.jsx", error: String((e && e.message) || e) }); }

// components/core/Row.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Row — the workhorse grouped-list row.
   leading (e.g. <IconTile/>) · title + optional subtitle ·
   trailing value text · chevron / custom trailing control. */
function Row({
  leading,
  title,
  subtitle,
  value,
  trailing,
  chevron = false,
  tone = 'default',
  // default | accent | destructive
  divider = true,
  // inset hairline at bottom (off for last row)
  onClick,
  style,
  ...rest
}) {
  const [pressed, setPressed] = React.useState(false);
  const interactive = !!onClick;
  const titleColor = tone === 'destructive' ? 'var(--destructive)' : tone === 'accent' ? 'var(--accent)' : 'var(--text-primary)';
  return /*#__PURE__*/React.createElement("div", _extends({
    role: interactive ? 'button' : undefined,
    tabIndex: interactive ? 0 : undefined,
    onClick: onClick,
    onPointerDown: () => interactive && setPressed(true),
    onPointerUp: () => setPressed(false),
    onPointerLeave: () => setPressed(false),
    style: {
      position: 'relative',
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-3)',
      minHeight: 'var(--row-h)',
      padding: '10px var(--space-4)',
      background: pressed ? 'var(--surface-pressed)' : 'transparent',
      cursor: interactive ? 'pointer' : 'default',
      transition: 'background var(--dur-fast) var(--ease-standard)',
      WebkitTapHighlightColor: 'transparent',
      ...style
    }
  }, rest), leading, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0,
      display: 'flex',
      flexDirection: 'column',
      gap: 1
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 'var(--size-headline)',
      fontWeight: 'var(--weight-medium)',
      color: titleColor,
      lineHeight: 'var(--lh-headline)',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, title), subtitle && /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 'var(--size-subhead)',
      color: 'var(--text-secondary)',
      lineHeight: 'var(--lh-subhead)',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, subtitle)), value != null && /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 'var(--size-callout)',
      color: 'var(--text-secondary)',
      flex: '0 0 auto',
      maxWidth: '45%',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, value), trailing, chevron && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: "chevron.right",
    size: 16,
    color: "var(--icon-disabled)"
  }), divider && /*#__PURE__*/React.createElement("span", {
    "aria-hidden": "true",
    style: {
      position: 'absolute',
      left: leading ? 'calc(var(--space-4) + var(--icon-tile) + var(--space-3))' : 'var(--space-4)',
      right: 0,
      bottom: 0,
      height: 0.5,
      background: 'var(--separator)'
    }
  }));
}
Object.assign(__ds_scope, { Row });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Row.jsx", error: String((e && e.message) || e) }); }

// components/core/SectionHeader.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* SectionHeader — grouped-list section label. Quiet, uppercase-ish
   caption with optional trailing action (text or icon button). */
function SectionHeader({
  title,
  action,
  onAction,
  actionIcon,
  uppercase = true,
  style,
  ...rest
}) {
  return /*#__PURE__*/React.createElement("div", _extends({
    style: {
      display: 'flex',
      alignItems: 'flex-end',
      justifyContent: 'space-between',
      gap: 'var(--space-3)',
      padding: `0 var(--space-1) var(--space-2)`,
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 'var(--size-footnote)',
      fontWeight: 'var(--weight-semibold)',
      letterSpacing: uppercase ? '0.4px' : 'var(--tracking-normal)',
      textTransform: uppercase ? 'uppercase' : 'none',
      color: 'var(--text-tertiary)'
    }
  }, title), action && /*#__PURE__*/React.createElement("button", {
    type: "button",
    onClick: onAction,
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 4,
      border: 'none',
      background: 'none',
      padding: 0,
      cursor: 'pointer',
      fontFamily: 'var(--font-text)',
      fontSize: 'var(--size-footnote)',
      fontWeight: 'var(--weight-semibold)',
      color: 'var(--accent)',
      WebkitTapHighlightColor: 'transparent'
    }
  }, action, actionIcon && /*#__PURE__*/React.createElement(__ds_scope.Icon, {
    name: actionIcon,
    size: 14,
    color: "var(--accent)"
  })));
}
Object.assign(__ds_scope, { SectionHeader });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/SectionHeader.jsx", error: String((e && e.message) || e) }); }

// components/core/SegmentedControl.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* SegmentedControl — iOS segmented picker.
   options: [{value,label}] or string[]. */
function SegmentedControl({
  options = [],
  value,
  onChange,
  style,
  ...rest
}) {
  const opts = options.map(o => typeof o === 'string' ? {
    value: o,
    label: o
  } : o);
  const idx = Math.max(0, opts.findIndex(o => o.value === value));
  return /*#__PURE__*/React.createElement("div", _extends({
    role: "tablist",
    style: {
      position: 'relative',
      display: 'grid',
      gridTemplateColumns: `repeat(${opts.length}, 1fr)`,
      gap: 2,
      padding: 2,
      background: 'color-mix(in srgb, var(--text-primary) 8%, transparent)',
      borderRadius: 'var(--radius-sm)',
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("span", {
    "aria-hidden": "true",
    style: {
      position: 'absolute',
      top: 2,
      bottom: 2,
      left: `calc(${idx} * (100% - 4px) / ${opts.length} + 2px)`,
      width: `calc((100% - 4px) / ${opts.length})`,
      background: 'var(--surface-base)',
      borderRadius: 'calc(var(--radius-sm) - 2px)',
      boxShadow: '0 1px 3px var(--shadow-ambient)',
      transition: 'left var(--dur-base) var(--ease-standard)'
    }
  }), opts.map(o => {
    const active = o.value === value;
    return /*#__PURE__*/React.createElement("button", {
      key: o.value,
      type: "button",
      role: "tab",
      "aria-selected": active,
      onClick: () => onChange && onChange(o.value),
      style: {
        position: 'relative',
        zIndex: 1,
        minHeight: 32,
        border: 'none',
        background: 'transparent',
        cursor: 'pointer',
        WebkitTapHighlightColor: 'transparent',
        fontFamily: 'var(--font-text)',
        fontSize: 'var(--size-subhead)',
        fontWeight: active ? 'var(--weight-semibold)' : 'var(--weight-medium)',
        color: active ? 'var(--text-primary)' : 'var(--text-secondary)',
        transition: 'color var(--dur-fast) var(--ease-standard)'
      }
    }, o.label);
  }));
}
Object.assign(__ds_scope, { SegmentedControl });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/SegmentedControl.jsx", error: String((e && e.message) || e) }); }

// components/core/StrengthMeter.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* StrengthMeter — password / vault health strength.
   score: 0 (empty) … 4 (strong). Four segments, color-coded. */
const LEVELS = [{
  label: 'Too weak',
  color: 'var(--destructive)'
}, {
  label: 'Weak',
  color: 'var(--destructive)'
}, {
  label: 'Fair',
  color: 'var(--warning)'
}, {
  label: 'Good',
  color: 'var(--accent)'
}, {
  label: 'Strong',
  color: 'var(--success)'
}];
function StrengthMeter({
  score = 0,
  showLabel = true,
  label,
  style,
  ...rest
}) {
  const s = Math.max(0, Math.min(4, score));
  const lvl = LEVELS[s];
  return /*#__PURE__*/React.createElement("div", _extends({
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 6,
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 5
    }
  }, [1, 2, 3, 4].map(seg => /*#__PURE__*/React.createElement("span", {
    key: seg,
    style: {
      flex: 1,
      height: 4,
      borderRadius: 'var(--radius-pill)',
      background: seg <= s ? lvl.color : 'color-mix(in srgb, var(--text-primary) 12%, transparent)',
      transition: 'background var(--dur-base) var(--ease-standard)'
    }
  }))), showLabel && /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 'var(--size-footnote)',
      fontWeight: 'var(--weight-medium)',
      color: lvl.color
    }
  }, label || lvl.label));
}
Object.assign(__ds_scope, { StrengthMeter });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/StrengthMeter.jsx", error: String((e && e.message) || e) }); }

// components/core/Switch.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Switch — iOS toggle. accent fill when on. */
function Switch({
  checked = false,
  onChange,
  disabled = false,
  label,
  style,
  ...rest
}) {
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    role: "switch",
    "aria-checked": checked,
    "aria-label": label,
    disabled: disabled,
    onClick: () => !disabled && onChange && onChange(!checked),
    style: {
      position: 'relative',
      width: 51,
      height: 31,
      flex: '0 0 auto',
      padding: 0,
      border: 'none',
      borderRadius: 'var(--radius-pill)',
      background: checked ? 'var(--accent)' : 'color-mix(in srgb, var(--text-primary) 18%, transparent)',
      cursor: disabled ? 'default' : 'pointer',
      opacity: disabled ? 0.5 : 1,
      transition: 'background var(--dur-base) var(--ease-standard)',
      WebkitTapHighlightColor: 'transparent',
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("span", {
    "aria-hidden": "true",
    style: {
      position: 'absolute',
      top: 2,
      left: checked ? 22 : 2,
      width: 27,
      height: 27,
      borderRadius: '50%',
      background: '#fff',
      boxShadow: '0 1px 3px rgba(0,0,0,0.28), 0 0 1px rgba(0,0,0,0.2)',
      transition: 'left var(--dur-base) var(--ease-standard)'
    }
  }));
}
Object.assign(__ds_scope, { Switch });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Switch.jsx", error: String((e && e.message) || e) }); }

// components/core/TabBar.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* VaultTabBar — custom, icon-only, floating tab bar.
   - No visible labels (labels live in aria only)
   - Compact sliding pill marks the active tab (Apple/Threads feel)
   - Solid fallback by default; glass control layer when `glass`
   - Meaningful badges only (dot or compact counter)
   tabs: [{ id, icon, iconFill?, label, badge?, badgeDot? }] */
function TabBar({
  tabs = [],
  value,
  onChange,
  glass = false,
  style,
  ...rest
}) {
  const idx = Math.max(0, tabs.findIndex(t => t.id === value));
  const n = tabs.length || 1;
  return /*#__PURE__*/React.createElement("nav", _extends({
    "aria-label": "Primary",
    style: {
      position: 'relative',
      display: 'grid',
      gridTemplateColumns: `repeat(${n}, 1fr)`,
      alignItems: 'center',
      height: 'var(--tabbar-height)',
      padding: '0 6px',
      borderRadius: 'var(--tabbar-radius)',
      background: glass ? 'var(--surface-floating)' : 'var(--surface-floating-solid)',
      backdropFilter: glass ? 'blur(24px) saturate(1.8)' : 'none',
      WebkitBackdropFilter: glass ? 'blur(24px) saturate(1.8)' : 'none',
      boxShadow: 'var(--elevation-3), var(--hairline)',
      ...style
    }
  }, rest), /*#__PURE__*/React.createElement("span", {
    "aria-hidden": "true",
    style: {
      position: 'absolute',
      top: '50%',
      height: 44,
      width: 46,
      transform: 'translateY(-50%)',
      left: `calc(${idx} * (100% - 12px) / ${n} + (100% - 12px) / ${n} / 2 - 23px + 6px)`,
      background: 'var(--accent-soft)',
      borderRadius: 'var(--radius-pill)',
      transition: 'left var(--dur-medium) var(--ease-spring)'
    }
  }), tabs.map(t => {
    const active = t.id === value;
    const iconName = active && t.iconFill ? t.iconFill : t.icon;
    return /*#__PURE__*/React.createElement("button", {
      key: t.id,
      type: "button",
      role: "tab",
      "aria-selected": active,
      "aria-label": t.label,
      onClick: () => onChange && onChange(t.id),
      style: {
        position: 'relative',
        zIndex: 1,
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        minWidth: 56,
        minHeight: 48,
        height: '100%',
        border: 'none',
        background: 'transparent',
        cursor: 'pointer',
        padding: 0,
        WebkitTapHighlightColor: 'transparent'
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        position: 'relative',
        display: 'inline-flex'
      }
    }, /*#__PURE__*/React.createElement(__ds_scope.Icon, {
      name: iconName,
      size: active ? 'var(--icon-tab)' : 24,
      color: active ? 'var(--accent)' : 'var(--icon-secondary)',
      style: {
        transition: 'background-color var(--dur-base) var(--ease-standard)'
      }
    }), (t.badge != null || t.badgeDot) && /*#__PURE__*/React.createElement("span", {
      style: {
        position: 'absolute',
        top: -3,
        right: -8
      }
    }, /*#__PURE__*/React.createElement(__ds_scope.Badge, {
      dot: t.badgeDot,
      count: t.badge,
      tone: "destructive"
    }))));
  }));
}
Object.assign(__ds_scope, { TabBar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/TabBar.jsx", error: String((e && e.message) || e) }); }

// ui_kits/ios-app/Appearance.jsx
try { (() => {
/* Appearance & security settings — live theming (Telegram-style). */
const ACCENTS = [{
  id: 'blue',
  light: '#2563eb',
  dark: '#4c8dff'
}, {
  id: 'indigo',
  light: '#5145cd',
  dark: '#8b80ff'
}, {
  id: 'teal',
  light: '#0e8a7d',
  dark: '#2fd0bf'
}, {
  id: 'purple',
  light: '#7c3aed',
  dark: '#b388ff'
}, {
  id: 'pink',
  light: '#d6256e',
  dark: '#ff77ab'
}, {
  id: 'graphite',
  light: '#4b4b50',
  dark: '#aeaeb2'
}, {
  id: 'mono',
  light: '#1c1c1e',
  dark: '#ffffff'
}];
function Appearance({
  theme,
  setTheme,
  accent,
  setAccent,
  onClose
}) {
  const [faceId, setFaceId] = React.useState(true);
  const [lockSwitch, setLockSwitch] = React.useState(true);
  const isDark = theme === 'dark';
  return /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minHeight: 0,
      overflowY: 'auto',
      background: 'var(--background-grouped)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'sticky',
      top: 0,
      zIndex: 10,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '4px var(--space-3)',
      minHeight: 44,
      background: 'color-mix(in srgb, var(--background-grouped) 82%, transparent)',
      backdropFilter: 'blur(12px)',
      WebkitBackdropFilter: 'blur(12px)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 17,
      fontWeight: 600,
      color: 'var(--text-primary)'
    }
  }, "Giao di\u1EC7n"), /*#__PURE__*/React.createElement("button", {
    onClick: onClose,
    style: {
      border: 'none',
      background: 'none',
      cursor: 'pointer',
      color: 'var(--accent)',
      fontFamily: 'var(--font-text)',
      fontSize: 17,
      fontWeight: 600,
      padding: '8px 10px'
    }
  }, "Xong")), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '8px var(--screen-gutter) var(--tabbar-bottom-pad)',
      display: 'flex',
      flexDirection: 'column',
      gap: 24
    }
  }, /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Ch\u1EBF \u0111\u1ED9"
  }), /*#__PURE__*/React.createElement(SegmentedControl, {
    value: theme,
    onChange: setTheme,
    options: [{
      value: 'light',
      label: 'Sáng'
    }, {
      value: 'dark',
      label: 'Tối'
    }]
  })), /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "M\xE0u nh\u1EA5n"
  }), /*#__PURE__*/React.createElement(Card, {
    padding: "18px"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      justifyContent: 'space-between'
    }
  }, ACCENTS.map(a => {
    const sel = a.id === accent;
    const sw = isDark ? a.dark : a.light;
    const lightSwatch = parseInt(sw.slice(1, 3), 16) * 0.299 + parseInt(sw.slice(3, 5), 16) * 0.587 + parseInt(sw.slice(5, 7), 16) * 0.114 > 150;
    return /*#__PURE__*/React.createElement("button", {
      key: a.id,
      onClick: () => setAccent(a.id),
      "aria-label": a.id,
      style: {
        width: 42,
        height: 42,
        borderRadius: '50%',
        cursor: 'pointer',
        padding: 0,
        border: lightSwatch ? '1px solid var(--separator)' : 'none',
        background: sw,
        position: 'relative',
        WebkitTapHighlightColor: 'transparent',
        boxShadow: sel ? `0 0 0 3px var(--surface-base), 0 0 0 5px ${sw}` : 'none',
        transition: 'box-shadow var(--dur-fast)'
      }
    }, sel && /*#__PURE__*/React.createElement(Icon, {
      name: "success",
      size: 20,
      color: lightSwatch ? '#1c1c1e' : '#fff',
      style: {
        position: 'absolute',
        inset: 0,
        margin: 'auto'
      }
    }));
  }))), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: '8px 4px 0',
      fontFamily: 'var(--font-text)',
      fontSize: 13,
      color: 'var(--text-tertiary)',
      textWrap: 'pretty'
    }
  }, "M\xE0u nh\u1EA5n \xE1p d\u1EE5ng t\u1EE9c th\xEC cho to\xE0n b\u1ED9 \u1EE9ng d\u1EE5ng \u2014 kh\xF4ng c\u1EA7n kh\u1EDFi \u0111\u1ED9ng l\u1EA1i.")), /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "B\u1EA3o m\u1EADt"
  }), /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, /*#__PURE__*/React.createElement(Row, {
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: "unlock",
      tint: "var(--accent)"
    }),
    title: "M\u1EDF kho\xE1 b\u1EB1ng Face ID",
    trailing: /*#__PURE__*/React.createElement(Switch, {
      checked: faceId,
      onChange: setFaceId,
      label: "Face ID"
    })
  }), /*#__PURE__*/React.createElement(Row, {
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: "lock",
      tint: "var(--icon-secondary)",
      soft: true
    }),
    title: "Kho\xE1 khi chuy\u1EC3n \u1EE9ng d\u1EE5ng",
    trailing: /*#__PURE__*/React.createElement(Switch, {
      checked: lockSwitch,
      onChange: setLockSwitch,
      label: "Kho\xE1 khi chuy\u1EC3n"
    })
  }), /*#__PURE__*/React.createElement(Row, {
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: "clock",
      tint: "var(--icon-secondary)",
      soft: true
    }),
    title: "T\u1EF1 \u0111\u1ED9ng kho\xE1",
    value: "Sau 1 ph\xFAt",
    chevron: true,
    divider: false,
    onClick: () => {}
  }))), /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, /*#__PURE__*/React.createElement(Row, {
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: "exit",
      tint: "var(--destructive)",
      soft: true
    }),
    title: "Kho\xE1 kho ngay",
    tone: "destructive",
    divider: false,
    onClick: onClose
  })))));
}
window.Appearance = Appearance;
window.ACCENTS = ACCENTS;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/ios-app/Appearance.jsx", error: String((e && e.message) || e) }); }

// ui_kits/ios-app/ItemDetail.jsx
try { (() => {
/* Item detail — credential view: space, copyable fields, password reveal +
   strength, live TOTP, and password-rotation status. */
function CopyField({
  label,
  value,
  mono,
  secure
}) {
  const [revealed, setRevealed] = React.useState(!secure);
  const [copied, setCopied] = React.useState(false);
  const display = secure && !revealed ? '••••••••••••' : value;
  function copy() {
    setCopied(true);
    setTimeout(() => setCopied(false), 1100);
  }
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      display: 'flex',
      alignItems: 'center',
      gap: 10,
      minHeight: 58,
      padding: '8px var(--space-4)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0,
      display: 'flex',
      flexDirection: 'column',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 13,
      fontWeight: 500,
      color: 'var(--text-secondary)'
    }
  }, label), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: mono ? 'var(--font-mono)' : 'var(--font-text)',
      fontSize: 17,
      color: 'var(--text-primary)',
      letterSpacing: mono ? secure && !revealed ? '0.16em' : '0.04em' : 'normal',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, display)), secure && /*#__PURE__*/React.createElement(IconButton, {
    name: revealed ? 'hide' : 'view',
    label: revealed ? 'Ẩn' : 'Hiện',
    size: "sm",
    color: "var(--icon-secondary)",
    onClick: () => setRevealed(r => !r)
  }), /*#__PURE__*/React.createElement(IconButton, {
    name: copied ? 'success' : 'copy',
    label: "Sao ch\xE9p",
    size: "sm",
    color: copied ? 'var(--success)' : 'var(--accent)',
    onClick: copy
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      left: 'var(--space-4)',
      right: 0,
      bottom: 0,
      height: 0.5,
      background: 'var(--separator)'
    }
  }));
}

/* Live TOTP row inside the detail */
function TotpField({
  seed
}) {
  const {
    code,
    remaining,
    progress
  } = useTotp(seed);
  const [copied, setCopied] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", {
    onClick: () => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1100);
    },
    role: "button",
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12,
      minHeight: 62,
      padding: '8px var(--space-4)',
      cursor: 'pointer'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 13,
      fontWeight: 500,
      color: 'var(--text-secondary)'
    }
  }, "M\xE3 x\xE1c th\u1EF1c (2FA)"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-mono)',
      fontSize: 24,
      fontWeight: 600,
      letterSpacing: '0.1em',
      color: copied ? 'var(--success)' : 'var(--accent)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, copied ? 'Đã sao chép' : fmtCode(code))), /*#__PURE__*/React.createElement(TotpRing, {
    progress: progress,
    remaining: remaining,
    size: 34
  }));
}
function ItemDetail({
  item,
  onBack
}) {
  const sp = (window.spaceById || (() => null))(item.space);
  const rot = (window.rotationStatus || (() => ({
    state: 'ok'
  })))(item);
  const rotColor = rot.tone === 'destructive' ? 'var(--destructive)' : rot.tone === 'warning' ? 'var(--warning)' : 'var(--text-secondary)';
  return /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minHeight: 0,
      overflowY: 'auto',
      background: 'var(--background-grouped)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'sticky',
      top: 0,
      zIndex: 10,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '4px var(--space-2)',
      minHeight: 44,
      background: 'color-mix(in srgb, var(--background-grouped) 82%, transparent)',
      backdropFilter: 'blur(12px)',
      WebkitBackdropFilter: 'blur(12px)'
    }
  }, /*#__PURE__*/React.createElement("button", {
    onClick: onBack,
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 2,
      border: 'none',
      background: 'none',
      cursor: 'pointer',
      color: 'var(--accent)',
      fontFamily: 'var(--font-text)',
      fontSize: 17,
      padding: '8px'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "chevron.left",
    size: 20,
    color: "var(--accent)"
  }), " Kho"), /*#__PURE__*/React.createElement("button", {
    style: {
      border: 'none',
      background: 'none',
      cursor: 'pointer',
      color: 'var(--accent)',
      fontFamily: 'var(--font-text)',
      fontSize: 17,
      padding: '8px 12px'
    }
  }, "S\u1EEDa")), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      padding: '8px 0 20px'
    }
  }, /*#__PURE__*/React.createElement(IconTile, {
    name: item.icon,
    tint: item.tint,
    size: 72,
    radius: "var(--radius-lg)",
    iconSize: 38
  }), /*#__PURE__*/React.createElement("h1", {
    style: {
      margin: '14px 0 6px',
      fontFamily: 'var(--font-display)',
      fontSize: 24,
      fontWeight: 700,
      letterSpacing: '-0.4px',
      color: 'var(--text-primary)'
    }
  }, item.name), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8
    }
  }, sp && /*#__PURE__*/React.createElement(SpaceTag, {
    space: sp,
    size: "md"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 15,
      color: 'var(--text-secondary)'
    }
  }, item.url || item.username))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 var(--screen-gutter)',
      display: 'flex',
      flexDirection: 'column',
      gap: 22,
      paddingBottom: 'calc(var(--tabbar-bottom-pad) + 8px)'
    }
  }, rot.state !== 'ok' && /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12,
      padding: '14px var(--space-4)',
      borderRadius: 'var(--radius-lg)',
      background: rot.tone === 'destructive' ? 'var(--destructive-soft)' : 'var(--warning-soft)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: rot.icon,
    size: 22,
    color: rotColor
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 15,
      fontWeight: 600,
      color: rotColor
    }
  }, rot.label), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 13,
      color: 'var(--text-secondary)'
    }
  }, item.rotateDays > 0 ? `Nhắc đổi mỗi ${item.rotateDays} ngày` : 'Nên cập nhật mật khẩu mới')), /*#__PURE__*/React.createElement(Button, {
    size: "sm",
    variant: rot.tone === 'destructive' ? 'primary' : 'secondary',
    onClick: () => {}
  }, "\u0110\u1ED5i")), /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, /*#__PURE__*/React.createElement(CopyField, {
    label: "T\xEAn \u0111\u0103ng nh\u1EADp",
    value: item.username
  }), /*#__PURE__*/React.createElement(CopyField, {
    label: "M\u1EADt kh\u1EA9u",
    value: item.password,
    mono: true,
    secure: true
  }), item.totp && /*#__PURE__*/React.createElement(TotpField, {
    seed: item.totp
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '12px var(--space-4) 14px'
    }
  }, /*#__PURE__*/React.createElement(StrengthMeter, {
    score: item.score,
    label: item.scoreLabel
  }))), /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, item.url && /*#__PURE__*/React.createElement(Row, {
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: "website",
      tint: "var(--icon-secondary)",
      soft: true
    }),
    title: "M\u1EDF trang web",
    value: item.url,
    tone: "accent",
    chevron: true,
    onClick: () => {}
  }), /*#__PURE__*/React.createElement(Row, {
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: "clock",
      tint: "var(--icon-secondary)",
      soft: true
    }),
    title: "\u0110\u1ED5i g\u1EA7n nh\u1EA5t",
    value: item.changed >= 30 ? `${Math.round(item.changed / 30)} tháng trước` : `${item.changed} ngày trước`,
    divider: item.rotateDays > 0
  }), item.rotateDays > 0 && /*#__PURE__*/React.createElement(Row, {
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: "refresh",
      tint: "var(--accent)",
      soft: true
    }),
    title: "Nh\u1EAFc \u0111\u1ED5i m\u1EADt kh\u1EA9u",
    value: `Mỗi ${item.rotateDays} ngày`,
    chevron: true,
    divider: false,
    onClick: () => {}
  })), /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, /*#__PURE__*/React.createElement(Row, {
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: "favorite",
      tint: "#d6256e",
      soft: true
    }),
    title: "Y\xEAu th\xEDch",
    trailing: /*#__PURE__*/React.createElement(Switch, {
      checked: !!item.fav,
      onChange: () => {},
      label: "Y\xEAu th\xEDch"
    })
  }), /*#__PURE__*/React.createElement(Row, {
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: "delete",
      tint: "var(--destructive)",
      soft: true
    }),
    title: "Xo\xE1 m\u1EE5c",
    tone: "destructive",
    divider: false,
    onClick: () => {}
  }))));
}
window.ItemDetail = ItemDetail;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/ios-app/ItemDetail.jsx", error: String((e && e.message) || e) }); }

// ui_kits/ios-app/UnlockScreen.jsx
try { (() => {
/* Unlock screen — master password + biometric, the app's front door. */
function UnlockScreen({
  onUnlock
}) {
  const [pw, setPw] = React.useState('');
  return /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      padding: '0 28px',
      background: 'var(--background-base)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: '0 0 auto',
      height: 96
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      width: 84,
      height: 84,
      borderRadius: 22,
      background: 'var(--accent)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      boxShadow: '0 12px 30px color-mix(in srgb, var(--accent) 40%, transparent)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "lock",
    size: 42,
    color: "var(--on-accent)"
  })), /*#__PURE__*/React.createElement("h1", {
    style: {
      margin: '22px 0 4px',
      fontFamily: 'var(--font-display)',
      fontSize: 28,
      fontWeight: 700,
      letterSpacing: '-0.4px',
      color: 'var(--text-primary)'
    }
  }, "Vaultify"), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: 0,
      fontFamily: 'var(--font-text)',
      fontSize: 15,
      color: 'var(--text-secondary)'
    }
  }, "M\u1EDF kho\xE1 kho c\u1EE7a b\u1EA1n"), /*#__PURE__*/React.createElement("div", {
    style: {
      width: '100%',
      marginTop: 40,
      display: 'flex',
      flexDirection: 'column',
      gap: 14
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 10,
      minHeight: 52,
      padding: '0 16px',
      background: 'var(--surface-base)',
      borderRadius: 'var(--radius-sm)',
      boxShadow: 'inset 0 0 0 1px var(--separator)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "unlock",
    size: 20,
    color: "var(--icon-secondary)"
  }), /*#__PURE__*/React.createElement("input", {
    type: "password",
    value: pw,
    onChange: e => setPw(e.target.value),
    placeholder: "M\u1EADt kh\u1EA9u ch\xEDnh",
    autoFocus: true,
    style: {
      flex: 1,
      minWidth: 0,
      border: 'none',
      outline: 'none',
      background: 'transparent',
      color: 'var(--text-primary)',
      fontFamily: 'var(--font-mono)',
      fontSize: 17,
      letterSpacing: '0.12em'
    }
  })), /*#__PURE__*/React.createElement(Button, {
    fullWidth: true,
    size: "lg",
    onClick: onUnlock,
    disabled: pw.length < 1
  }, "M\u1EDF kho\xE1")), /*#__PURE__*/React.createElement("button", {
    onClick: onUnlock,
    style: {
      marginTop: 'auto',
      marginBottom: 44,
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      gap: 10,
      border: 'none',
      background: 'none',
      cursor: 'pointer'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 58,
      height: 58,
      borderRadius: 16,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      background: 'var(--surface-pressed)'
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: "32",
    height: "32",
    viewBox: "0 0 32 32",
    fill: "none",
    stroke: "var(--accent)",
    strokeWidth: "2.2",
    strokeLinecap: "round",
    strokeLinejoin: "round",
    "aria-hidden": "true"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M5 10V7a2 2 0 0 1 2-2h3M22 5h3a2 2 0 0 1 2 2v3M27 22v3a2 2 0 0 1-2 2h-3M10 27H7a2 2 0 0 1-2-2v-3"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M12 13v2M20 13v2M16 13v4l-1.5 1.5"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M12 21c1.2 1 2.5 1.4 4 1.4s2.8-.4 4-1.4"
  }))), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 14,
      fontWeight: 600,
      color: 'var(--accent)'
    }
  }, "M\u1EDF b\u1EB1ng Face ID")));
}
window.UnlockScreen = UnlockScreen;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/ios-app/UnlockScreen.jsx", error: String((e && e.message) || e) }); }

// ui_kits/ios-app/Watchtower.jsx
try { (() => {
/* Watchtower — vault health & monitoring report. */
function ScoreRing({
  value = 82
}) {
  // ---- speedometer geometry: 270° arc, open at the bottom ----
  const W = 232,
    H = 196,
    CX = W / 2,
    CY = 104,
    R = 86,
    BAND = 18;
  const START = 135,
    SWEEP = 270;
  const f = Math.max(0, Math.min(1, value / 100));
  const polar = (rad, deg) => {
    const a = deg * Math.PI / 180;
    return [CX + rad * Math.cos(a), CY + rad * Math.sin(a)];
  };
  const arc = (rad, d0, d1) => {
    const [x0, y0] = polar(rad, d0),
      [x1, y1] = polar(rad, d1);
    const large = d1 - d0 > 180 ? 1 : 0;
    return `M ${x0.toFixed(2)} ${y0.toFixed(2)} A ${rad} ${rad} 0 ${large} 1 ${x1.toFixed(2)} ${y1.toFixed(2)}`;
  };
  const endDeg = START + SWEEP * f;
  // gradient-position colour at the fill tip (green → blue)
  const lerp = (a, b, t) => Math.round(a + (b - a) * t);
  const hex = t => `rgb(${lerp(0x16, 0x38, t)},${lerp(0xA3, 0xBD, t)},${lerp(0x4A, 0xF8, t)})`;
  const tip = hex(f);
  // ticks
  const NT = 44;
  const ticks = [];
  for (let i = 0; i <= NT; i++) {
    const deg = START + SWEEP * (i / NT);
    const major = i % 4 === 0;
    const L = major ? 11 : 8;
    const [ax, ay] = polar(R - L / 2, deg),
      [bx, by] = polar(R + L / 2, deg);
    ticks.push({
      ax,
      ay,
      bx,
      by,
      w: major ? 2.4 : 1.5
    });
  }
  // marker triangle at the fill tip, pointing outward into the band
  const baseR = R - BAND / 2 - 6;
  const half = 16 / baseR * (180 / Math.PI);
  const [mx, my] = polar(baseR + 13, endDeg);
  const [m1x, m1y] = polar(baseR, endDeg - half);
  const [m2x, m2y] = polar(baseR, endDeg + half);
  const band = ScoreRing.band(value);
  const uid = 'sg' + Math.round(value);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      width: W,
      height: H
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: W,
    height: H,
    viewBox: `0 0 ${W} ${H}`,
    "aria-hidden": "true"
  }, /*#__PURE__*/React.createElement("defs", null, /*#__PURE__*/React.createElement("linearGradient", {
    id: uid + 'g',
    gradientUnits: "userSpaceOnUse",
    x1: CX - R,
    y1: CY,
    x2: CX + R,
    y2: CY
  }, /*#__PURE__*/React.createElement("stop", {
    offset: "0%",
    stopColor: "#16A34A"
  }), /*#__PURE__*/React.createElement("stop", {
    offset: "50%",
    stopColor: "#10B981"
  }), /*#__PURE__*/React.createElement("stop", {
    offset: "100%",
    stopColor: "#38BDF8"
  })), /*#__PURE__*/React.createElement("filter", {
    id: uid + 'f',
    x: "-30%",
    y: "-30%",
    width: "160%",
    height: "160%"
  }, /*#__PURE__*/React.createElement("feDropShadow", {
    dx: "0",
    dy: "3",
    stdDeviation: "5",
    floodColor: "#10B981",
    floodOpacity: "0.28"
  }))), /*#__PURE__*/React.createElement("path", {
    d: arc(R, START, START + SWEEP),
    fill: "none",
    strokeWidth: BAND,
    strokeLinecap: "round",
    stroke: "color-mix(in srgb, var(--text-primary) 7%, transparent)"
  }), /*#__PURE__*/React.createElement("path", {
    d: arc(R, START, endDeg),
    fill: "none",
    strokeWidth: BAND,
    strokeLinecap: "round",
    stroke: `url(#${uid}g)`,
    filter: `url(#${uid}f)`,
    style: {
      transition: 'all var(--dur-slow) var(--ease-standard)'
    }
  }), /*#__PURE__*/React.createElement("g", {
    stroke: "color-mix(in srgb, var(--text-primary) 16%, transparent)",
    strokeLinecap: "round"
  }, ticks.map((t, i) => /*#__PURE__*/React.createElement("line", {
    key: i,
    x1: t.ax,
    y1: t.ay,
    x2: t.bx,
    y2: t.by,
    strokeWidth: t.w
  }))), /*#__PURE__*/React.createElement("path", {
    d: `M ${mx.toFixed(2)} ${my.toFixed(2)} L ${m1x.toFixed(2)} ${m1y.toFixed(2)} L ${m2x.toFixed(2)} ${m2y.toFixed(2)} Z`,
    fill: tip,
    style: {
      transition: 'all var(--dur-slow) var(--ease-standard)'
    }
  }), /*#__PURE__*/React.createElement("text", {
    x: CX,
    y: CY + 6,
    textAnchor: "middle",
    style: {
      fontFamily: 'var(--font-display)',
      fontSize: '52px',
      fontWeight: 700,
      letterSpacing: '-2px',
      fill: 'var(--text-primary)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, value), /*#__PURE__*/React.createElement("text", {
    x: CX,
    y: CY + 30,
    textAnchor: "middle",
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: '12px',
      fontWeight: 700,
      letterSpacing: '1.4px',
      fill: band.a
    }
  }, band.label.toUpperCase())));
}
ScoreRing.band = value => value >= 80 ? {
  a: 'var(--success)',
  glow: 'var(--success)',
  label: 'Khá an toàn'
} : value >= 50 ? {
  a: 'var(--warning)',
  glow: 'var(--warning)',
  label: 'Cần chú ý'
} : {
  a: 'var(--destructive)',
  glow: 'var(--destructive)',
  label: 'Rủi ro cao'
};

/* Overall password-strength meter — 1Password style. */
function StrengthBar({
  value = 72
}) {
  const spectrum = ['#22C55E', '#65D43A', '#A3E635', '#FACC15', '#FBBF24', '#F59E0B', '#F97316', '#EF4444'];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'stretch',
      gap: 5,
      height: 14
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: `${value}%`,
      minWidth: 14,
      background: 'var(--success)',
      borderRadius: 999,
      transition: 'width var(--dur-slow) var(--ease-standard)'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      display: 'flex',
      gap: 5
    }
  }, spectrum.map((c, i) => /*#__PURE__*/React.createElement("div", {
    key: i,
    style: {
      flex: 1,
      background: c,
      borderRadius: 4,
      opacity: 0.9
    }
  }))));
}
function StrengthCard({
  value = 72,
  onClick
}) {
  const [pressed, setPressed] = React.useState(false);
  return /*#__PURE__*/React.createElement(Card, {
    variant: "base",
    padding: "0",
    style: {
      overflow: 'hidden'
    }
  }, /*#__PURE__*/React.createElement("div", {
    role: "button",
    onClick: onClick,
    onPointerDown: () => setPressed(true),
    onPointerUp: () => setPressed(false),
    onPointerLeave: () => setPressed(false),
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 14,
      padding: '16px var(--space-4)',
      cursor: 'pointer',
      background: pressed ? 'var(--surface-pressed)' : 'transparent',
      transition: 'background var(--dur-fast)',
      WebkitTapHighlightColor: 'transparent'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      flex: 1,
      fontFamily: 'var(--font-text)',
      fontSize: 17,
      fontWeight: 600,
      color: 'var(--text-primary)'
    }
  }, "\u0110\u1ED9 m\u1EA1nh m\u1EADt kh\u1EA9u t\u1ED5ng th\u1EC3"), /*#__PURE__*/React.createElement(Icon, {
    name: "chevron.right",
    size: 16,
    color: "var(--icon-disabled)"
  })), /*#__PURE__*/React.createElement(StrengthBar, {
    value: value
  })));
}
function Watchtower() {
  const issues = [{
    id: 'comp',
    icon: 'warning',
    tint: 'var(--destructive)',
    title: 'Mật khẩu bị lộ',
    sub: '1 mục trong rò rỉ dữ liệu',
    count: 1,
    tone: 'destructive'
  }, {
    id: 'reuse',
    icon: 'copy',
    tint: 'var(--warning)',
    title: 'Dùng lại mật khẩu',
    sub: '3 mục dùng chung mật khẩu',
    count: 3,
    tone: 'warning'
  }, {
    id: 'weak',
    icon: 'lock',
    tint: 'var(--warning)',
    title: 'Mật khẩu yếu',
    sub: '2 mục dễ đoán',
    count: 2,
    tone: 'warning'
  }, {
    id: '2fa',
    icon: 'success',
    tint: 'var(--accent)',
    title: 'Bật xác thực 2 lớp',
    sub: '4 mục hỗ trợ 2FA',
    count: 4,
    tone: 'accent'
  }];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minHeight: 0,
      overflowY: 'auto',
      background: 'var(--background-grouped)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '4px var(--screen-gutter) 0'
    }
  }, /*#__PURE__*/React.createElement("h1", {
    style: {
      margin: '0 0 16px',
      fontFamily: 'var(--font-display)',
      fontSize: 28,
      fontWeight: 700,
      letterSpacing: '-0.4px',
      color: 'var(--text-primary)'
    }
  }, "Gi\xE1m s\xE1t")), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      padding: '4px 0 8px'
    }
  }, /*#__PURE__*/React.createElement(ScoreRing, {
    value: 82
  }), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: '6px 28px 0',
      textAlign: 'center',
      fontFamily: 'var(--font-text)',
      fontSize: 15,
      color: 'var(--text-secondary)',
      textWrap: 'pretty'
    }
  }, "Kh\u1EAFc ph\u1EE5c 6 v\u1EA5n \u0111\u1EC1 b\xEAn d\u01B0\u1EDBi \u0111\u1EC3 n\xE2ng \u0111i\u1EC3m b\u1EA3o m\u1EADt c\u1EE7a kho.")), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '18px var(--screen-gutter) var(--tabbar-bottom-pad)',
      display: 'flex',
      flexDirection: 'column',
      gap: 22
    }
  }, /*#__PURE__*/React.createElement(StrengthCard, {
    value: 72,
    onClick: () => {}
  }), /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "C\u1EA7n x\u1EED l\xFD"
  }), /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, issues.map((it, i) => /*#__PURE__*/React.createElement(Row, {
    key: it.id,
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: it.icon,
      tint: it.tint,
      soft: true
    }),
    title: it.title,
    subtitle: it.sub,
    trailing: /*#__PURE__*/React.createElement("span", {
      style: {
        display: 'inline-flex',
        alignItems: 'center',
        gap: 8
      }
    }, /*#__PURE__*/React.createElement(Badge, {
      count: it.count,
      tone: it.tone === 'accent' ? 'success' : it.tone
    })),
    chevron: true,
    divider: i < issues.length - 1,
    onClick: () => {}
  }))))));
}
window.Watchtower = Watchtower;
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/ios-app/Watchtower.jsx", error: String((e && e.message) || e) }); }

// ui_kits/ios-app/app.jsx
try { (() => {
/* App — Vaultify iPhone recreation.
   Multi-space vault · quick TOTP · password-rotation reminders ·
   live theme/accent. State lives on the IPhone wrapper so every
   surface re-tints instantly (no restart, no light/dark desync). */

/* ---- Spaces (personal / company / shared) ---- */
const SPACES = [{
  id: 'personal',
  name: 'Cá nhân',
  tint: '#2563eb',
  icon: 'profile'
}, {
  id: 'acme',
  name: 'Acme Corp',
  tint: '#7c3aed',
  icon: 'bank'
}, {
  id: 'family',
  name: 'Gia đình',
  tint: '#0e8a7d',
  icon: 'favorite'
}];
const spaceById = id => SPACES.find(s => s.id === id);

/* ---- Items. totp = a 2FA secret seed · rotateDays = đổi mật khẩu định kỳ
   · changed = số ngày kể từ lần đổi gần nhất ---- */
const ITEMS = [{
  id: 'vcb',
  name: 'Vietcombank',
  icon: 'bank',
  tint: '#0a8f3c',
  space: 'personal',
  username: '0901234567',
  url: 'vietcombank.com.vn',
  password: 'Vcb#2026xKq',
  score: 4,
  rotateDays: 30,
  changed: 33,
  totp: 'VCB2FAKEY'
}, {
  id: 'acb',
  name: 'ACB Online',
  icon: 'bank',
  tint: '#0052a5',
  space: 'personal',
  username: 'cat@gmail.com',
  url: 'acb.com.vn',
  password: 'Acb!9wQ2mLz',
  score: 4,
  rotateDays: 15,
  changed: 12
}, {
  id: 'github',
  name: 'GitHub',
  icon: 'login',
  tint: '#1c1c1e',
  space: 'acme',
  username: 'octocat@acme.com',
  url: 'github.com',
  password: 'k7$Rm2!qZ4xL',
  score: 4,
  changed: 20,
  totp: 'GH7KQ2',
  fav: true
}, {
  id: 'google',
  name: 'Google',
  icon: 'login',
  tint: '#4285f4',
  space: 'personal',
  username: 'cat@gmail.com',
  url: 'accounts.google.com',
  password: 'P9!vQ2s@Lm7z',
  score: 4,
  changed: 90,
  totp: 'GOOGLE9',
  fav: true
}, {
  id: 'figma',
  name: 'Figma',
  icon: 'login',
  tint: '#a259ff',
  space: 'acme',
  username: 'cat@acme.com',
  url: 'figma.com',
  password: 'fG3#tyU8wQ',
  score: 3,
  changed: 210
}, {
  id: 'aws',
  name: 'AWS Console',
  icon: 'website',
  tint: '#ff9900',
  space: 'acme',
  username: 'ops@acme.com',
  url: 'aws.amazon.com',
  password: 'Aws#2025kPq',
  score: 4,
  rotateDays: 90,
  changed: 96,
  totp: 'AWSKEY1'
}, {
  id: 'apple',
  name: 'Apple ID',
  icon: 'identity',
  tint: '#1c1c1e',
  space: 'personal',
  username: 'cat@icloud.com',
  url: 'appleid.apple.com',
  password: 'Zx9#Kq2!Pm4v',
  score: 4,
  changed: 60
}, {
  id: 'visa',
  name: 'Visa',
  icon: 'card',
  tint: '#1a1f71',
  space: 'personal',
  username: '•••• 4242',
  url: '',
  password: '4242 4242 4242 4242',
  score: 4,
  changed: 30
}, {
  id: 'netflix',
  name: 'Netflix',
  icon: 'login',
  tint: '#e50914',
  space: 'family',
  username: 'cat@gmail.com',
  url: 'netflix.com',
  password: 'netflix123',
  score: 1,
  changed: 400,
  alert: true
}, {
  id: 'fastmail',
  name: 'Fastmail',
  icon: 'email',
  tint: '#0e8a7d',
  space: 'acme',
  username: 'cat@fastmail.com',
  url: 'fastmail.com',
  password: 'mB7$wK2zQ9',
  score: 3,
  changed: 10,
  totp: 'FMAIL3'
}, {
  id: 'notion',
  name: 'Notion',
  icon: 'note',
  tint: '#1c1c1e',
  space: 'acme',
  username: 'cat@acme.com',
  url: 'notion.so',
  password: 'nT8#vRq2Lp',
  score: 3,
  changed: 35
}];

/* ---- Rotation / staleness status ---- */
function rotationStatus(it) {
  if (it.rotateDays > 0) {
    const due = it.rotateDays - it.changed;
    if (due <= 0) return {
      state: 'overdue',
      tone: 'destructive',
      icon: 'refresh',
      label: `Quá hạn đổi ${-due} ngày`,
      short: 'Quá hạn'
    };
    if (due <= 5) return {
      state: 'soon',
      tone: 'warning',
      icon: 'clock',
      label: `Đổi sau ${due} ngày`,
      short: `${due} ngày`
    };
    return {
      state: 'ok',
      tone: 'neutral',
      label: `Đổi sau ${due} ngày`
    };
  }
  if (it.changed >= 180) return {
    state: 'stale',
    tone: 'warning',
    icon: 'clock',
    label: `${Math.round(it.changed / 30)} tháng chưa đổi`,
    short: 'Đã lâu'
  };
  return {
    state: 'ok'
  };
}
function attentionReason(it) {
  const r = rotationStatus(it);
  if (r.state !== 'ok') return r;
  if (it.score <= 1) return {
    state: 'weak',
    tone: 'destructive',
    icon: 'warning',
    label: 'Mật khẩu yếu · dùng lại',
    short: 'Yếu'
  };
  return null;
}

/* ============================================================ Cells */
function ItemCell({
  item,
  onOpen,
  showSpace,
  divider
}) {
  const [pressed, setPressed] = React.useState(false);
  const sp = spaceById(item.space);
  const att = attentionReason(item);
  return /*#__PURE__*/React.createElement("div", {
    role: "button",
    onClick: () => onOpen(item),
    onPointerDown: () => setPressed(true),
    onPointerUp: () => setPressed(false),
    onPointerLeave: () => setPressed(false),
    style: {
      position: 'relative',
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-3)',
      minHeight: 62,
      padding: '10px var(--space-4)',
      background: pressed ? 'var(--surface-pressed)' : 'transparent',
      cursor: 'pointer',
      transition: 'background var(--dur-fast)',
      WebkitTapHighlightColor: 'transparent'
    }
  }, /*#__PURE__*/React.createElement(IconTile, {
    name: item.icon,
    tint: item.tint,
    size: 38,
    radius: "var(--radius-sm)"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0,
      display: 'flex',
      flexDirection: 'column',
      gap: 3
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 17,
      fontWeight: 600,
      color: 'var(--text-primary)',
      lineHeight: '20px',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, item.name), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 7,
      minWidth: 0
    }
  }, showSpace && /*#__PURE__*/React.createElement(SpaceTag, {
    space: sp
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 13,
      color: 'var(--text-secondary)',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, item.username))), item.totp && /*#__PURE__*/React.createElement(Icon, {
    name: "clock",
    size: 16,
    color: "var(--icon-disabled)"
  }), att && /*#__PURE__*/React.createElement("span", {
    style: {
      width: 8,
      height: 8,
      borderRadius: '50%',
      flex: '0 0 auto',
      background: att.tone === 'destructive' ? 'var(--destructive)' : 'var(--warning)'
    }
  }), /*#__PURE__*/React.createElement(Icon, {
    name: "chevron.right",
    size: 16,
    color: "var(--icon-disabled)"
  }), divider && /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      left: 'calc(var(--space-4) + 38px + var(--space-3))',
      right: 0,
      bottom: 0,
      height: 0.5,
      background: 'var(--separator)'
    }
  }));
}
function AttentionCell({
  item,
  onUpdate,
  divider
}) {
  const att = attentionReason(item);
  const sp = spaceById(item.space);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-3)',
      minHeight: 64,
      padding: '10px var(--space-4)'
    }
  }, /*#__PURE__*/React.createElement(IconTile, {
    name: item.icon,
    tint: item.tint,
    size: 38,
    radius: "var(--radius-sm)"
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0,
      display: 'flex',
      flexDirection: 'column',
      gap: 3
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 16,
      fontWeight: 600,
      color: 'var(--text-primary)',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, item.name), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 6
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: att.icon,
    size: 13,
    color: att.tone === 'destructive' ? 'var(--destructive)' : 'var(--warning)'
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 13,
      fontWeight: 500,
      color: att.tone === 'destructive' ? 'var(--destructive)' : 'var(--warning)'
    }
  }, att.label))), /*#__PURE__*/React.createElement(Button, {
    size: "sm",
    variant: att.tone === 'destructive' ? 'primary' : 'secondary',
    onClick: () => onUpdate(item)
  }, "\u0110\u1ED5i"), divider && /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      left: 'calc(var(--space-4) + 38px + var(--space-3))',
      right: 0,
      bottom: 0,
      height: 0.5,
      background: 'var(--separator)'
    }
  }));
}

/* ============================================================ Home */
function Home({
  space,
  onOpenSpace,
  onOpenItem,
  onAdd,
  onGenerate,
  onTotpAll,
  onSettings
}) {
  const inSpace = it => space === 'all' || it.space === space;
  const items = ITEMS.filter(inSpace);
  const totps = items.filter(i => i.totp);
  const attention = items.filter(attentionReason).sort((a, b) => {
    const t = {
      overdue: 0,
      weak: 1,
      soon: 2,
      stale: 3
    };
    return (t[attentionReason(a).state] ?? 9) - (t[attentionReason(b).state] ?? 9);
  });
  const favs = items.filter(i => i.fav);
  const cur = space === 'all' ? {
    name: 'Tất cả space',
    tint: 'var(--icon-secondary)'
  } : spaceById(space);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minHeight: 0,
      overflowY: 'auto',
      background: 'var(--background-grouped)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '2px var(--screen-gutter) 0'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      minHeight: 44
    }
  }, /*#__PURE__*/React.createElement("button", {
    onClick: onOpenSpace,
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      border: 'none',
      background: 'none',
      cursor: 'pointer',
      padding: '4px 0',
      WebkitTapHighlightColor: 'transparent'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 10,
      height: 10,
      borderRadius: '50%',
      background: cur.tint
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-display)',
      fontSize: 24,
      fontWeight: 700,
      letterSpacing: '-0.4px',
      color: 'var(--text-primary)'
    }
  }, cur.name), /*#__PURE__*/React.createElement(Icon, {
    name: "chevron.down",
    size: 17,
    color: "var(--icon-secondary)"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 2
    }
  }, /*#__PURE__*/React.createElement(IconButton, {
    name: "add",
    label: "Th\xEAm m\u1EE5c",
    color: "var(--accent)",
    onClick: onAdd
  }), /*#__PURE__*/React.createElement(IconButton, {
    name: "settings",
    label: "C\xE0i \u0111\u1EB7t",
    color: "var(--accent)",
    onClick: onSettings
  }))), /*#__PURE__*/React.createElement("button", {
    onClick: () => {},
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      width: '100%',
      margin: '8px 0 16px',
      minHeight: 40,
      padding: '0 12px',
      border: 'none',
      borderRadius: 'var(--radius-sm)',
      background: 'color-mix(in srgb, var(--text-primary) 7%, transparent)',
      cursor: 'pointer'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "search",
    size: 18,
    color: "var(--icon-secondary)"
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 16,
      color: 'var(--text-tertiary)'
    }
  }, "T\xECm trong kho"))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 var(--screen-gutter)',
      display: 'flex',
      flexDirection: 'column',
      gap: 24,
      paddingBottom: 'var(--tabbar-bottom-pad)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 6
    }
  }, /*#__PURE__*/React.createElement(QuickAction, {
    icon: "add",
    label: "Th\xEAm m\u1EE5c",
    tint: "var(--accent)",
    onClick: onAdd
  }), /*#__PURE__*/React.createElement(QuickAction, {
    icon: "refresh",
    label: "T\u1EA1o m\u1EADt kh\u1EA9u",
    tint: "#0e8a7d",
    onClick: onGenerate
  }), /*#__PURE__*/React.createElement(QuickAction, {
    icon: "clock",
    label: "M\xE3 2FA",
    tint: "#7c3aed",
    onClick: onTotpAll
  }), /*#__PURE__*/React.createElement(QuickAction, {
    icon: "watchtower",
    label: "Gi\xE1m s\xE1t",
    tint: "#0a8f3c",
    onClick: () => {}
  })), totps.length > 0 && /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "M\xE3 x\xE1c th\u1EF1c",
    action: "Xem t\u1EA5t c\u1EA3",
    onAction: onTotpAll
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 10,
      overflowX: 'auto',
      padding: '2px 2px 4px',
      margin: '0 -2px',
      scrollbarWidth: 'none'
    }
  }, totps.map(it => /*#__PURE__*/React.createElement(TotpCard, {
    key: it.id,
    item: it
  })))), attention.length > 0 && /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: `Cần chú ý · ${attention.length}`
  }), /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, attention.slice(0, 4).map((it, i) => /*#__PURE__*/React.createElement(AttentionCell, {
    key: it.id,
    item: it,
    onUpdate: onOpenItem,
    divider: i < Math.min(4, attention.length) - 1
  })))), favs.length > 0 && /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Y\xEAu th\xEDch"
  }), /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, favs.map((it, i) => /*#__PURE__*/React.createElement(ItemCell, {
    key: it.id,
    item: it,
    onOpen: onOpenItem,
    showSpace: space === 'all',
    divider: i < favs.length - 1
  })))), /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: `Tất cả · ${items.length}`,
    action: "S\u1EAFp x\u1EBFp"
  }), /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, items.map((it, i) => /*#__PURE__*/React.createElement(ItemCell, {
    key: it.id,
    item: it,
    onOpen: onOpenItem,
    showSpace: space === 'all',
    divider: i < items.length - 1
  }))))));
}

/* ============================================================ Space switcher */
function SpaceSwitcher({
  space,
  setSpace,
  onClose
}) {
  const pick = id => {
    setSpace(id);
    onClose();
  };
  const countOf = id => id === 'all' ? ITEMS.length : ITEMS.filter(i => i.space === id).length;
  return /*#__PURE__*/React.createElement(Sheet, {
    title: "Spaces",
    onClose: onClose
  }, /*#__PURE__*/React.createElement(Card, {
    variant: "grouped",
    style: {
      marginBottom: 18
    }
  }, /*#__PURE__*/React.createElement(Row, {
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: "items",
      tint: "var(--icon-secondary)",
      soft: true
    }),
    title: "T\u1EA5t c\u1EA3 space",
    value: String(countOf('all')),
    trailing: space === 'all' ? /*#__PURE__*/React.createElement(Icon, {
      name: "success",
      size: 20,
      color: "var(--accent)"
    }) : null,
    divider: true,
    onClick: () => pick('all')
  }), SPACES.map((s, i) => /*#__PURE__*/React.createElement(Row, {
    key: s.id,
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: s.icon,
      tint: s.tint
    }),
    title: s.name,
    value: String(countOf(s.id)),
    trailing: space === s.id ? /*#__PURE__*/React.createElement(Icon, {
      name: "success",
      size: 20,
      color: "var(--accent)"
    }) : null,
    divider: i < SPACES.length - 1,
    onClick: () => pick(s.id)
  }))), /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, /*#__PURE__*/React.createElement(Row, {
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: "add",
      tint: "var(--accent)",
      soft: true
    }),
    title: "T\u1EA1o space m\u1EDBi",
    tone: "accent",
    divider: true,
    onClick: onClose
  }), /*#__PURE__*/React.createElement(Row, {
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: "settings",
      tint: "var(--icon-secondary)",
      soft: true
    }),
    title: "Qu\u1EA3n l\xFD spaces & th\xE0nh vi\xEAn",
    chevron: true,
    divider: false,
    onClick: onClose
  })));
}

/* ============================================================ Create item (shows rotation + TOTP options) */
function CreateItem({
  space,
  onClose
}) {
  const [rotate, setRotate] = React.useState('off');
  const [totp, setTotp] = React.useState(false);
  const [sp, setSp] = React.useState(space === 'all' ? 'personal' : space);
  const [pw, setPw] = React.useState('Vcb#2026xKq');
  return /*#__PURE__*/React.createElement(Sheet, {
    title: "M\u1EE5c m\u1EDBi",
    onClose: onClose
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 22,
      paddingTop: 4
    }
  }, /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, /*#__PURE__*/React.createElement(Row, {
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: "login",
      tint: "var(--accent)"
    }),
    title: "Lo\u1EA1i",
    value: "\u0110\u0103ng nh\u1EADp",
    chevron: true,
    onClick: () => {}
  }), /*#__PURE__*/React.createElement(Row, {
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: spaceById(sp).icon,
      tint: spaceById(sp).tint
    }),
    title: "Space",
    value: spaceById(sp).name,
    chevron: true,
    divider: false,
    onClick: () => {
      const i = SPACES.findIndex(s => s.id === sp);
      setSp(SPACES[(i + 1) % SPACES.length].id);
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 14
    }
  }, /*#__PURE__*/React.createElement(Field, {
    label: "T\xEAn",
    leadingIcon: "login",
    defaultValue: "Vietcombank"
  }), /*#__PURE__*/React.createElement(Field, {
    label: "Email / T\xEAn \u0111\u0103ng nh\u1EADp",
    leadingIcon: "email",
    defaultValue: "0901234567"
  }), /*#__PURE__*/React.createElement(Field, {
    label: "M\u1EADt kh\u1EA9u",
    leadingIcon: "lock",
    mono: true,
    secure: true,
    revealable: true,
    value: pw,
    onChange: e => setPw(e.target.value),
    trailing: /*#__PURE__*/React.createElement(IconButton, {
      name: "refresh",
      label: "T\u1EA1o m\u1EADt kh\u1EA9u",
      size: "sm",
      color: "var(--accent)",
      onClick: () => setPw('K' + Math.random().toString(36).slice(2, 11) + '#9')
    })
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 2px'
    }
  }, /*#__PURE__*/React.createElement(StrengthMeter, {
    score: 4
  }))), /*#__PURE__*/React.createElement("section", null, /*#__PURE__*/React.createElement(SectionHeader, {
    title: "Nh\u1EAFc \u0111\u1ED5i m\u1EADt kh\u1EA9u"
  }), /*#__PURE__*/React.createElement(SegmentedControl, {
    value: rotate,
    onChange: setRotate,
    options: [{
      value: 'off',
      label: 'Tắt'
    }, {
      value: '15',
      label: '15 ngày'
    }, {
      value: '30',
      label: '30 ngày'
    }, {
      value: '90',
      label: '90 ngày'
    }]
  }), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: '8px 4px 0',
      fontFamily: 'var(--font-text)',
      fontSize: 13,
      color: 'var(--text-tertiary)',
      textWrap: 'pretty'
    }
  }, rotate === 'off' ? 'Vaultify sẽ không nhắc đổi mật khẩu cho mục này.' : `Vaultify sẽ nhắc bạn đổi mật khẩu mỗi ${rotate} ngày — phù hợp cho ngân hàng yêu cầu đổi định kỳ.`)), /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, /*#__PURE__*/React.createElement(Row, {
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: "clock",
      tint: "#7c3aed",
      soft: true
    }),
    title: "Th\xEAm m\xE3 x\xE1c th\u1EF1c (2FA)",
    subtitle: totp ? 'Quét QR hoặc dán khoá' : undefined,
    trailing: /*#__PURE__*/React.createElement(Switch, {
      checked: totp,
      onChange: setTotp,
      label: "2FA"
    }),
    divider: false
  })), /*#__PURE__*/React.createElement(Button, {
    fullWidth: true,
    size: "lg",
    onClick: onClose
  }, "L\u01B0u v\xE0o kho")));
}

/* ============================================================ Password generator */
function genPw(len = 18) {
  const a = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*';
  let s = '';
  for (let i = 0; i < len; i++) s += a[Math.floor(Math.random() * a.length)];
  return s;
}
function Generator({
  onClose
}) {
  const [pw, setPw] = React.useState(() => genPw());
  const [copied, setCopied] = React.useState(false);
  function copy() {
    setCopied(true);
    setTimeout(() => setCopied(false), 1200);
  }
  return /*#__PURE__*/React.createElement(Sheet, {
    title: "T\u1EA1o m\u1EADt kh\u1EA9u",
    onClose: onClose
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 18,
      paddingTop: 4
    }
  }, /*#__PURE__*/React.createElement(Card, {
    padding: "18px"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-mono)',
      fontSize: 22,
      fontWeight: 600,
      color: 'var(--text-primary)',
      wordBreak: 'break-all',
      lineHeight: '30px',
      letterSpacing: '0.02em'
    }
  }, pw), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 14
    }
  }, /*#__PURE__*/React.createElement(StrengthMeter, {
    score: 4
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 10
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    fullWidth: true,
    leadingIcon: "refresh",
    onClick: () => setPw(genPw())
  }, "T\u1EA1o l\u1EA1i"), /*#__PURE__*/React.createElement(Button, {
    fullWidth: true,
    leadingIcon: copied ? 'success' : 'copy',
    onClick: copy
  }, copied ? 'Đã sao chép' : 'Sao chép')), /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, /*#__PURE__*/React.createElement(Row, {
    title: "\u0110\u1ED9 d\xE0i",
    value: "18 k\xFD t\u1EF1",
    chevron: true,
    onClick: () => {}
  }), /*#__PURE__*/React.createElement(Row, {
    title: "K\xFD t\u1EF1 \u0111\u1EB7c bi\u1EC7t",
    trailing: /*#__PURE__*/React.createElement(Switch, {
      checked: true,
      onChange: () => {},
      label: "K\xFD t\u1EF1 \u0111\u1EB7c bi\u1EC7t"
    }),
    divider: false
  }))));
}

/* ============================================================ Full TOTP list */
function TotpList({
  space,
  onClose
}) {
  const [q, setQ] = React.useState('');
  const all = ITEMS.filter(i => i.totp && (space === 'all' || i.space === space));
  const norm = s => (s || '').toLowerCase();
  const ql = norm(q.trim());
  const items = ql ? all.filter(it => norm(it.name).includes(ql) || norm(it.username).includes(ql) || norm(spaceById(it.space)?.name).includes(ql)) : all;
  return /*#__PURE__*/React.createElement(Sheet, {
    title: "M\xE3 x\xE1c th\u1EF1c",
    onClose: onClose
  }, /*#__PURE__*/React.createElement("label", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      minHeight: 40,
      padding: '0 12px',
      marginBottom: 14,
      borderRadius: 'var(--radius-sm)',
      background: 'color-mix(in srgb, var(--text-primary) 7%, transparent)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "search",
    size: 18,
    color: "var(--icon-secondary)"
  }), /*#__PURE__*/React.createElement("input", {
    value: q,
    onChange: e => setQ(e.target.value),
    placeholder: "T\xECm t\xEAn, email, space\u2026",
    style: {
      flex: 1,
      border: 'none',
      outline: 'none',
      background: 'transparent',
      fontFamily: 'var(--font-text)',
      fontSize: 16,
      color: 'var(--text-primary)',
      minWidth: 0
    }
  }), q && /*#__PURE__*/React.createElement("button", {
    onClick: () => setQ(''),
    "aria-label": "Xo\xE1 t\xECm ki\u1EBFm",
    style: {
      display: 'inline-flex',
      border: 'none',
      background: 'none',
      padding: 4,
      cursor: 'pointer'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "add",
    size: 16,
    color: "var(--icon-secondary)",
    style: {
      transform: 'rotate(45deg)'
    }
  }))), items.length > 0 ? /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, items.map((it, i) => /*#__PURE__*/React.createElement(TotpRow, {
    key: it.id,
    item: it,
    divider: i < items.length - 1
  }))) : /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '40px 16px',
      textAlign: 'center',
      fontFamily: 'var(--font-text)',
      fontSize: 15,
      color: 'var(--text-tertiary)'
    }
  }, "Kh\xF4ng c\xF3 m\xE3 n\xE0o kh\u1EDBp \u201C", q, "\u201D."));
}
function TotpRow({
  item,
  divider
}) {
  const {
    code,
    remaining,
    progress
  } = useTotp(item.totp);
  const [copied, setCopied] = React.useState(false);
  const sp = spaceById(item.space);
  return /*#__PURE__*/React.createElement("div", {
    onClick: () => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1100);
    },
    role: "button",
    style: {
      position: 'relative',
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-3)',
      minHeight: 64,
      padding: '10px var(--space-4)',
      cursor: 'pointer'
    }
  }, /*#__PURE__*/React.createElement(IconTile, {
    name: item.icon,
    tint: item.tint,
    size: 38
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 15,
      color: 'var(--text-secondary)',
      display: 'flex',
      gap: 7,
      alignItems: 'center',
      marginBottom: 2
    }
  }, /*#__PURE__*/React.createElement(SpaceTag, {
    space: sp
  }), " ", /*#__PURE__*/React.createElement("span", {
    style: {
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, item.name)), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-mono)',
      fontSize: 26,
      fontWeight: 600,
      letterSpacing: '0.08em',
      color: copied ? 'var(--success)' : 'var(--accent)',
      fontVariantNumeric: 'tabular-nums'
    }
  }, copied ? 'Đã sao chép' : fmtCode(code))), /*#__PURE__*/React.createElement(TotpRing, {
    progress: progress,
    remaining: remaining,
    size: 32
  }), divider && /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      left: 'calc(var(--space-4) + 38px + var(--space-3))',
      right: 0,
      bottom: 0,
      height: 0.5,
      background: 'var(--separator)'
    }
  }));
}

/* ============================================================ Categories & Search */
function Categories({
  space,
  onOpen
}) {
  const items = ITEMS.filter(i => space === 'all' || i.space === space);
  const cats = [{
    id: 'logins',
    icon: 'login',
    tint: 'var(--accent)',
    label: 'Tên đăng nhập',
    n: items.filter(i => i.icon === 'login').length
  }, {
    id: 'bank',
    icon: 'bank',
    tint: '#0a8f3c',
    label: 'Ngân hàng & tài chính',
    n: items.filter(i => i.icon === 'bank').length
  }, {
    id: 'cards',
    icon: 'card',
    tint: '#1a1f71',
    label: 'Thẻ',
    n: items.filter(i => i.icon === 'card').length
  }, {
    id: 'identity',
    icon: 'identity',
    tint: '#7c3aed',
    label: 'Danh tính',
    n: items.filter(i => i.icon === 'identity').length
  }, {
    id: 'note',
    icon: 'note',
    tint: 'var(--warning)',
    label: 'Ghi chú bảo mật',
    n: items.filter(i => i.icon === 'note').length
  }];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minHeight: 0,
      overflowY: 'auto',
      background: 'var(--background-grouped)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '4px var(--screen-gutter) 16px'
    }
  }, /*#__PURE__*/React.createElement("h1", {
    style: {
      margin: 0,
      fontFamily: 'var(--font-display)',
      fontSize: 28,
      fontWeight: 700,
      letterSpacing: '-0.4px',
      color: 'var(--text-primary)'
    }
  }, "M\u1EE5c")), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 var(--screen-gutter) var(--tabbar-bottom-pad)'
    }
  }, /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, cats.map((c, i) => /*#__PURE__*/React.createElement(Row, {
    key: c.id,
    leading: /*#__PURE__*/React.createElement(IconTile, {
      name: c.icon,
      tint: c.tint
    }),
    title: c.label,
    value: String(c.n),
    chevron: true,
    divider: i < cats.length - 1,
    onClick: () => {}
  })))));
}
function Search({
  onOpen
}) {
  const [q, setQ] = React.useState('');
  const [sp, setSp] = React.useState('all');
  let res = ITEMS.filter(i => sp === 'all' || i.space === sp);
  if (q) res = res.filter(i => (i.name + ' ' + i.username).toLowerCase().includes(q.toLowerCase()));
  return /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minHeight: 0,
      overflowY: 'auto',
      background: 'var(--background-grouped)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '4px var(--screen-gutter) 0'
    }
  }, /*#__PURE__*/React.createElement("h1", {
    style: {
      margin: '0 0 12px',
      fontFamily: 'var(--font-display)',
      fontSize: 28,
      fontWeight: 700,
      letterSpacing: '-0.4px',
      color: 'var(--text-primary)'
    }
  }, "T\xECm ki\u1EBFm"), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8,
      minHeight: 40,
      padding: '0 12px',
      borderRadius: 'var(--radius-sm)',
      background: 'color-mix(in srgb, var(--text-primary) 7%, transparent)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "search",
    size: 18,
    color: "var(--icon-secondary)"
  }), /*#__PURE__*/React.createElement("input", {
    value: q,
    onChange: e => setQ(e.target.value),
    placeholder: "T\xEAn, email, space\u2026",
    autoFocus: true,
    style: {
      flex: 1,
      border: 'none',
      outline: 'none',
      background: 'transparent',
      fontFamily: 'var(--font-text)',
      fontSize: 16,
      color: 'var(--text-primary)'
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 8,
      overflowX: 'auto',
      padding: '12px 0 16px',
      scrollbarWidth: 'none'
    }
  }, [{
    id: 'all',
    name: 'Tất cả',
    tint: 'var(--icon-secondary)'
  }, ...SPACES].map(s => {
    const on = sp === s.id;
    return /*#__PURE__*/React.createElement("button", {
      key: s.id,
      onClick: () => setSp(s.id),
      style: {
        flex: '0 0 auto',
        display: 'inline-flex',
        alignItems: 'center',
        gap: 6,
        padding: '7px 13px',
        borderRadius: 'var(--radius-pill)',
        border: 'none',
        cursor: 'pointer',
        background: on ? 'var(--accent)' : 'color-mix(in srgb, var(--text-primary) 7%, transparent)',
        WebkitTapHighlightColor: 'transparent'
      }
    }, s.id !== 'all' && /*#__PURE__*/React.createElement("span", {
      style: {
        width: 7,
        height: 7,
        borderRadius: '50%',
        background: on ? 'var(--on-accent)' : s.tint
      }
    }), /*#__PURE__*/React.createElement("span", {
      style: {
        fontFamily: 'var(--font-text)',
        fontSize: 14,
        fontWeight: 600,
        color: on ? 'var(--on-accent)' : 'var(--text-secondary)'
      }
    }, s.name));
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 var(--screen-gutter) var(--tabbar-bottom-pad)'
    }
  }, /*#__PURE__*/React.createElement(Card, {
    variant: "grouped"
  }, res.map((it, i) => /*#__PURE__*/React.createElement(ItemCell, {
    key: it.id,
    item: it,
    onOpen: onOpen,
    showSpace: true,
    divider: i < res.length - 1
  })), res.length === 0 && /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '28px',
      textAlign: 'center',
      fontFamily: 'var(--font-text)',
      fontSize: 15,
      color: 'var(--text-tertiary)'
    }
  }, "Kh\xF4ng c\xF3 k\u1EBFt qu\u1EA3"))));
}

/* ============================================================ App shell */
const TABS = [{
  id: 'home',
  icon: 'home',
  iconFill: 'home.fill',
  label: 'Trang chủ'
}, {
  id: 'items',
  icon: 'items',
  iconFill: 'items.fill',
  label: 'Mục'
}, {
  id: 'watchtower',
  icon: 'watchtower',
  label: 'Giám sát',
  badge: 5
}, {
  id: 'search',
  icon: 'search',
  label: 'Tìm kiếm'
}];
function App() {
  const [locked, setLocked] = React.useState(true);
  const [tab, setTab] = React.useState('home');
  const [space, setSpace] = React.useState('all');
  const [detail, setDetail] = React.useState(null);
  const [sheet, setSheet] = React.useState(null); // 'space' | 'create' | 'gen' | 'totp' | 'settings'
  const [theme, setTheme] = React.useState('light');
  const [accent, setAccent] = React.useState('blue');
  const overlay = !!detail || sheet === 'settings';
  function screen() {
    if (tab === 'home') return /*#__PURE__*/React.createElement(Home, {
      space: space,
      onOpenSpace: () => setSheet('space'),
      onOpenItem: setDetail,
      onAdd: () => setSheet('create'),
      onGenerate: () => setSheet('gen'),
      onTotpAll: () => setSheet('totp'),
      onSettings: () => setSheet('settings')
    });
    if (tab === 'items') return /*#__PURE__*/React.createElement(Categories, {
      space: space,
      onOpen: setDetail
    });
    if (tab === 'watchtower') return /*#__PURE__*/React.createElement(Watchtower, null);
    if (tab === 'search') return /*#__PURE__*/React.createElement(Search, {
      onOpen: setDetail
    });
    return null;
  }
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 40,
      alignItems: 'flex-start',
      flexWrap: 'wrap',
      justifyContent: 'center'
    }
  }, /*#__PURE__*/React.createElement(IPhone, {
    theme: theme,
    accent: accent
  }, /*#__PURE__*/React.createElement(StatusBar, null), locked ? /*#__PURE__*/React.createElement(UnlockScreen, {
    onUnlock: () => setLocked(false)
  }) : /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      flex: 1,
      minHeight: 0,
      display: 'flex',
      flexDirection: 'column'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minHeight: 0,
      display: 'flex',
      flexDirection: 'column'
    }
  }, screen()), !overlay && /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      left: 'var(--tabbar-inset)',
      right: 'var(--tabbar-inset)',
      bottom: 'calc(var(--tabbar-offset) + 8px)'
    }
  }, /*#__PURE__*/React.createElement(TabBar, {
    tabs: TABS,
    value: tab,
    onChange: setTab,
    glass: true
  })), sheet === 'space' && /*#__PURE__*/React.createElement(SpaceSwitcher, {
    space: space,
    setSpace: setSpace,
    onClose: () => setSheet(null)
  }), sheet === 'create' && /*#__PURE__*/React.createElement(CreateItem, {
    space: space,
    onClose: () => setSheet(null)
  }), sheet === 'gen' && /*#__PURE__*/React.createElement(Generator, {
    onClose: () => setSheet(null)
  }), sheet === 'totp' && /*#__PURE__*/React.createElement(TotpList, {
    space: space,
    onClose: () => setSheet(null)
  }), detail && /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      background: 'var(--background-grouped)',
      display: 'flex',
      flexDirection: 'column',
      animation: 'slideIn var(--dur-medium) var(--ease-standard)'
    }
  }, /*#__PURE__*/React.createElement(ItemDetail, {
    item: detail,
    onBack: () => setDetail(null)
  })), sheet === 'settings' && /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: 0,
      background: 'var(--background-grouped)',
      display: 'flex',
      flexDirection: 'column',
      animation: 'slideIn var(--dur-medium) var(--ease-standard)'
    }
  }, /*#__PURE__*/React.createElement(Appearance, {
    theme: theme,
    setTheme: setTheme,
    accent: accent,
    setAccent: setAccent,
    onClose: () => setSheet(null)
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      bottom: 8,
      left: '50%',
      transform: 'translateX(-50%)',
      width: 140,
      height: 5,
      borderRadius: 3,
      background: 'var(--text-primary)',
      opacity: 0.32,
      zIndex: 60
    }
  })), /*#__PURE__*/React.createElement(DemoControls, {
    locked: locked,
    theme: theme,
    setTheme: setTheme,
    accent: accent,
    setAccent: setAccent,
    onLock: () => setLocked(true)
  }));
}
function DemoControls({
  locked,
  theme,
  setTheme,
  accent,
  setAccent,
  onLock
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      width: 230,
      display: 'flex',
      flexDirection: 'column',
      gap: 18,
      paddingTop: 8
    }
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("p", {
    style: {
      margin: '0 0 8px',
      font: '600 12px var(--font-text)',
      letterSpacing: '0.4px',
      textTransform: 'uppercase',
      color: '#8a8a8e'
    }
  }, "Ch\u1EBF \u0111\u1ED9"), /*#__PURE__*/React.createElement(SegmentedControl, {
    value: theme,
    onChange: setTheme,
    options: [{
      value: 'light',
      label: 'Sáng'
    }, {
      value: 'dark',
      label: 'Tối'
    }]
  })), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("p", {
    style: {
      margin: '0 0 10px',
      font: '600 12px var(--font-text)',
      letterSpacing: '0.4px',
      textTransform: 'uppercase',
      color: '#8a8a8e'
    }
  }, "M\xE0u nh\u1EA5n"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 12,
      flexWrap: 'wrap'
    }
  }, window.ACCENTS.map(a => {
    const sel = a.id === accent,
      col = theme === 'dark' ? a.dark : a.light;
    return /*#__PURE__*/React.createElement("button", {
      key: a.id,
      onClick: () => setAccent(a.id),
      "aria-label": a.id,
      style: {
        width: 34,
        height: 34,
        borderRadius: '50%',
        border: 'none',
        cursor: 'pointer',
        background: col,
        position: 'relative',
        boxShadow: sel ? `0 0 0 2px #fff, 0 0 0 4px ${col}` : 'none'
      }
    }, sel && /*#__PURE__*/React.createElement(Icon, {
      name: "success",
      size: 16,
      color: "#fff",
      style: {
        position: 'absolute',
        inset: 0,
        margin: 'auto'
      }
    }));
  }))), !locked && /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    leadingIcon: "lock",
    onClick: onLock
  }, "Kho\xE1 kho"), /*#__PURE__*/React.createElement("p", {
    style: {
      margin: 0,
      font: '400 12px var(--font-text)',
      lineHeight: '17px',
      color: '#8a8a8e',
      textWrap: 'pretty'
    }
  }, "\u0110\u1ED5i ch\u1EBF \u0111\u1ED9 & m\xE0u nh\u1EA5n \u0111\u1EC3 th\u1EA5y to\xE0n b\u1ED9 giao di\u1EC7n \u0111\u1ED5i t\u1EE9c th\xEC \u2014 kh\xF4ng c\u1EA7n kh\u1EDFi \u0111\u1ED9ng l\u1EA1i, kh\xF4ng desync."));
}
ReactDOM.createRoot(document.getElementById('root')).render(/*#__PURE__*/React.createElement(App, null));

/* expose helpers for sibling screen files (ItemDetail) */
Object.assign(window, {
  SPACES,
  spaceById,
  rotationStatus,
  attentionReason,
  ITEMS
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/ios-app/app.jsx", error: String((e && e.message) || e) }); }

// ui_kits/ios-app/kit-components.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* ============================================================
   Vaultify UI kit — local primitives
   Self-contained, cosmetic mirrors of the design-system core
   components (so the kit renders without the compiled bundle).
   Same tokens, same look. Attached to window for screen files.
   ============================================================ */

const POLARIS_BASE = 'https://unpkg.com/@shopify/polaris-icons@7.13.0/dist/svg/';
const ICON_MAP = {
  home: 'HomeMajor',
  'home.fill': 'HomeFilledMinor',
  items: 'CollectionsMajor',
  'items.fill': 'CollectionsFilledMajor',
  watchtower: 'FraudProtectMajor',
  search: 'SearchMinor',
  categories: 'CategoriesMajor',
  login: 'KeyMajor',
  password: 'KeyMajor',
  card: 'CreditCardMajor',
  identity: 'IdentityCardMajor',
  note: 'ContentMinor',
  email: 'EmailMajor',
  website: 'GlobeMajor',
  bank: 'BankMajor',
  wifi: 'GlobeMajor',
  copy: 'DuplicateMinor',
  view: 'ViewMinor',
  hide: 'HideMinor',
  edit: 'EditMinor',
  delete: 'DeleteMinor',
  add: 'AddMajor',
  'add.circle': 'CirclePlusMinor',
  refresh: 'RefreshMajor',
  filter: 'FilterMajor',
  settings: 'SettingsMajor',
  profile: 'CustomersMajor',
  exit: 'ExitMajor',
  more: 'HorizontalDotsMinor',
  share: 'ExportMinor',
  external: 'ExternalMinor',
  'chevron.right': 'ChevronRightMinor',
  'chevron.left': 'ChevronLeftMinor',
  'chevron.down': 'ChevronDownMinor',
  'chevron.up': 'ChevronUpMinor',
  lock: 'LockMajor',
  unlock: 'KeyMajor',
  success: 'CircleTickMajor',
  alert: 'AlertMinor',
  warning: 'DiamondAlertMajor',
  info: 'InfoMinor',
  favorite: 'FavoriteMajor',
  clock: 'ClockMajor'
};
const iconUrl = n => {
  const file = ICON_MAP[n] || n;
  return typeof window !== 'undefined' && window.__resources && window.__resources[file] || `${POLARIS_BASE}${file}.svg`;
};
const _svgCache = {};
function fetchIconSvg(url) {
  if (!_svgCache[url]) _svgCache[url] = fetch(url).then(r => r.ok ? r.text() : '').catch(() => '');
  return _svgCache[url];
}
function Icon({
  name,
  size = 20,
  color = 'currentColor',
  style
}) {
  const ref = React.useRef(null);
  const dim = typeof size === 'number' ? size + 'px' : size;
  const url = iconUrl(name);
  React.useEffect(() => {
    let alive = true;
    fetchIconSvg(url).then(txt => {
      if (!alive || !ref.current || !txt) return;
      ref.current.innerHTML = txt;
      const svg = ref.current.querySelector('svg');
      if (svg) {
        svg.setAttribute('width', '100%');
        svg.setAttribute('height', '100%');
        svg.style.display = 'block';
        svg.style.fill = color;
      }
    });
    return () => {
      alive = false;
    };
  }, [url, color]);
  return /*#__PURE__*/React.createElement("span", {
    ref: ref,
    "aria-hidden": "true",
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      flex: '0 0 auto',
      width: dim,
      height: dim,
      color,
      ...style
    }
  });
}
function IconTile({
  name,
  tint = 'var(--accent)',
  onTint = 'var(--on-accent)',
  size = 32,
  soft = false,
  radius = 'var(--radius-sm)',
  iconSize,
  style
}) {
  const bg = soft ? `color-mix(in srgb, ${tint} 16%, transparent)` : tint;
  const fg = soft ? tint : onTint;
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      width: size,
      height: size,
      flex: '0 0 auto',
      borderRadius: radius,
      background: bg,
      ...style
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: name,
    size: iconSize || Math.round(size * 0.6),
    color: fg
  }));
}
function usePress() {
  const [p, set] = React.useState(false);
  return [p, {
    onPointerDown: () => set(true),
    onPointerUp: () => set(false),
    onPointerLeave: () => set(false)
  }];
}
function Button({
  children,
  variant = 'primary',
  size = 'md',
  fullWidth = false,
  leadingIcon,
  trailingIcon,
  disabled,
  onClick,
  style
}) {
  const [pressed, bind] = usePress();
  const S = {
    sm: {
      h: 34,
      px: 14,
      f: 15,
      r: 'var(--radius-sm)'
    },
    md: {
      h: 44,
      px: 18,
      f: 17,
      r: 'var(--radius-sm)'
    },
    lg: {
      h: 52,
      px: 22,
      f: 17,
      r: 'var(--radius-md)'
    }
  }[size];
  const V = {
    primary: {
      background: pressed && !disabled ? 'var(--accent-press)' : 'var(--accent)',
      color: 'var(--on-accent)'
    },
    secondary: {
      background: pressed ? 'var(--surface-pressed)' : 'var(--surface-base)',
      color: 'var(--text-primary)',
      boxShadow: 'inset 0 0 0 1px var(--separator)'
    },
    ghost: {
      background: pressed ? 'var(--surface-pressed)' : 'transparent',
      color: 'var(--accent)'
    },
    destructive: {
      background: 'var(--destructive-soft)',
      color: 'var(--destructive)'
    }
  }[variant];
  return /*#__PURE__*/React.createElement("button", _extends({
    onClick: onClick,
    disabled: disabled
  }, bind, {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 8,
      width: fullWidth ? '100%' : 'auto',
      minHeight: S.h,
      padding: `0 ${S.px}px`,
      border: 'none',
      borderRadius: S.r,
      fontFamily: 'var(--font-text)',
      fontSize: S.f,
      fontWeight: 600,
      letterSpacing: '-0.2px',
      lineHeight: 1,
      cursor: disabled ? 'default' : 'pointer',
      opacity: disabled ? 0.4 : 1,
      transform: pressed && !disabled ? 'scale(0.97)' : 'scale(1)',
      transition: 'transform var(--dur-fast) var(--ease-standard), background var(--dur-fast) var(--ease-standard)',
      WebkitTapHighlightColor: 'transparent',
      ...V,
      ...style
    }
  }), leadingIcon && /*#__PURE__*/React.createElement(Icon, {
    name: leadingIcon,
    size: 18
  }), children, trailingIcon && /*#__PURE__*/React.createElement(Icon, {
    name: trailingIcon,
    size: 18
  }));
}
function IconButton({
  name,
  label,
  size = 'md',
  variant = 'plain',
  color = 'var(--icon-primary)',
  onClick,
  style
}) {
  const [pressed, bind] = usePress();
  const box = {
      sm: 32,
      md: 44,
      lg: 48
    }[size],
    ic = {
      sm: 18,
      md: 22,
      lg: 24
    }[size];
  const bg = variant === 'filled' ? 'var(--accent)' : variant === 'tinted' ? 'var(--surface-pressed)' : pressed ? 'var(--surface-pressed)' : 'transparent';
  return /*#__PURE__*/React.createElement("button", _extends({
    "aria-label": label,
    onClick: onClick
  }, bind, {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      width: box,
      height: box,
      border: 'none',
      borderRadius: variant === 'plain' ? 'var(--radius-sm)' : 'var(--radius-pill)',
      background: bg,
      cursor: 'pointer',
      transform: pressed ? 'scale(0.97)' : 'scale(1)',
      transition: 'transform var(--dur-fast) var(--ease-standard), background var(--dur-fast)',
      WebkitTapHighlightColor: 'transparent',
      padding: 0,
      ...style
    }
  }), /*#__PURE__*/React.createElement(Icon, {
    name: name,
    size: ic,
    color: variant === 'filled' ? 'var(--on-accent)' : color
  }));
}
function Card({
  children,
  variant = 'base',
  radius = 'var(--radius-lg)',
  padding = 'var(--space-4)',
  style
}) {
  const V = {
    base: {
      background: 'var(--surface-base)',
      boxShadow: '0 0 0 0.5px var(--separator)'
    },
    elevated: {
      background: 'var(--surface-elevated)',
      boxShadow: 'var(--elevation-2)'
    },
    grouped: {
      background: 'var(--surface-base)',
      boxShadow: '0 0 0 0.5px var(--separator)',
      padding: 0
    }
  }[variant];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      borderRadius: radius,
      padding: variant === 'grouped' ? 0 : padding,
      overflow: variant === 'grouped' ? 'hidden' : 'visible',
      ...V,
      ...style
    }
  }, children);
}
function Row({
  leading,
  title,
  subtitle,
  value,
  trailing,
  chevron,
  tone = 'default',
  divider = true,
  onClick,
  style
}) {
  const [pressed, bind] = usePress();
  const interactive = !!onClick;
  const tc = tone === 'destructive' ? 'var(--destructive)' : tone === 'accent' ? 'var(--accent)' : 'var(--text-primary)';
  return /*#__PURE__*/React.createElement("div", _extends({
    role: interactive ? 'button' : undefined,
    onClick: onClick
  }, interactive ? bind : {}, {
    style: {
      position: 'relative',
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-3)',
      minHeight: 'var(--row-h)',
      padding: '10px var(--space-4)',
      background: pressed ? 'var(--surface-pressed)' : 'transparent',
      cursor: interactive ? 'pointer' : 'default',
      transition: 'background var(--dur-fast)',
      WebkitTapHighlightColor: 'transparent',
      ...style
    }
  }), leading, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0,
      display: 'flex',
      flexDirection: 'column',
      gap: 1
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 17,
      fontWeight: 500,
      color: tc,
      lineHeight: '22px',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, title), subtitle && /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 15,
      color: 'var(--text-secondary)',
      lineHeight: '20px',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, subtitle)), value != null && /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 16,
      color: 'var(--text-secondary)',
      flex: '0 0 auto',
      maxWidth: '45%',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, value), trailing, chevron && /*#__PURE__*/React.createElement(Icon, {
    name: "chevron.right",
    size: 16,
    color: "var(--icon-disabled)"
  }), divider && /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      left: leading ? 'calc(var(--space-4) + 32px + var(--space-3))' : 'var(--space-4)',
      right: 0,
      bottom: 0,
      height: 0.5,
      background: 'var(--separator)'
    }
  }));
}
function SectionHeader({
  title,
  action,
  onAction
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'flex-end',
      justifyContent: 'space-between',
      padding: '0 2px 8px'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 13,
      fontWeight: 600,
      letterSpacing: '0.4px',
      textTransform: 'uppercase',
      color: 'var(--text-tertiary)'
    }
  }, title), action && /*#__PURE__*/React.createElement("button", {
    onClick: onAction,
    style: {
      border: 'none',
      background: 'none',
      padding: 0,
      cursor: 'pointer',
      fontFamily: 'var(--font-text)',
      fontSize: 13,
      fontWeight: 600,
      color: 'var(--accent)'
    }
  }, action));
}
function Switch({
  checked,
  onChange,
  label
}) {
  return /*#__PURE__*/React.createElement("button", {
    role: "switch",
    "aria-checked": checked,
    "aria-label": label,
    onClick: () => onChange && onChange(!checked),
    style: {
      position: 'relative',
      width: 51,
      height: 31,
      flex: '0 0 auto',
      padding: 0,
      border: 'none',
      borderRadius: 'var(--radius-pill)',
      background: checked ? 'var(--accent)' : 'color-mix(in srgb, var(--text-primary) 18%, transparent)',
      cursor: 'pointer',
      transition: 'background var(--dur-base) var(--ease-standard)',
      WebkitTapHighlightColor: 'transparent'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      top: 2,
      left: checked ? 22 : 2,
      width: 27,
      height: 27,
      borderRadius: '50%',
      background: '#fff',
      boxShadow: '0 1px 3px rgba(0,0,0,0.28)',
      transition: 'left var(--dur-base) var(--ease-standard)'
    }
  }));
}
function SegmentedControl({
  options = [],
  value,
  onChange,
  style
}) {
  const opts = options.map(o => typeof o === 'string' ? {
    value: o,
    label: o
  } : o);
  const idx = Math.max(0, opts.findIndex(o => o.value === value));
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative',
      display: 'grid',
      gridTemplateColumns: `repeat(${opts.length},1fr)`,
      gap: 2,
      padding: 2,
      background: 'color-mix(in srgb, var(--text-primary) 8%, transparent)',
      borderRadius: 'var(--radius-sm)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      top: 2,
      bottom: 2,
      left: `calc(${idx} * (100% - 4px) / ${opts.length} + 2px)`,
      width: `calc((100% - 4px) / ${opts.length})`,
      background: 'var(--surface-base)',
      borderRadius: 'calc(var(--radius-sm) - 2px)',
      boxShadow: '0 1px 3px var(--shadow-ambient)',
      transition: 'left var(--dur-base) var(--ease-standard)'
    }
  }), opts.map(o => {
    const a = o.value === value;
    return /*#__PURE__*/React.createElement("button", {
      key: o.value,
      onClick: () => onChange && onChange(o.value),
      style: {
        position: 'relative',
        zIndex: 1,
        minHeight: 32,
        border: 'none',
        background: 'transparent',
        cursor: 'pointer',
        fontFamily: 'var(--font-text)',
        fontSize: 15,
        fontWeight: a ? 600 : 500,
        color: a ? 'var(--text-primary)' : 'var(--text-secondary)',
        WebkitTapHighlightColor: 'transparent',
        transition: 'color var(--dur-fast)'
      }
    }, o.label);
  }));
}
function Badge({
  count,
  dot = false,
  tone = 'destructive',
  max = 99
}) {
  const bg = {
    destructive: 'var(--destructive)',
    accent: 'var(--accent)',
    neutral: 'var(--icon-secondary)',
    success: 'var(--success)',
    warning: 'var(--warning)'
  }[tone];
  if (dot) return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-block',
      width: 8,
      height: 8,
      borderRadius: '50%',
      background: bg,
      boxShadow: '0 0 0 2px var(--surface-base)'
    }
  });
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      minWidth: 18,
      height: 18,
      padding: '0 5px',
      borderRadius: 'var(--radius-pill)',
      background: bg,
      color: '#fff',
      fontFamily: 'var(--font-text)',
      fontSize: 11,
      fontWeight: 700,
      lineHeight: 1,
      fontVariantNumeric: 'tabular-nums'
    }
  }, count > max ? `${max}+` : count);
}
const STR = [{
  label: 'Too weak',
  color: 'var(--destructive)'
}, {
  label: 'Weak',
  color: 'var(--destructive)'
}, {
  label: 'Fair',
  color: 'var(--warning)'
}, {
  label: 'Good',
  color: 'var(--accent)'
}, {
  label: 'Strong',
  color: 'var(--success)'
}];
function StrengthMeter({
  score = 0,
  showLabel = true,
  label,
  style
}) {
  const s = Math.max(0, Math.min(4, score)),
    lvl = STR[s];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 6,
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 5
    }
  }, [1, 2, 3, 4].map(seg => /*#__PURE__*/React.createElement("span", {
    key: seg,
    style: {
      flex: 1,
      height: 4,
      borderRadius: 'var(--radius-pill)',
      background: seg <= s ? lvl.color : 'color-mix(in srgb, var(--text-primary) 12%, transparent)',
      transition: 'background var(--dur-base)'
    }
  }))), showLabel && /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 13,
      fontWeight: 500,
      color: lvl.color
    }
  }, label || lvl.label));
}
function TabBar({
  tabs = [],
  value,
  onChange,
  glass = false,
  style
}) {
  const idx = Math.max(0, tabs.findIndex(t => t.id === value)),
    n = tabs.length || 1;
  return /*#__PURE__*/React.createElement("nav", {
    "aria-label": "Primary",
    style: {
      position: 'relative',
      display: 'grid',
      gridTemplateColumns: `repeat(${n},1fr)`,
      alignItems: 'center',
      height: 'var(--tabbar-height)',
      padding: '0 6px',
      borderRadius: 'var(--tabbar-radius)',
      background: glass ? 'var(--surface-floating)' : 'var(--surface-floating-solid)',
      backdropFilter: glass ? 'blur(24px) saturate(1.8)' : 'none',
      WebkitBackdropFilter: glass ? 'blur(24px) saturate(1.8)' : 'none',
      boxShadow: 'var(--elevation-3), 0 0 0 0.5px var(--separator)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      top: '50%',
      height: 44,
      width: 46,
      transform: 'translateY(-50%)',
      left: `calc(${idx} * (100% - 12px) / ${n} + (100% - 12px) / ${n} / 2 - 23px + 6px)`,
      background: 'var(--accent-soft)',
      borderRadius: 'var(--radius-pill)',
      transition: 'left var(--dur-medium) var(--ease-spring)'
    }
  }), tabs.map(t => {
    const a = t.id === value,
      nm = a && t.iconFill ? t.iconFill : t.icon;
    return /*#__PURE__*/React.createElement("button", {
      key: t.id,
      role: "tab",
      "aria-selected": a,
      "aria-label": t.label,
      onClick: () => onChange && onChange(t.id),
      style: {
        position: 'relative',
        zIndex: 1,
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        minWidth: 56,
        minHeight: 48,
        height: '100%',
        border: 'none',
        background: 'transparent',
        cursor: 'pointer',
        padding: 0,
        WebkitTapHighlightColor: 'transparent'
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        position: 'relative',
        display: 'inline-flex'
      }
    }, /*#__PURE__*/React.createElement(Icon, {
      name: nm,
      size: a ? 27 : 24,
      color: a ? 'var(--accent)' : 'var(--icon-secondary)'
    }), (t.badge != null || t.badgeDot) && /*#__PURE__*/React.createElement("span", {
      style: {
        position: 'absolute',
        top: -3,
        right: -8
      }
    }, /*#__PURE__*/React.createElement(Badge, {
      dot: t.badgeDot,
      count: t.badge
    }))));
  }));
}

/* ---- iPhone frame + status bar (device chrome, drawn) ---- */
function StatusBar() {
  const c = 'var(--text-primary)';
  return /*#__PURE__*/React.createElement("div", {
    style: {
      height: 54,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '0 30px 0 34px',
      flex: '0 0 auto'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 16,
      fontWeight: 600,
      color: c,
      letterSpacing: '-0.2px'
    }
  }, "9:41"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 7
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: "18",
    height: "12",
    viewBox: "0 0 18 12",
    "aria-hidden": "true"
  }, [0, 1, 2, 3].map(i => /*#__PURE__*/React.createElement("rect", {
    key: i,
    x: i * 4.6,
    y: 9 - i * 2.6,
    width: "3",
    height: 3 + i * 2.6,
    rx: "1",
    fill: c
  }))), /*#__PURE__*/React.createElement("svg", {
    width: "17",
    height: "12",
    viewBox: "0 0 17 12",
    fill: "none",
    stroke: c,
    strokeWidth: "1.6",
    strokeLinecap: "round",
    "aria-hidden": "true"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M2 4.3C6 1 11 1 15 4.3"
  }), /*#__PURE__*/React.createElement("path", {
    d: "M4.3 7C6.6 5 10.4 5 12.7 7"
  }), /*#__PURE__*/React.createElement("circle", {
    cx: "8.5",
    cy: "9.6",
    r: "0.9",
    fill: c,
    stroke: "none"
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      width: 25,
      height: 13,
      borderRadius: 3,
      boxShadow: `inset 0 0 0 1.2px ${c}`,
      position: 'relative',
      opacity: 0.95
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      top: 2,
      bottom: 2,
      left: 2,
      width: '72%',
      background: c,
      borderRadius: 1.5
    }
  }))));
}
function IPhone({
  children,
  theme = 'light',
  accent = 'blue'
}) {
  return /*#__PURE__*/React.createElement("div", {
    "data-theme": theme,
    "data-accent": accent,
    style: {
      width: 390,
      height: 844,
      borderRadius: 54,
      background: 'var(--background-base)',
      position: 'relative',
      overflow: 'hidden',
      boxShadow: '0 1px 0 1px rgba(0,0,0,0.04), 0 30px 70px rgba(0,0,0,0.28), inset 0 0 0 1px var(--separator)',
      display: 'flex',
      flexDirection: 'column'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      top: 11,
      left: '50%',
      transform: 'translateX(-50%)',
      width: 124,
      height: 36,
      background: '#000',
      borderRadius: 20,
      zIndex: 50
    }
  }), children);
}

/* ---- TOTP (authenticator codes) ---- */
function totpCode(seed, step) {
  let h = 2166136261;
  const s = (seed || '') + ':' + step;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return String((h >>> 0) % 1000000).padStart(6, '0');
}
function useTotp(seed, period = 30) {
  const [t, setT] = React.useState(() => Math.floor(Date.now() / 1000));
  React.useEffect(() => {
    const id = setInterval(() => setT(Math.floor(Date.now() / 1000)), 1000);
    return () => clearInterval(id);
  }, []);
  const step = Math.floor(t / period),
    remaining = period - t % period;
  return {
    code: totpCode(seed, step),
    remaining,
    period,
    progress: remaining / period
  };
}
function fmtCode(c) {
  return c ? c.slice(0, 3) + ' ' + c.slice(3) : '';
}
function TotpRing({
  progress,
  remaining,
  size = 26
}) {
  const r = (size - 4) / 2,
    c = 2 * Math.PI * r,
    off = c * (1 - progress);
  const col = remaining <= 5 ? 'var(--warning)' : 'var(--accent)';
  return /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'relative',
      width: size,
      height: size,
      flex: '0 0 auto'
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: size,
    height: size,
    viewBox: `0 0 ${size} ${size}`,
    style: {
      transform: 'rotate(-90deg)'
    },
    "aria-hidden": "true"
  }, /*#__PURE__*/React.createElement("circle", {
    cx: size / 2,
    cy: size / 2,
    r: r,
    fill: "none",
    stroke: "color-mix(in srgb, var(--text-primary) 12%, transparent)",
    strokeWidth: "2.5"
  }), /*#__PURE__*/React.createElement("circle", {
    cx: size / 2,
    cy: size / 2,
    r: r,
    fill: "none",
    stroke: col,
    strokeWidth: "2.5",
    strokeLinecap: "round",
    strokeDasharray: c,
    strokeDashoffset: off,
    style: {
      transition: 'stroke-dashoffset 1s linear, stroke var(--dur-base)'
    }
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      inset: 0,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      fontFamily: 'var(--font-mono)',
      fontSize: 10,
      fontWeight: 600,
      color: col,
      fontVariantNumeric: 'tabular-nums'
    }
  }, remaining));
}
/* Horizontal authenticator card for Home */
function TotpCard({
  item,
  onCopy
}) {
  const {
    code,
    remaining,
    progress
  } = useTotp(item.totp);
  const [copied, setCopied] = React.useState(false);
  function copy() {
    setCopied(true);
    setTimeout(() => setCopied(false), 1100);
    onCopy && onCopy();
  }
  return /*#__PURE__*/React.createElement("button", {
    onClick: copy,
    style: {
      flex: '0 0 auto',
      width: 158,
      textAlign: 'left',
      border: 'none',
      cursor: 'pointer',
      background: 'var(--surface-base)',
      borderRadius: 'var(--radius-md)',
      boxShadow: '0 0 0 0.5px var(--separator)',
      padding: '12px 14px',
      display: 'flex',
      flexDirection: 'column',
      gap: 10,
      WebkitTapHighlightColor: 'transparent'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between'
    }
  }, /*#__PURE__*/React.createElement(IconTile, {
    name: item.icon,
    tint: item.tint,
    size: 26,
    iconSize: 15
  }), /*#__PURE__*/React.createElement(TotpRing, {
    progress: progress,
    remaining: remaining
  })), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-mono)',
      fontSize: 23,
      fontWeight: 600,
      letterSpacing: '0.06em',
      color: copied ? 'var(--success)' : 'var(--text-primary)',
      fontVariantNumeric: 'tabular-nums',
      transition: 'color var(--dur-fast)'
    }
  }, copied ? 'Đã chép' : fmtCode(code)), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 5,
      marginTop: 2
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 13,
      color: 'var(--text-secondary)',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, item.name))));
}

/* ---- Space tag (which space an item belongs to) ---- */
function SpaceTag({
  space,
  size = 'sm'
}) {
  if (!space) return null;
  const pad = size === 'sm' ? '2px 7px 2px 6px' : '3px 9px 3px 7px';
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 5,
      padding: pad,
      borderRadius: 'var(--radius-pill)',
      background: 'color-mix(in srgb, ' + space.tint + ' 14%, transparent)',
      maxWidth: '100%'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 6,
      height: 6,
      borderRadius: '50%',
      background: space.tint,
      flex: '0 0 auto'
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 11,
      fontWeight: 600,
      color: space.tint,
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis',
      letterSpacing: '0.1px'
    }
  }, space.name));
}

/* ---- Quick action tile (Home) ---- */
function QuickAction({
  icon,
  label,
  tint = 'var(--accent)',
  onClick
}) {
  const [p, bind] = usePress();
  return /*#__PURE__*/React.createElement("button", _extends({
    onClick: onClick
  }, bind, {
    style: {
      flex: 1,
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      gap: 8,
      border: 'none',
      background: 'transparent',
      cursor: 'pointer',
      padding: '2px 0',
      WebkitTapHighlightColor: 'transparent',
      transform: p ? 'scale(0.96)' : 'scale(1)',
      transition: 'transform var(--dur-fast)'
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      width: 54,
      height: 54,
      borderRadius: 'var(--radius-md)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      background: 'color-mix(in srgb, ' + tint + ' 14%, transparent)'
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: icon,
    size: 24,
    color: tint
  })), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 12,
      fontWeight: 500,
      color: 'var(--text-secondary)',
      textAlign: 'center',
      lineHeight: '14px'
    }
  }, label));
}

/* ---- Bottom sheet ---- */
function Sheet({
  title,
  onClose,
  children,
  maxHeight = '86%'
}) {
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClose,
    style: {
      position: 'absolute',
      inset: 0,
      zIndex: 80,
      background: 'rgba(0,0,0,0.32)',
      display: 'flex',
      flexDirection: 'column',
      justifyContent: 'flex-end',
      animation: 'fade var(--dur-fast) var(--ease-standard)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    onClick: e => e.stopPropagation(),
    style: {
      background: 'var(--background-grouped)',
      borderTopLeftRadius: 'var(--radius-xl)',
      borderTopRightRadius: 'var(--radius-xl)',
      maxHeight,
      display: 'flex',
      flexDirection: 'column',
      overflow: 'hidden',
      boxShadow: 'var(--elevation-sheet)',
      animation: 'sheetUp var(--dur-medium) var(--ease-standard)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: '0 0 auto',
      paddingTop: 8
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 38,
      height: 5,
      borderRadius: 3,
      background: 'var(--separator-opaque)',
      margin: '0 auto 6px'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '6px 12px 10px'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 60
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-text)',
      fontSize: 17,
      fontWeight: 600,
      color: 'var(--text-primary)'
    }
  }, title), /*#__PURE__*/React.createElement("button", {
    onClick: onClose,
    style: {
      width: 60,
      textAlign: 'right',
      border: 'none',
      background: 'none',
      cursor: 'pointer',
      color: 'var(--accent)',
      fontFamily: 'var(--font-text)',
      fontSize: 17,
      fontWeight: 600,
      padding: '2px 4px'
    }
  }, "Xong"))), /*#__PURE__*/React.createElement("div", {
    style: {
      overflowY: 'auto',
      padding: '0 var(--screen-gutter) calc(var(--space-6) + env(safe-area-inset-bottom))'
    }
  }, children)));
}
Object.assign(window, {
  Icon,
  IconTile,
  Button,
  IconButton,
  Card,
  Row,
  SectionHeader,
  Switch,
  SegmentedControl,
  Badge,
  StrengthMeter,
  TabBar,
  StatusBar,
  IPhone,
  iconUrl,
  ICON_MAP,
  useTotp,
  TotpRing,
  TotpCard,
  fmtCode,
  SpaceTag,
  QuickAction,
  Sheet
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/ios-app/kit-components.jsx", error: String((e && e.message) || e) }); }

__ds_ns.Badge = __ds_scope.Badge;

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Card = __ds_scope.Card;

__ds_ns.Field = __ds_scope.Field;

__ds_ns.POLARIS_BASE = __ds_scope.POLARIS_BASE;

__ds_ns.ICON_MAP = __ds_scope.ICON_MAP;

__ds_ns.Icon = __ds_scope.Icon;

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.IconTile = __ds_scope.IconTile;

__ds_ns.Row = __ds_scope.Row;

__ds_ns.SectionHeader = __ds_scope.SectionHeader;

__ds_ns.SegmentedControl = __ds_scope.SegmentedControl;

__ds_ns.StrengthMeter = __ds_scope.StrengthMeter;

__ds_ns.Switch = __ds_scope.Switch;

__ds_ns.TabBar = __ds_scope.TabBar;

})();
