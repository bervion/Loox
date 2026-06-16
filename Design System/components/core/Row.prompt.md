Grouped-list row — the workhorse for vault items, settings, and detail fields.

```jsx
<Card variant="grouped">
  <Row leading={<IconTile name="login" tint="var(--accent)" />}
       title="GitHub" subtitle="octocat@github.com" chevron onClick={open} />
  <Row leading={<IconTile name="card" tint="var(--success)" />}
       title="Visa" value="•••• 4242" chevron />
  <Row title="Face ID unlock" trailing={<Switch checked={on} onChange={setOn} />} divider={false} />
</Card>
```

Compose inside `<Card variant="grouped">`. `leading` is usually an `<IconTile/>`; `value` is right-aligned secondary text; `trailing` takes a Switch/Badge/IconButton; `chevron` adds a disclosure arrow. Turn `divider={false}` on the last row. `tone="destructive"` for delete/sign-out rows.
