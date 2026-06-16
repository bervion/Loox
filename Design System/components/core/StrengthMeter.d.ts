import * as React from 'react';

export interface StrengthMeterProps {
  /** 0 (empty) … 4 (strong). */
  score?: 0 | 1 | 2 | 3 | 4;
  /** Show the textual level under the bar. Default true. */
  showLabel?: boolean;
  /** Override the auto label (e.g. "Reused on 3 sites"). */
  label?: string;
  style?: React.CSSProperties;
}

/** Four-segment password / vault-health strength indicator, color-coded by score. */
export declare function StrengthMeter(props: StrengthMeterProps): React.JSX.Element;
