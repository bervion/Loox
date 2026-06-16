import * as React from 'react';
import type { IconName } from './Icon';

export interface IconTileProps extends React.HTMLAttributes<HTMLSpanElement> {
  /** Icon to render inside the tile. */
  name: IconName;
  /** Tile fill (solid) or glyph color (soft). Default var(--accent). */
  tint?: string;
  /** Glyph color on a solid tile. Default var(--on-accent). */
  onTint?: string;
  /** Tile box size. Default var(--icon-tile) = 32px. */
  size?: number | string;
  /** Override glyph size (defaults to ~60% of tile). */
  iconSize?: number | string;
  /** Corner radius. Default var(--radius-sm). */
  radius?: string;
  /** soft = 16% tinted background with colored glyph (calmer). */
  soft?: boolean;
}

/** Rounded tinted tile holding one icon — the leading element for rows & item lists. */
export declare function IconTile(props: IconTileProps): React.JSX.Element;
