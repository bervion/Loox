import React from 'react';

/* Badge — alert dot or compact counter. Non-text contrast safe. */
export function Badge({
  count,
  dot = false,
  tone = 'destructive',   // destructive | accent | neutral | success | warning
  max = 99,
  style,
  ...rest
}) {
  const toneBg = {
    destructive: 'var(--destructive)',
    accent: 'var(--accent)',
    neutral: 'var(--icon-secondary)',
    success: 'var(--success)',
    warning: 'var(--warning)',
  }[tone] || 'var(--destructive)';

  if (dot) {
    return (
      <span
        aria-hidden="true"
        style={{
          display: 'inline-block', width: 8, height: 8, borderRadius: '50%',
          background: toneBg, boxShadow: '0 0 0 2px var(--surface-base)', ...style,
        }}
        {...rest}
      />
    );
  }
  const text = typeof count === 'number' && count > max ? `${max}+` : count;
  return (
    <span
      style={{
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        minWidth: 18, height: 18, padding: '0 5px', borderRadius: 'var(--radius-pill)',
        background: toneBg, color: '#fff',
        fontFamily: 'var(--font-text)', fontSize: 11, fontWeight: 'var(--weight-bold)',
        lineHeight: 1, fontVariantNumeric: 'tabular-nums', ...style,
      }}
      {...rest}
    >
      {text}
    </span>
  );
}
