import * as React from 'react';

export interface SegmentOption { value: string; label: string; }

export interface SegmentedControlProps {
  /** Options as strings or {value,label} objects. */
  options: Array<string | SegmentOption>;
  /** Selected value. */
  value: string;
  /** Selection change handler. */
  onChange?: (value: string) => void;
  style?: React.CSSProperties;
}

/** iOS segmented control with a sliding selected pill. Use for 2–4 short options. */
export declare function SegmentedControl(props: SegmentedControlProps): React.JSX.Element;
