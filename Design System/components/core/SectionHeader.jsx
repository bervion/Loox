import React from 'react';
import { Icon } from './Icon';

/* SectionHeader — grouped-list section label. Quiet, uppercase-ish
   caption with optional trailing action (text or icon button). */
export function SectionHeader({
  title,
  action,
  onAction,
  actionIcon,
  uppercase = true,
  style,
  ...rest
}) {
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'flex-end',
        justifyContent: 'space-between',
        gap: 'var(--space-3)',
        padding: `0 var(--space-1) var(--space-2)`,
        ...style,
      }}
      {...rest}
    >
      <span
        style={{
          fontFamily: 'var(--font-text)',
          fontSize: 'var(--size-footnote)',
          fontWeight: 'var(--weight-semibold)',
          letterSpacing: uppercase ? '0.4px' : 'var(--tracking-normal)',
          textTransform: uppercase ? 'uppercase' : 'none',
          color: 'var(--text-tertiary)',
        }}
      >
        {title}
      </span>
      {action && (
        <button
          type="button"
          onClick={onAction}
          style={{
            display: 'inline-flex', alignItems: 'center', gap: 4,
            border: 'none', background: 'none', padding: 0, cursor: 'pointer',
            fontFamily: 'var(--font-text)', fontSize: 'var(--size-footnote)',
            fontWeight: 'var(--weight-semibold)', color: 'var(--accent)',
            WebkitTapHighlightColor: 'transparent',
          }}
        >
          {action}
          {actionIcon && <Icon name={actionIcon} size={14} color="var(--accent)" />}
        </button>
      )}
    </div>
  );
}
