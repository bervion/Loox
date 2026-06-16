import * as React from 'react';

export interface SwitchProps {
  /** On/off state. */
  checked?: boolean;
  /** Called with the next value when toggled. */
  onChange?: (next: boolean) => void;
  disabled?: boolean;
  /** Accessible label (the control has no visible text). */
  label?: string;
  style?: React.CSSProperties;
}

/** iOS-style toggle. Accent fill when on; respects reduced motion via tokens. */
export declare function Switch(props: SwitchProps): React.JSX.Element;
