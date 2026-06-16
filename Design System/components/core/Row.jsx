import React from 'react';
import { Icon } from './Icon';

/* Row — the workhorse grouped-list row.
   leading (e.g. <IconTile/>) · title + optional subtitle ·
   trailing value text · chevron / custom trailing control. */
export function Row({
  leading,
  title,
  subtitle,
  value,
  trailing,
  chevron = false,
  tone = 'default',     // default | accent | destructive
  divider = true,       // inset hairline at bottom (off for last row)
  onClick,
  style,
  ...rest
}) {
  const [pressed, setPressed] = React.useState(false);
  const interactive = !!onClick;
  const titleColor =
    tone === 'destructive' ? 'var(--destructive)'
    : tone === 'accent' ? 'var(--accent)'
    : 'var(--text-primary)';

  return (
    <div
      role={interactive ? 'button' : undefined}
      tabIndex={interactive ? 0 : undefined}
      onClick={onClick}
      onPointerDown={() => interactive && setPressed(true)}
      onPointerUp={() => setPressed(false)}
      onPointerLeave={() => setPressed(false)}
      style={{
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
        ...style,
      }}
      {...rest}
    >
      {leading}
      <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 1 }}>
        <span
          style={{
            fontFamily: 'var(--font-text)', fontSize: 'var(--size-headline)',
            fontWeight: 'var(--weight-medium)', color: titleColor,
            lineHeight: 'var(--lh-headline)',
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}
        >
          {title}
        </span>
        {subtitle && (
          <span
            style={{
              fontFamily: 'var(--font-text)', fontSize: 'var(--size-subhead)',
              color: 'var(--text-secondary)', lineHeight: 'var(--lh-subhead)',
              whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
            }}
          >
            {subtitle}
          </span>
        )}
      </div>
      {value != null && (
        <span
          style={{
            fontFamily: 'var(--font-text)', fontSize: 'var(--size-callout)',
            color: 'var(--text-secondary)', flex: '0 0 auto',
            maxWidth: '45%', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}
        >
          {value}
        </span>
      )}
      {trailing}
      {chevron && <Icon name="chevron.right" size={16} color="var(--icon-disabled)" />}
      {divider && (
        <span
          aria-hidden="true"
          style={{
            position: 'absolute', left: leading ? 'calc(var(--space-4) + var(--icon-tile) + var(--space-3))' : 'var(--space-4)',
            right: 0, bottom: 0, height: 0.5, background: 'var(--separator)',
          }}
        />
      )}
    </div>
  );
}
