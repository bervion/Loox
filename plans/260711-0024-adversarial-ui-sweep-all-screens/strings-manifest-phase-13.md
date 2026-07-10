# Strings manifest — Phase 13 (Main shell + Mac surfaces + App root)

No new or changed catalog strings. Every user-facing string already reviewed had EN+VI
present (verified directly against `Vaultify/Localizable.xcstrings`: Home, Items,
Watchtower, Search, Profile, Vault, Loox, All Items, Favorites, Archive, Recently
Deleted, New Item, Spaces, Tags, Create New Space, Edit, No items, Items you add will
appear here., Select an item to view its details., All Spaces, No results, Clear, Keep
at least one identity, This is your only identity. Add another before removing this
one., Couldn't accept the invitation, Invitation accepted, Unlock your vault and open
"Shared with Me" on Home to finish setting up., Unfavorite, Favorite, Trash, OK, Search
vault, More).

The one copy fix in this phase (`MacHeaderBar.swift` — removed the em-dash
title/subtitle join in `MacSearchSuggestionsPanel`) touched a `Text(verbatim:)` built
from dynamic item data (`item.title` / `item.subtitle`), not a catalog key — no manifest
entry needed.

| key | EN | VI | context |
|---|---|---|---|
| — | — | — | no additions |
