# Legacy Entity Link Fixtures

These golden fixtures capture real serialized representations written by earlier engine commits, used to verify backward compatibility and deterministic migration of legacy entity link sets.

## Origin and Generation Details

- **Legacy Fixtures Commit:** `0eaab8b4a8a12fa42f5898e4bdb70d5fa7ca5636` (Pass 4.1)
  - `item_only.json`: Link X added at HLC timestamp `pt: 30`, tombstones empty.
  - `tombstone_only.json`: Link X deleted at HLC timestamp `pt: 20`, items empty.
  - `item30_tomb20.json`: Link X added at `pt: 30`, tombstone at `pt: 20`. Under legacy Add-Wins, link X is active.
  - `item20_tomb20.json`: Link X added at `pt: 20`, tombstone at `pt: 20`. Under legacy Add-Wins tie-breaking, link X is active.
  - `item10_tomb20.json`: Link X added at `pt: 10`, tombstone at `pt: 20`. Tombstone is newer; link X is removed.
  - `mixed.json`: Multiple entity link IDs exercising item-only, tombstone-only, tie, and newer/older combinations.

- **Native Baseline Fixture Commit:** `9252069b99e278c3d5354d5cad2aab29ff8bfe1e`
  - `native_starting_head.json`: Serialized with generation-aware `EntityLinkCrdtSet` containing an active link and a targeted tombstone without legacy migration flags.

## Generation Steps

1. In a scratch directory, checked out `vtt-engine-core` at `0eaab8b4a8a12fa42f5898e4bdb70d5fa7ca5636`.
2. Invoked Dart generation logic directly using `0eaab8b`'s `RoomNodeState`, `CrdtOrSet<RoomEntityLink>`, `RoomEntityLink`, and `HybridLogicalClock` implementations.
3. Serialized via `RoomNodeState.toMap()`.
4. Generated `native_starting_head.json` at `9252069b99e278c3d5354d5cad2aab29ff8bfe1e` via its native `EntityLinkCrdtSet` and `RoomNodeState.toMap()`.
