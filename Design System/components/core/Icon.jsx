import React from 'react';

/* ============================================================
   Vaultify Icon system
   Renders Shopify Polaris icons (v7.13.0) loaded from the unpkg
   CDN and recolored via CSS mask, so a single semantic color
   token drives the glyph — exactly like an SF Symbols family.

   Use semantic names from ICON_MAP, or pass any Polaris filename
   stem directly (e.g. name="LockMajor").
   ============================================================ */

export const POLARIS_BASE =
  'https://unpkg.com/@shopify/polaris-icons@7.13.0/dist/svg/';

// Semantic name -> Polaris file stem. Outline + filled where it exists.
export const ICON_MAP = {
  // Navigation / tabs
  home: 'HomeMajor',            'home.fill': 'HomeFilledMinor',
  items: 'CollectionsMajor',    'items.fill': 'CollectionsFilledMajor',
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
  clock: 'ClockMajor',
};

export function resolveIcon(name) {
  return ICON_MAP[name] || name;
}

export function iconUrl(name) {
  return `${POLARIS_BASE}${resolveIcon(name)}.svg`;
}

// Fetch + cache raw SVG markup so glyphs render as real DOM SVG
// (recolorable via `fill`, and visible to screenshot/export renderers).
const _svgCache = {};
export function fetchIconSvg(url) {
  if (!_svgCache[url]) {
    _svgCache[url] = fetch(url).then((r) => (r.ok ? r.text() : '')).catch(() => '');
  }
  return _svgCache[url];
}

export function Icon({
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
    fetchIconSvg(url).then((txt) => {
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
    return () => { alive = false; };
  }, [url, color]);

  return (
    <span
      ref={ref}
      role={decorative ? undefined : 'img'}
      aria-hidden={decorative ? 'true' : undefined}
      aria-label={decorative ? undefined : label || name}
      className={className}
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        flex: '0 0 auto',
        width: dim,
        height: dim,
        color,
        ...style,
      }}
      {...rest}
    />
  );
}
