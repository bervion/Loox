import * as React from 'react';

export interface RowProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Leading element, usually an <IconTile/> or <Avatar/>. */
  leading?: React.ReactNode;
  /** Primary label. */
  title: React.ReactNode;
  /** Optional supporting label below the title. */
  subtitle?: React.ReactNode;
  /** Optional trailing value text (right-aligned, secondary color). */
  value?: React.ReactNode;
  /** Custom trailing control (Switch, Badge, IconButton…). */
  trailing?: React.ReactNode;
  /** Show a trailing disclosure chevron. */
  chevron?: boolean;
  /** Color role for the title. Default 'default'. */
  tone?: 'default' | 'accent' | 'destructive';
  /** Inset hairline at the bottom; turn off for the last row in a group. */
  divider?: boolean;
  onClick?: () => void;
}

/** Standard grouped-list row: leading tile, title/subtitle, trailing value or control. */
export declare function Row(props: RowProps): React.JSX.Element;
