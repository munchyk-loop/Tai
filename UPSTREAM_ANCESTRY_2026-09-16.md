# Tai / Trio ancestry reconciliation — 2026-09-16

Bounded reconciliation after Tai PRs #16 and #17; not a new functional sync.
The historical audit in `UPSTREAM_SYNC_BASELINE.md` remains unchanged.

## Boundary and proof

- Integrated Tai dev: `2b1e57ec681e80c025150d53212a81a4211d4dc0`.
- Previous common upstream ancestor: `556fba7b1c55c23d7fbe352eb665fbd1d01803cd`.
- Official upstream boundary: `7983946726b60dc0c3f2b9608f2596cc2b45910e`.
- Reconciliation merge: `3e0455fc36422c8544b69955f7f618b51cc52d67`.
- Parents in order: integrated Tai dev, official upstream boundary.
- Merge tree: `9b01985878383c467cf958d7aea20379e9ff1f7b`, identical to integrated Tai dev.

## Accounted first-parent interval

Eleven functional PR merges and eleven CI version bumps lie between the previous
ancestor and boundary. #16 imported ten functional merges with `cherry-pick -m 1 -x`;
#17 supplied the concentration-aware Tai adaptation of upstream #1300.
Those integrations alone did not retain the original upstream ancestry.

| Upstream PR | Upstream merge | Tai integration |
| --- | --- | --- |
| #1493 gesture legend | `c6d87c5d106a` | `cd4724f26c66` / #16 |
| #1300 finalized pump events | `b3486749e0e6` | `e2dfb07348ca` plus concentration/test/UI follow-ups / #17 |
| #1473 contact bobble | `deaee3c62198` | `81e2f3e15be3` / #16 |
| #1492 chart label anchoring | `e6c2dacdc609` | `d3bcd5f65954` / #16 |
| #1367 DI hygiene | `285ca8321951` | `cecd322f60f8` / #16 |
| #1512 display-only glucose | `b74f11a01e8b` | `6c2a43055ad1` / #16 |
| #1510 alarm gating/volume | `15a0a5177e38` | `de3a6979afd8` / #16 |
| #1455 chart readout | `0fe413206208` | `98d981168998` / #16 |
| #1517 telemetry reliability | `c2c1902a22cd` | `3f5f4a06bbbf` / #16 |
| #1465 submodule updates | `0de3c69946a1` | `8276513f8b89` / #16 |
| #1519 telemetry launch order | `2865101e3527` | `5ae6a79bcb8c`, `ca6a22345d66` / #16 |

All fifteen gitlinks changed in this interval match the official boundary in Tai dev.
The eleven upstream CI version bumps to `.97`–`.107` are deliberately excluded:
Tai retains its own version policy and `.96`.

## Resolution decisions

A normal three-way `git merge --no-ff --no-commit` was performed, not the `ours`
strategy. The fifteen conflicted paths retain the already integrated Tai versions:
concentration normalization, expanded/hermetic tests, Tai chart/readout layout and
symbols, gesture/localization copy, and Xcode wiring. The upstream treatment-history
view remains deleted in favor of Tai's adapted history. Contact help and telemetry
signature conflicts are formatting differences.

The only two non-conflicted staged deltas were rejected deliberately: upstream's
CI version bump in `Config.xcconfig` and a duplicate background telemetry call in
`FetchGlucoseManager.swift`. The merge introduces no application, configuration,
resource, or gitlink changes. A follow-up commit adds only this record.

This records accepted integrations and deliberate exclusions at a pinned boundary,
not byte-for-byte parity with upstream or an audit of later upstream commits.

## Verification and promotion

Verified locally: no unresolved index entries; merge tree equals its Tai parent;
official boundary is an ancestor; merge-base with that boundary equals the boundary.
No new runtime tests were run: the application tree is unchanged.

Promote into Tai `dev` using **Create a merge commit** (or a true fast-forward).
Do not squash or rebase: that discards the upstream-parent relationship.
After promotion verify:

```sh
git fetch origin
git merge-base --is-ancestor 7983946726b60dc0c3f2b9608f2596cc2b45910e origin/dev
git merge-base origin/dev 7983946726b60dc0c3f2b9608f2596cc2b45910e
```

The first ancestry check must exit zero; the second must print the boundary SHA.
Future routine syncs should merge the next official upstream boundary normally,
following `UPSTREAM_SYNC_BASELINE.md`, and audit only the new upstream interval.
