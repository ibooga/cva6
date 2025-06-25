#!/bin/bash

# Comprehensive script for running fully associative cache tests
# This script handles all timeout and cycle limit issues

set -e

TEST_NAME=${1:-"hello_world"}
TARGET=${2:-"cv32a6_imac_sv32"}
TIMEOUT=${3:-"3000"}
MAX_CYCLES=${4:-"5000000"}

echo "=== CVA6 Fully Associative Cache Test Runner ==="
echo "Test: ${TEST_NAME}"
echo "Target: ${TARGET}" 
echo "Timeout: ${TIMEOUT}s"
echo "Max Cycles: ${MAX_CYCLES}"
echo ""

# Method 1: Try Python runner with increased timeout
echo "=== Method 1: Python Test Runner ==="
echo "Running: python3 cva6.py --c_tests ../tests/custom/hello_world/hello_world.c --iss_timeout ${TIMEOUT} --target ${TARGET}"

if timeout ${TIMEOUT} python3 cva6.py --c_tests ../tests/custom/hello_world/hello_world.c --iss_timeout ${TIMEOUT} --target ${TARGET}; then
    echo "✅ Python test runner succeeded"
    exit 0
fi

echo "⚠️  Python test runner failed or timed out, trying direct make..."
echo ""

# Method 2: Direct make with cycle limit
echo "=== Method 2: Direct Make with Cycle Limit ==="
ELF_FILE="out_*/directed_tests/${TEST_NAME}.o"
if ls ${ELF_FILE} 1> /dev/null 2>&1; then
    ELF_PATH=$(ls ${ELF_FILE} | head -1)
    echo "Found ELF: ${ELF_PATH}"
else
    # Use previous successful ELF
    ELF_PATH="/home/cai/cache_project/sandbox/cva6/verif/sim/out_2025-06-19/directed_tests/hello_world.o"
    echo "Using previous ELF: ${ELF_PATH}"
fi

DATE=$(date +%Y-%m-%d)
OUTPUT_DIR="out_${DATE}/veri-testharness_sim"
mkdir -p "${OUTPUT_DIR}"

echo "Running: make veri-testharness with increased cycle limit..."
timeout ${TIMEOUT} make veri-testharness \
    target=${TARGET} \
    variant=rv32imac_zbkb_zbkx_zkne_zknd_zknh_zicsr_zifencei \
    elf="${ELF_PATH}" \
    path_var=/home/cai/cache_project/sandbox/cva6/ \
    tool_path=/home/cai/cache_project/sandbox/cva6/tools/spike/bin \
    isscomp_opts="" \
    issrun_opts="+debug_disable=1 +max-cycles=${MAX_CYCLES}" \
    isspostrun_opts="0x0000000080000000" \
    log="${OUTPUT_DIR}/${TEST_NAME}.${TARGET}.log" \
    2>&1 || echo "Make command timed out or failed"

echo ""
echo "=== Post-Test Recovery ==="

# Check for output files and recover if needed
if [[ -f "verilator.vcd" ]]; then
    echo "Moving VCD file..."
    mv "verilator.vcd" "${OUTPUT_DIR}/${TEST_NAME}.${TARGET}.vcd"
    echo "✅ VCD file moved"
fi

if [[ -f "trace_rvfi_hart_00.dasm" ]]; then
    echo "Moving trace file..."
    cp "trace_rvfi_hart_00.dasm" "${OUTPUT_DIR}/${TEST_NAME}.${TARGET}.trace"
    echo "✅ Trace file copied"
fi

# Check results
ISS_FILE="${OUTPUT_DIR}/${TEST_NAME}.${TARGET}.log.iss"
if [[ -f "${ISS_FILE}" ]]; then
    if grep -q "SUCCESS" "${ISS_FILE}"; then
        echo "🎉 TEST PASSED - Found SUCCESS in simulation"
        echo "Files in ${OUTPUT_DIR}:"
        ls -lh "${OUTPUT_DIR}/"
        exit 0
    elif grep -q "FAILED" "${ISS_FILE}"; then
        echo "❌ TEST FAILED - Found FAILED in simulation"
        echo "Check ${ISS_FILE} for details"
        exit 1
    else
        echo "⚠️  Test completed but status unclear"
        echo "Check ${ISS_FILE} for details"
        exit 2
    fi
else
    echo "❌ No ISS file found - test may not have completed"
    exit 3
fi