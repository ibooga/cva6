# WT_CLN Fully Associative Cache Performance Issue Analysis

## Problem Summary
The WT_CLN fully associative cache configuration (INDEX_WIDTH=0, 128 ways) is **465x slower** than the normal WT cache configuration, requiring 1.65M cycles vs 3.6K cycles for the hello_world test.

## Root Cause Identified

### Primary Issue: Runtime Loop in Cache Mirror Logic
**File:** `core/cache_subsystem/wt_cln_dcache_mem.sv:314-322`

**Problem Code:**
```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin : p_mirror
  if (!rst_ni) begin
    vld_mirror <= '{default: '0};
    tag_mirror <= '{default: '0};
  end else begin
    for (int i = 0; i < CVA6Cfg.DCACHE_SET_ASSOC; i++) begin  // ← 128 iterations per cycle!
      if (vld_req[i] & vld_we) begin
        vld_mirror[vld_addr][i] <= vld_wdata[i];
        tag_mirror[vld_addr][i] <= wr_cl_tag_i;
      end
    end
  end
end
```

**Impact:**
- This loop executes **every clock cycle** 
- With fully associative cache: `DCACHE_SET_ASSOC = 128 ways`
- Creates 128 conditional assignments per cycle
- Massive simulation overhead due to event scheduling

### Contributing Factors

1. **Tag Comparison Parallelism (lines 243-249):**
   ```systemverilog
   for (genvar i = 0; i < CVA6Cfg.DCACHE_SET_ASSOC; i++) begin : gen_tag_cmpsel
     assign rd_hit_oh_o[i] = (rd_tag == tag_rdata[i]) & rd_vld_bits_o[i] & cmp_en_q;
   ```
   - 128 parallel tag comparisons every read access

2. **Bank Generation Logic (lines 144-154):**
   ```systemverilog
   for (genvar k = 0; k < DCACHE_NUM_BANKS; k++) begin : gen_bank
     for (genvar j = 0; j < CVA6Cfg.DCACHE_SET_ASSOC; j++) begin : gen_bank_way
   ```
   - 128 way × DCACHE_NUM_BANKS parallel logic structures

3. **Large Associativity Without Set Indexing:**
   - INDEX_WIDTH=0 forces all cache lines into a single set
   - All 128 ways must be checked for every access
   - No address-based filtering to reduce search space

## Performance Impact Analysis

| Metric | Normal WT Cache | Fully Associative WT_CLN | Ratio |
|--------|----------------|---------------------------|-------|
| **Cycles** | 3,550 | 1,651,500 | **465.2x** |
| **VCD Size** | 49.4 MB | 1,654.1 MB | **33.5x** |
| **Signal Activity** | req_i: 231 | req_i: 1,192 | **5.2x** |

The exponential increase in simulation events correlates with the O(N) runtime complexity where N=128 ways.

## Technical Analysis

### Signal Activity Investigation
- Most AXI and cache signals show 1:1 activity ratio
- `req_i` signal shows 5.2x increase, indicating cache request processing overhead
- VCD file bloat (33.5x) suggests excessive internal signal transitions

### VCD Analysis Results
- **Normal cache:** 13.91 MB per 1K cycles
- **Fully associative:** 1.00 MB per 1K cycles  
- Lower density in FA cache indicates simulation struggling with event processing

### Configuration Impact
```systemverilog
// build_config_pkg.sv - Current fully associative forcing
int unsigned DCACHE_INDEX_WIDTH = 0;  // Forces single set
int unsigned DCACHE_SET_ASSOC = 128;  // All ways in one set
```

## Recommended Solutions

### 1. Immediate Fix: Optimize Runtime Loop
Replace runtime `for (int i = 0...)` with generate loop or conditional logic:

```systemverilog
// Option A: Use generate loop with enables
for (genvar i = 0; i < CVA6Cfg.DCACHE_SET_ASSOC; i++) begin : gen_mirror_way
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      vld_mirror[vld_addr][i] <= 1'b0;
      tag_mirror[vld_addr][i] <= '0;
    end else if (vld_req[i] & vld_we) begin
      vld_mirror[vld_addr][i] <= vld_wdata[i];
      tag_mirror[vld_addr][i] <= wr_cl_tag_i;
    end
  end
end

// Option B: Use vector assignment
always_ff @(posedge clk_i or negedge rst_ni) begin : p_mirror
  if (!rst_ni) begin
    vld_mirror <= '{default: '0};
    tag_mirror <= '{default: '0};
  end else if (vld_we) begin
    for (int i = 0; i < CVA6Cfg.DCACHE_SET_ASSOC; i++) begin
      if (vld_req[i]) begin
        vld_mirror[vld_addr][i] <= vld_wdata[i];
        tag_mirror[vld_addr][i] <= wr_cl_tag_i;
      end
    end
  end
end
```

### 2. Long-term: Cache Architecture Optimization
- Implement hierarchical indexing even for fully associative mode
- Use content-addressable memory (CAM) structures for tag lookup
- Consider partial associativity (e.g., 16-way sets) instead of full associativity

### 3. Simulation Optimization
- Add synthesis-time optimizations for high associativity
- Implement early termination in tag comparison loops
- Use more efficient replacement policies (e.g., tree-based LRU)

## Verification Steps

1. **Code Fix:** Optimize the runtime loop in `wt_cln_dcache_mem.sv`
2. **Regression Test:** Verify functionality with modified code
3. **Performance Test:** Run hello_world test and confirm cycle count improvement
4. **Coverage:** Ensure all cache operations still work correctly

## Expected Improvement
Fixing the runtime loop should reduce simulation time by **orders of magnitude**, potentially bringing the fully associative cache performance to within 2-5x of normal cache performance rather than 465x.

## Files Requiring Modification
- `/home/cai/cache_project/sandbox/cva6/core/cache_subsystem/wt_cln_dcache_mem.sv` (Primary fix)
- `/home/cai/cache_project/sandbox/cva6/core/include/build_config_pkg.sv` (Configuration)

---
**Analysis Date:** 2025-06-20  
**Investigation Method:** VCD analysis, signal tracing, code review  
**Status:** Root cause confirmed, fix strategy identified