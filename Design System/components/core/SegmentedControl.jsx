import React from 'react';

/* SegmentedControl — iOS segmented picker.
   options: [{value,label}] or string[]. */
export function SegmentedControl({
  options = [],
  value,
  onChange,
  style,
  ...rest
}) {
  const opts = options.map((o) => (typeof o === 'string' ? { value: o, label: o } : o));
  const idx = Math.max(0, opts.findIndex((o) => o.value === value));
  return (
    <div
      role="tablist"
      style={{
        position: 'relative',
        display: 'grid',
        gridTemplateColumns: `repeat(${opts.length}, 1fr)`,
        gap: 2,
        padding: 2,
        background: 'color-mix(in srgb, var(--text-primary) 8%, transparent)',
        borderRadius: 'var(--radius-sm)',
        ...style,
      }}
      {...rest}
    >
      <span
        aria-hidden="true"
        style={{
          position: 'absolute',
          top: 2, bottom: 2,
          left: `calc(${idx} * (100% - 4px) / ${opts.length} + 2px)`,
          width: `calc((100% - 4px) / ${opts.length})`,
          background: 'var(--surface-base)',
          borderRadius: 'calc(var(--radius-sm) - 2px)',
          boxShadow: '0 1px 3px var(--shadow-ambient)',
          transition: 'left var(--dur-base) var(--ease-standard)',
        }}
      />
      {opts.map((o) => {
        const active = o.value === value;
        return (
          <button
            key={o.value}
            type="button"
            role="tab"
            aria-selected={active}
            onClick={() => onChange && onChange(o.value)}
            style={{
              position: 'relative', zIndex: 1,
              minHeight: 32, border: 'none', background: 'transparent',
              cursor: 'pointer', WebkitTapHighlightColor: 'transparent',
              fontFamily: 'var(--font-text)', fontSize: 'var(--size-subhead)',
              fontWeight: active ? 'var(--weight-semibold)' : 'var(--weight-medium)',
              color: active ? 'var(--text-primary)' : 'var(--text-secondary)',
              transition: 'color var(--dur-fast) var(--ease-standard)',
            }}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}
