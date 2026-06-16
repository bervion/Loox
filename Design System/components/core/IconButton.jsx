import React from 'react';
import { Icon } from './Icon';

/* IconButton — icon-only control. Always requires `label` (a11y). */
const IB_SIZES = {
  sm: { box: 32, icon: 18 },
  md: { box: 44, icon: 22 },
  lg: { box: 48, icon: 24 },
};

export function IconButton({
  name,
  label,
  size = 'md',
  variant = 'plain',   // plain | filled | tinted
  color = 'var(--icon-primary)',
  disabled = false,
  style,
  onClick,
  ...rest
}) {
  const [pressed, setPressed] = React.useState(false);
  const s = IB_SIZES[size] || IB_SIZES.md;
  const bg =
    variant === 'filled' ? 'var(--accent)'
    : variant === 'tinted' ? 'var(--surface-pressed)'
    : (pressed ? 'var(--surface-pressed)' : 'transparent');
  const fg = variant === 'filled' ? 'var(--on-accent)' : color;
  return (
    <button
      type="button"
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
      onPointerDown={() => setPressed(true)}
      onPointerUp={() => setPressed(false)}
      onPointerLeave={() => setPressed(false)}
      style={{
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
        ...style,
      }}
      {...rest}
    >
      <Icon name={name} size={s.icon} color={fg} />
    </button>
  );
}
