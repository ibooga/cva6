# CVA6 Fully Associative Cache Development Notes

## Quick Commands

### Running Tests with Increased Timeout
For fully associative cache tests that require longer simulation time:

**Recommended Method - Comprehensive Test Runner:**
```bash
# Run with all timeout issues handled automatically
./run_fa_test.sh hello_world cv32a6_imac_sv32 3000 5000000

# Arguments: test_name target timeout_seconds max_cycles
./run_fa_test.sh <test> <target> <timeout> <max_cycles>
```

**Manual Methods:**
```bash
# Standard hello_world test with extended timeout
python3 cva6.py --c_tests ../tests/custom/hello_world/hello_world.c --iss_timeout 2000 --target cv32a6_imac_sv32

# Direct make with cycle limit
make veri-testharness target=cv32a6_imac_sv32 elf=<test>.o issrun_opts="+max-cycles=5000000" log=<output>.log
```

### Manual Test Recovery
If a test times out but completed successfully:
```bash
# Check for simulation completion in .iss file
grep "SUCCESS" out_*/veri-testharness_sim/*.iss

# Manual file movement if needed
mv verilator.vcd out_*/veri-testharness_sim/<test_name>.cv32a6_imac_sv32.vcd
cp trace_rvfi_hart_00.dasm out_*/veri-testharness_sim/<test_name>.cv32a6_imac_sv32.log
```

## Configuration Changes

### Timeout Settings
- **Default timeout increased**: 500s → 1500s in cva6.py for fully associative cache
- **Manual override**: Use `--iss_timeout <seconds>` for specific tests
- **Expected times**: Fully associative cache tests can take 8-10 minutes due to complex logic

### Cache Configuration Status
- **INDEX_WIDTH = 0**: Forced in build_config_pkg.sv for true fully associative cache
- **Address validation**: Implemented in wt_cln_dcache_missunit.sv (256MB range)
- **Safe indexing**: Functions added to wt_cln_cache_pkg.sv for INDEX_WIDTH=0

## Test Infrastructure

### Performance Expectations
- **Normal cache tests**: ~1000 cycles, <30s runtime
- **Fully associative tests**: ~1.6M cycles, 8-10 minutes runtime
- **VCD file size**: 1.7GB for hello_world test (vs ~10MB normal)

### Timeout and Cycle Limits
The simulation has multiple timeout mechanisms:
1. **Python timeout**: Default 1500s (configurable via --iss_timeout)
2. **Simulation cycle limit**: ~2M cycles (built into testbench)
3. **DTM timeout**: Internal timeout in Debug Transport Module

### Running Tests with Increased Cycle Limit
```bash
# Run with increased cycle limit (5M cycles) and timeout
make veri-testharness elf=<test>.o issrun_opts="+max-cycles=5000000" log=<output>.log

# Through Python test runner with both timeouts increased
python3 cva6.py --test <test> --iss_timeout 3000 --target cv32a6_imac_sv32
```

### Linting and Type Checking
Run these commands before committing:
```bash
# Add lint commands here when discovered
make lint          # (if available)
make typecheck     # (if available)
```

## Important Notes
- Always check .iss files for SUCCESS/FAILURE status even if timeout occurs
- VCD files are critical for debugging cache behavior but are very large
- Address range validation prevents AXI violations in fully associative mode
- Test runner kills processes on timeout, preventing file cleanup - manual recovery may be needed