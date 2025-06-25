# Critical Cache Performance Issue Fix

## Root Cause Identified

🚨 **CRITICAL ISSUE:** Infinite request replay loops in fully associative cache

### Problem Flow:
1. **Fully associative cache** (128 ways) causes more frequent `wr_cl_vld_i` activity
2. **Arbiter denies `rd_ack_o`** when `wr_cl_vld_i` is high (`gnt_i = ~wr_cl_vld_i`)
3. **Controller enters `REPLAY_REQ` state** when `!rd_ack_q` (line 165 in wt_cln_dcache_ctrl.sv)
4. **Continuous replay cycles** create 5.2x more `req_i` activity and 465x more cycles

### Key Evidence:
- `wr_cl_vld_o = load_ack | (|wr_cl_we_o)` (wt_cln_dcache_missunit.sv:428)
- In 128-way FA cache, `wr_cl_we_o` has 128 bits vs 32 bits in normal cache
- More frequent cache line writes block read requests

## Fix Strategy

### Option 1: Optimize Arbiter Priority (Recommended)
Modify the arbiter to give read requests higher priority or allow concurrent operation:

```systemverilog
// In wt_cln_dcache_mem.sv line 181
// OLD: .gnt_i  (~wr_cl_vld_i),
// NEW: Allow reads unless there's a true write conflict
.gnt_i  (~wr_cl_vld_i | read_write_no_conflict),
```

### Option 2: Reduce Cache Line Write Frequency
Optimize when `wr_cl_we_o` is active to reduce blocking:

```systemverilog
// In wt_cln_dcache_missunit.sv line 428
// OLD: assign wr_cl_vld_o = load_ack | (|wr_cl_we_o);
// NEW: More selective activation
assign wr_cl_vld_o = load_ack | (wr_cl_active_when_needed);
```

### Option 3: Optimize REPLAY Logic
Reduce replay frequency for non-conflicting requests:

```systemverilog
// In wt_cln_dcache_ctrl.sv line 165
// OLD: if (wr_cl_vld_i || !rd_ack_q) begin state_d = REPLAY_REQ;
// NEW: More selective replay conditions
if ((wr_cl_vld_i && address_conflict) || !rd_ack_q) begin state_d = REPLAY_REQ;
```

## Implementation Plan

1. **Start with Option 1** - least risky, most targeted
2. **Test with intermediate associativity** to validate fix
3. **Measure cycle count improvement**
4. **Apply additional optimizations if needed**

## Expected Results
- Reduce req_i activity from 5.2x to ~1.1x
- Reduce cycle count from 465x to <10x (target: normal + reasonable FA overhead)
- Test should PASS instead of timeout

This fix directly addresses the 500x performance issue root cause.