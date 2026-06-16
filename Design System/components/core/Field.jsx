import React from 'react';
import { Icon } from './Icon';

/* Field — labeled text input, iOS grouped style.
   Supports leading icon, secure (password) mode with reveal,
   monospace values, and a custom trailing slot (e.g. copy button). */
export function Field({
  label,
  value,
  defaultValue,
  onChange,
  placeholder,
  type = 'text',
  leadingIcon,
  secure = false,
  revealable = false,
  mono = false,
  trailing,
  disabled = false,
  readOnly = false,
  style,
  inputStyle,
  ...rest
}) {
  const [revealed, setRevealed] = React.useState(false);
  const isSecure = secure && !revealed;
  const inputType = isSecure ? 'password' : (type === 'password' ? 'text' : type);

  return (
    <label
      style={{
        display: 'flex',
        flexDirection: 'column',
        gap: 6,
        opacity: disabled ? 0.5 : 1,
        ...style,
      }}
      {...rest}
    >
      {label && (
        <span style={{
          fontFamily: 'var(--font-text)', fontSize: 'var(--size-footnote)',
          fontWeight: 'var(--weight-medium)', color: 'var(--text-secondary)',
          paddingLeft: 2,
        }}>{label}</span>
      )}
      <span style={{
        display: 'flex', alignItems: 'center', gap: 'var(--space-2)',
        minHeight: 'var(--control-h-lg)',
        padding: '0 var(--space-3)',
        background: 'var(--surface-base)',
        borderRadius: 'var(--radius-sm)',
        boxShadow: 'inset 0 0 0 1px var(--separator)',
      }}>
        {leadingIcon && <Icon name={leadingIcon} size={20} color="var(--icon-secondary)" />}
        <input
          type={inputType}
          value={value}
          defaultValue={defaultValue}
          onChange={onChange}
          placeholder={placeholder}
          disabled={disabled}
          readOnly={readOnly}
          style={{
            flex: 1, minWidth: 0,
            border: 'none', outline: 'none', background: 'transparent',
            color: 'var(--text-primary)',
            fontFamily: mono ? 'var(--font-mono)' : 'var(--font-text)',
            fontSize: 'var(--size-body)',
            letterSpacing: mono && isSecure ? '0.12em' : 'normal',
            fontVariantNumeric: mono ? 'tabular-nums' : 'normal',
            ...inputStyle,
          }}
        />
        {revealable && (
          <button
            type="button"
            aria-label={revealed ? 'Hide' : 'Reveal'}
            onClick={() => setRevealed((r) => !r)}
            style={{
              display: 'inline-flex', border: 'none', background: 'none',
              padding: 4, cursor: 'pointer', WebkitTapHighlightColor: 'transparent',
            }}
          >
            <Icon name={revealed ? 'hide' : 'view'} size={20} color="var(--icon-secondary)" />
          </button>
        )}
        {trailing}
      </span>
    </label>
  );
}
