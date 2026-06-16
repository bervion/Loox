import * as React from 'react';

export type IconName =
  | 'home' | 'home.fill' | 'items' | 'items.fill' | 'watchtower' | 'search'
  | 'categories' | 'login' | 'password' | 'card' | 'identity' | 'note'
  | 'email' | 'website' | 'bank' | 'wifi' | 'copy' | 'view' | 'hide' | 'edit'
  | 'delete' | 'add' | 'add.circle' | 'refresh' | 'filter' | 'settings'
  | 'profile' | 'exit' | 'more' | 'share' | 'external'
  | 'chevron.right' | 'chevron.left' | 'chevron.down' | 'chevron.up'
  | 'lock' | 'unlock' | 'success' | 'alert' | 'warning' | 'info'
  | 'favorite' | 'clock'
  | (string & {});

export interface IconProps extends React.HTMLAttributes<HTMLSpanElement> {
  /** Semantic icon name (see ICON_MAP) or a raw Polaris file stem. */
  name: IconName;
  /** px number or any CSS length/token. Default var(--icon-inline) = 20px. */
  size?: number | string;
  /** Any color/token. Default currentColor — inherits parent text color. */
  color?: string;
  /** When false the icon is exposed to AT with `label`. Default true (hidden). */
  decorative?: boolean;
  /** Accessible label, used when decorative is false. */
  label?: string;
}

/**
 * Vaultify icon — a Polaris glyph recolored via CSS mask so a single
 * semantic color token drives it, like an SF Symbols family.
 */
export declare function Icon(props: IconProps): React.JSX.Element;
export declare const ICON_MAP: Record<string, string>;
export declare const POLARIS_BASE: string;
export declare function iconUrl(name: string): string;
export declare function resolveIcon(name: string): string;
