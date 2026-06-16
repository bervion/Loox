import React from 'react';
import { Icon } from './Icon';

/* IconTile — rounded, tinted square holding a single icon.
   The standard leading element for list rows and item lists. */
export function IconTile({
  name,
  tint = 'var(--accent)',
  onTint = 'var(--on-accent)',
  size = 'var(--icon-tile)',
  iconSize,
  radius = 'var(--radius-sm)',
  soft = false,           // soft = tinted background + colored glyph
  style,
  ...rest
}) {
  const dim = typeof size === 'number' ? `${size}px` : size;
  const glyph = iconSize || `calc(${typeof size === 'number' ? dim : '1px * 0 + ' + dim} * 0.62)`;
  const bg = soft ? `color-mix(in srgb, ${tint} 16%, transparent)` : tint;
  const fg = soft ? tint : onTint;
  return (
    <span
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        justifyContent: 'center',
        width: dim,
        height: dim,
        flex: '0 0 auto',
        borderRadius: radius,
        background: bg,
        ...style,
      }}
      {...rest}
    >
      <Icon name={name} size={iconSize || `calc(${dim} * 0.6)`} color={fg} />
    </span>
  );
}
