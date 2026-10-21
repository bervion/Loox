# Wiki source

These pages are the source of the [GitHub Wiki](https://github.com/bervion/Loox/wiki). Edit them here so changes go through review, then sync them to the wiki. Links use the wiki's `[[Page Name]]` syntax, so they only resolve on the wiki itself.

GitHub only serves a wiki for a public repository on GitHub Free. To publish, from the repository root:

```bash
git clone git@github.com:bervion/Loox.wiki.git ../Loox.wiki
rsync -a --delete --exclude .git --exclude README.md docs/wiki/ ../Loox.wiki/
git -C ../Loox.wiki add -A
git -C ../Loox.wiki commit -m "docs: sync wiki from docs/wiki"
git -C ../Loox.wiki push
```

`--delete` replaces whatever is on the wiki, including a placeholder first page created on the web. This README is not published.
