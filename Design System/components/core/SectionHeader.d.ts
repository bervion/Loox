import * as React from 'react';
import type { IconName } from './Icon';

export interface SectionHeaderProps extends React.HTMLAttributes<HTMLDivElement> {
  /** Section label text. */
  title: string;
  /** Optional trailing action label (e.g. "Edit", "See all"). */
  action?: React.ReactNode;
  /** Trailing action click handler. */
  onAction?: () => void;
  /** Optional icon after the action label. */
  actionIcon?: IconName;
  /** Uppercase the label (iOS grouped style). Default true. */
  uppercase?: boolean;
}

/** Quiet grouped-list section header with an optional trailing accent action. */
export declare function SectionHeader(props: SectionHeaderProps): React.JSX.Element;
