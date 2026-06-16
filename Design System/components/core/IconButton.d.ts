import * as React from 'react';
import type { IconName } from './Icon';

export interface IconButtonProps extends Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'aria-label'> {
  /** Icon to render. */
  name: IconName;
  /** REQUIRED accessible label — the control is icon-only. */
  label: string;
  /** Hit box. Default 'md' (44pt). Never below 44pt for primary controls. */
  size?: 'sm' | 'md' | 'lg';
  /** plain (transparent), filled (accent), or tinted (neutral pressed fill). */
  variant?: 'plain' | 'filled' | 'tinted';
  /** Glyph color for plain/tinted variants. Default var(--icon-primary). */
  color?: string;
  disabled?: boolean;
}

/** Icon-only button with a mandatory accessibility label and 44pt minimum hit area. */
export declare function IconButton(props: IconButtonProps): React.JSX.Element;
