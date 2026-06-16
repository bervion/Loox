Recolorable Polaris icon — use anywhere the app needs a glyph; it behaves like an SF Symbols family driven by one color token.

```jsx
<Icon name="lock" size={22} color="var(--icon-secondary)" />
<Icon name="search" />                 {/* inherits currentColor */}
<Icon name="LockMajor" />              {/* raw Polaris stem also works */}
```

Pass a semantic name from `ICON_MAP` (login, card, copy, view, watchtower, chevron.right, …) or any Polaris file stem. `color` accepts any token; default `currentColor` inherits the parent's text color. Set `decorative={false}` + `label` for standalone meaningful icons.
