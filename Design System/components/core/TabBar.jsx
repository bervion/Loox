import React from 'react';
import { Icon } from './Icon';
import { Badge } from './Badge';

/* VaultTabBar — custom, icon-only, floating tab bar.
   - No visible labels (labels live in aria only)
   - Compact sliding pill marks the active tab (Apple/Threads feel)
   - Solid fallback by default; glass control layer when `glass`
   - Meaningful badges only (dot or compact counter)
   tabs: [{ id, icon, iconFill?, label, badge?, badgeDot? }] */
export function TabBar({
  tabs = [],
  value,
  onChange,
  glass = false,
  style,
  ...rest
}) {
  const idx = Math.max(0, tabs.findIndex((t) => t.id === value));
  const n = tabs.length || 1;

  return (
    <nav
      aria-label="Primary"
      style={{
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
        ...style,
      }}
      {...rest}
    >
      {/* sliding selected pill */}
      <span
        aria-hidden="true"
        style={{
          position: 'absolute',
          top: '50%',
          height: 44,
          width: 46,
          transform: 'translateY(-50%)',
          left: `calc(${idx} * (100% - 12px) / ${n} + (100% - 12px) / ${n} / 2 - 23px + 6px)`,
          background: 'var(--accent-soft)',
          borderRadius: 'var(--radius-pill)',
          transition: 'left var(--dur-medium) var(--ease-spring)',
        }}
      />
      {tabs.map((t) => {
        const active = t.id === value;
        const iconName = active && t.iconFill ? t.iconFill : t.icon;
        return (
          <button
            key={t.id}
            type="button"
            role="tab"
            aria-selected={active}
            aria-label={t.label}
            onClick={() => onChange && onChange(t.id)}
            style={{
              position: 'relative', zIndex: 1,
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              minWidth: 56, minHeight: 48, height: '100%',
              border: 'none', background: 'transparent', cursor: 'pointer', padding: 0,
              WebkitTapHighlightColor: 'transparent',
            }}
          >
            <span style={{ position: 'relative', display: 'inline-flex' }}>
              <Icon
                name={iconName}
                size={active ? 'var(--icon-tab)' : 24}
                color={active ? 'var(--accent)' : 'var(--icon-secondary)'}
                style={{ transition: 'background-color var(--dur-base) var(--ease-standard)' }}
              />
              {(t.badge != null || t.badgeDot) && (
                <span style={{ position: 'absolute', top: -3, right: -8 }}>
                  <Badge dot={t.badgeDot} count={t.badge} tone="destructive" />
                </span>
              )}
            </span>
          </button>
        );
      })}
    </nav>
  );
}
