import React from 'react';

/* StrengthMeter — password / vault health strength.
   score: 0 (empty) … 4 (strong). Four segments, color-coded. */
const LEVELS = [
  { label: 'Too weak', color: 'var(--destructive)' },
  { label: 'Weak',     color: 'var(--destructive)' },
  { label: 'Fair',     color: 'var(--warning)' },
  { label: 'Good',     color: 'var(--accent)' },
  { label: 'Strong',   color: 'var(--success)' },
];

export function StrengthMeter({
  score = 0,
  showLabel = true,
  label,
  style,
  ...rest
}) {
  const s = Math.max(0, Math.min(4, score));
  const lvl = LEVELS[s];
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6, ...style }} {...rest}>
      <div style={{ display: 'flex', gap: 5 }}>
        {[1, 2, 3, 4].map((seg) => (
          <span
            key={seg}
            style={{
              flex: 1, height: 4, borderRadius: 'var(--radius-pill)',
              background: seg <= s ? lvl.color : 'color-mix(in srgb, var(--text-primary) 12%, transparent)',
              transition: 'background var(--dur-base) var(--ease-standard)',
            }}
          />
        ))}
      </div>
      {showLabel && (
        <span style={{
          fontFamily: 'var(--font-text)', fontSize: 'var(--size-footnote)',
          fontWeight: 'var(--weight-medium)', color: lvl.color,
        }}>{label || lvl.label}</span>
      )}
    </div>
  );
}
