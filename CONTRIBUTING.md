# Contributing to Vaultify

## Branch model

Vaultify uses a two-tier integration model:

- **`develop`** is the autonomous integration branch. Ticket branches merge
  here behind required checks with no human review step.
- **`main`** is the release branch and is owner territory. It only moves
  through a single reviewed integration pull request.

## Ticket branches into develop

Every change starts from a board ticket and flows through a ticket branch:

1. Branch from the current `develop` head. Branch names must match
   `fix/<slug>`, `feat/<slug>`, `quality/<slug>`, or `agent/<slug>` —
   lowercase, digits and hyphens only.
2. Keep the diff scoped to one ticket. The commit message carries the ticket
   subject and identifier so every commit traces back to the board.
3. Open a pull request with `develop` as the base. The PR body references the
   originating ticket.
4. Wait for the required checks: Trusted PR policy, Quality contract, Unit
   tests, Snapshot tests, and the Critical UI journey — all running on the
   self-hosted `vaultify-ci` runner.
5. Merge (squash) only when every check is green. Branches touching trusted
   paths — workflows, quality policy inputs — additionally require the
   owner's exact-head approval and cannot self-merge.

## Develop reaches main once a day

At 07:00 each morning an integration pull request from `develop` into `main`
is opened or refreshed automatically. It carries a work report: the commit
list, diffstat, and pointers to the tickets and findings behind each change.
The owner reviews that single PR as the day's briefing and merges it; nothing
else ever pushes to `main`.

## Quality artifacts

Analysis deliverables (coverage maps, audits, gap analyses) are not code and
do not go through pull requests. They are published append-only into
`quality/` in the team workspace, one uniquely named artifact per ticket,
each carrying its originating task in the publish record.
