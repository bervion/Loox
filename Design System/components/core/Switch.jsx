import React from 'react';

/* Switch — iOS toggle. accent fill when on. */
export function Switch({
  checked = false,
  onChange,
  disabled = false,
  label,
  style,
  ...rest
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      disabled={disabled}
      onClick={() => !disabled && onChange && onChange(!checked)}
      style={{
        position: 'relative',
        width: 51,
        height: 31,
        flex: '0 0 auto',
        padding: 0,
        border: 'none',
        borderRadius: 'var(--radius-pill)',
        background: checked ? 'var(--accent)' : 'color-mix(in srgb, var(--text-primary) 18%, transparent)',
        cursor: disabled ? 'default' : 'pointer',
        opacity: disabled ? 0.5 : 1,
        transition: 'background var(--dur-base) var(--ease-standard)',
        WebkitTapHighlightColor: 'transparent',
        ...style,
      }}
      {...rest}
    >
      <span
        aria-hidden="true"
        style={{
          position: 'absolute',
          top: 2,
          left: checked ? 22 : 2,
          width: 27,
          height: 27,
          borderRadius: '50%',
          background: '#fff',
          boxShadow: '0 1px 3px rgba(0,0,0,0.28), 0 0 1px rgba(0,0,0,0.2)',
          transition: 'left var(--dur-base) var(--ease-standard)',
        }}
      />
    </button>
  );
}
