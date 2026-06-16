Floating icon-only bottom navigation — the app's primary tab bar. No visible labels; a sliding accent pill marks the active tab.

```jsx
const tabs = [
  { id:'home', icon:'home', iconFill:'home.fill', label:'Home' },
  { id:'items', icon:'items', iconFill:'items.fill', label:'Items' },
  { id:'watchtower', icon:'watchtower', label:'Watchtower', badge:3 },
  { id:'search', icon:'search', label:'Search' },
];
<TabBar tabs={tabs} value={tab} onChange={setTab} />
```

Mount it as a fixed overlay near the bottom safe area (inset ~22px, ~12px above safe area) — not inside feature screens. Reserve `var(--tabbar-bottom-pad)` of scroll padding so content clears it. Pass `glass` for the translucent control layer; default is the solid Threads-style fallback. Badges should be meaningful only (`badge` counter or `badgeDot`).
