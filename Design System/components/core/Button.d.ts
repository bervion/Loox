import * as React from 'react';
import type { IconName } from './Icon';

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  /**
   * @startingPoint section="Buttons" subtitle="Primary, secondary, ghost & destructive actions" viewport="700x180"
   */
  children?: React.ReactNode;
  /** Visual emphasis. Default 'primary'. */
  variant?: 'primary' | 'secondary' | 'ghost' | 'destructive';
  /** Control height. Default 'md'. */
  size?: 'sm' | 'md' | 'lg';
  /** Stretch to container width. */
  fullWidth?: boolean;
  /** Optional leading icon (semantic name). */
  leadingIcon?: IconName;
  /** Optional trailing icon (semantic name). */
  trailingIcon?: IconName;
  disabled?: boolean;
}

/** Vaultify button. Accent-filled primary, bordered secondary, tinted-text ghost, soft destructive. */
export declare function Button(props: ButtonProps): React.JSX.Element;
