import * as React from 'react';

export interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
  children?: React.ReactNode;
  /** base (hairline), elevated (shadow), grouped (zero-pad row container), floating (glass). */
  variant?: 'base' | 'elevated' | 'grouped' | 'floating';
  /** Corner radius. Default var(--radius-lg) = 20px. */
  radius?: string;
  /** Inner padding (ignored for grouped). Default var(--space-4). */
  padding?: string;
}

/** Surface container. Use for grouping/affordance, never as decoration. */
export declare function Card(props: CardProps): React.JSX.Element;
