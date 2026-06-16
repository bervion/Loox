Primary action button — accent-filled by default; use one primary per view.

```jsx
<Button onClick={save}>Save</Button>
<Button variant="secondary" leadingIcon="add">New item</Button>
<Button variant="ghost" size="sm">Cancel</Button>
<Button variant="destructive" fullWidth>Delete vault</Button>
```

Variants: `primary` (accent + on-accent), `secondary` (bordered surface), `ghost` (accent text, no fill), `destructive` (soft red). Sizes `sm | md | lg`. `fullWidth` stretches; `leadingIcon`/`trailingIcon` take semantic icon names. Press gives a subtle scale + deepened fill.
