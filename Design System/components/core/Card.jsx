import React from 'react';

/* Card — standard surface container. Use for grouping or affordance,
   not as decoration. Grouped list rows live inside variant="grouped". */
export function Card({
  children,
  variant = 'base',     // base | elevated | grouped | floating
  radius = 'var(--radius-lg)',
  padding = 'var(--space-4)',
  style,
  ...rest
}) {
  const surfaces = {
    base:     { background: 'var(--surface-base)',     boxShadow: 'var(--hairline)' },
    elevated: { background: 'var(--surface-elevated)', boxShadow: 'var(--elevation-2)' },
    grouped:  { background: 'var(--surface-base)',     boxShadow: 'var(--hairline)', padding: 0 },
    floating: { background: 'var(--surface-floating)', boxShadow: 'var(--elevation-3)',
                backdropFilter: 'blur(20px) saturate(1.6)', WebkitBackdropFilter: 'blur(20px) saturate(1.6)' },
  };
  const v = surfaces[variant] || surfaces.base;
  return (
    <div
      style={{
        borderRadius: radius,
        padding: variant === 'grouped' ? 0 : padding,
        overflow: variant === 'grouped' ? 'hidden' : 'visible',
        ...v,
        ...style,
      }}
      {...rest}
    >
      {children}
    </div>
  );
}
