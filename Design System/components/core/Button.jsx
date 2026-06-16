import React from 'react';
import { Icon } from './Icon';

/* Button — primary / secondary / ghost / destructive, three sizes.
   Native-feeling press: subtle scale + deepened fill. */
const SIZES = {
  sm: { h: 'var(--control-h-sm)', px: 14, font: 'var(--size-subhead)', radius: 'var(--radius-sm)', gap: 6 },
  md: { h: 'var(--control-h-md)', px: 18, font: 'var(--size-body)',    radius: 'var(--radius-sm)', gap: 8 },
  lg: { h: 'var(--control-h-lg)', px: 22, font: 'var(--size-body)',    radius: 'var(--radius-md)', gap: 8 },
};

function variantStyle(variant, pressed) {
  switch (variant) {
    case 'secondary':
      return { background: pressed ? 'var(--surface-pressed)' : 'var(--surface-base)',
               color: 'var(--text-primary)', boxShadow: 'inset 0 0 0 1px var(--separator)' };
    case 'ghost':
      return { background: pressed ? 'var(--surface-pressed)' : 'transparent',
               color: 'var(--accent)', boxShadow: 'none' };
    case 'destructive':
      return { background: pressed ? 'var(--destructive-soft)' : 'var(--destructive-soft)',
               color: 'var(--destructive)', boxShadow: 'none',
               filter: pressed ? 'brightness(0.96)' : 'none' };
    case 'primary':
    default:
      return { background: pressed ? 'var(--accent-press)' : 'var(--accent)',
               color: 'var(--on-accent)', boxShadow: 'none' };
  }
}

export function Button({
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
  return (
    <button
      type={type}
      disabled={disabled}
      onClick={onClick}
      onPointerDown={() => setPressed(true)}
      onPointerUp={() => setPressed(false)}
      onPointerLeave={() => setPressed(false)}
      style={{
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
        ...style,
      }}
      {...rest}
    >
      {leadingIcon && <Icon name={leadingIcon} size={s.font === 'var(--size-subhead)' ? 16 : 18} color="currentColor" />}
      {children}
      {trailingIcon && <Icon name={trailingIcon} size={s.font === 'var(--size-subhead)' ? 16 : 18} color="currentColor" />}
    </button>
  );
}
