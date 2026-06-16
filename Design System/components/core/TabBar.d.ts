import * as React from 'react';
import type { IconName } from './Icon';

export interface TabItem {
  /** Stable id (also the selected value). */
  id: string;
  /** Inactive icon (semantic name). */
  icon: IconName;
  /** Optional filled icon used when active. */
  iconFill?: IconName;
  /** REQUIRED accessible label — never rendered visually. */
  label: string;
  /** Compact counter badge. */
  badge?: number;
  /** Render a dot badge instead of a counter. */
  badgeDot?: boolean;
}

export interface TabBarProps extends React.HTMLAttributes<HTMLElement> {
  /**
   * Four primary tabs (Home, Items, Watchtower, Search).
   * @startingPoint section="Navigation" subtitle="Floating icon-only tab bar with sliding pill" viewport="430x120"
   */
  tabs: TabItem[];
  /** Selected tab id. */
  value: string;
  /** Selection handler — fire light haptics here on device. */
  onChange?: (id: string) => void;
  /** Use the translucent glass control layer (else solid fallback). Default false. */
  glass?: boolean;
}

/** Custom icon-only floating tab bar: no labels, sliding accent pill, meaningful badges only. */
export declare function TabBar(props: TabBarProps): React.JSX.Element;
