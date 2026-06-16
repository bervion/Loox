import * as React from 'react';
import type { IconName } from './Icon';

export interface FieldProps {
  /** Field label shown above the input. */
  label?: string;
  value?: string;
  defaultValue?: string;
  onChange?: (e: React.ChangeEvent<HTMLInputElement>) => void;
  placeholder?: string;
  type?: string;
  /** Leading icon inside the field. */
  leadingIcon?: IconName;
  /** Mask the value (password). */
  secure?: boolean;
  /** Show a reveal/hide eye toggle (pairs with secure). */
  revealable?: boolean;
  /** Render value in the monospace face (passwords, codes). */
  mono?: boolean;
  /** Custom trailing slot, e.g. a copy IconButton. */
  trailing?: React.ReactNode;
  disabled?: boolean;
  readOnly?: boolean;
  style?: React.CSSProperties;
  inputStyle?: React.CSSProperties;
}

/** Labeled text input (iOS grouped style) with secure mode, reveal, mono & trailing slot. */
export declare function Field(props: FieldProps): React.JSX.Element;
