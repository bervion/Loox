import * as React from 'react';

export interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  /** Counter value. Ignored when `dot` is true. */
  count?: number;
  /** Render a small alert dot instead of a counter. */
  dot?: boolean;
  /** Color role. Default 'destructive'. */
  tone?: 'destructive' | 'accent' | 'neutral' | 'success' | 'warning';
  /** Clamp counter; shows `${max}+`. Default 99. */
  max?: number;
}

/** Alert dot or compact counter for meaningful alerts. Does not resize its host. */
export declare function Badge(props: BadgeProps): React.JSX.Element;
