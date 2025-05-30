# Hybrid Cache Design

This document provides an overview of the hybrid cache architecture used in CVA6.
It complements `hybrid_cache_validation.md` with a concise design reference.

## Modes
- **Write Through (WT)** – standard set associative cache.
- **WT_HYB** – dynamically switches between set associative and fully associative
  organisations depending on the current privilege level.
- **WT_HYB_FORCE_SET_ASS** – hybrid cache forced into set associative mode.
- **WT_HYB_FORCE_FULL_ASS** – hybrid cache forced into fully associative mode.

## Replacement Policies
The cache supports retaining or flushing data when changing modes. Additional
algorithms such as round-robin or pseudo random victim selection are available.

### Hashed Index Calculation
In fully associative mode, a small lookup table accelerates tag matching. Each
tag is hashed to select an entry in this table:

```
index = (tag ^ HASH_SEED ^ (tag >> log2(WAYS))) % WAYS
```

The `HASH_SEED` parameter randomises the distribution of tags across the table,
reducing systematic collisions. If a hit is not found at the hashed index, the
lookup logic falls back to a full search over all ways.

### Entry Reorganisation on Mode Switch
When the cache switches between set associative and fully associative modes with
`REPL_POLICY_RETAIN`, valid entries are preserved. Switching to fully
associative mode copies the tags of each active way into the lookup table using
the hashed index calculation. Switching back rebuilds the set associative view
by writing each cached line to its physical set. Only the minimal number of
lines are moved; unused entries remain invalid.

### Set Allocation in Fully Associative Mode
Fully associative operation does not automatically use all cache sets.  Instead,
two configuration parameters select a contiguous subset of sets:

- `FA_SET_BASE` – index of the first set reserved for fully-associative access.
- `FA_SET_COUNT` – number of sets starting from `FA_SET_BASE`.

Only these sets participate while the cache is in fully associative mode.  The
contents of all other sets remain untouched until set associative operation is
restored.

## Usage
Set the `DCacheType` parameter in the configuration package to one of the modes
above. The analysis utilities found in this repository can be used to benchmark
different configurations and visualise their behaviour.
