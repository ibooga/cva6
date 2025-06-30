#!/bin/bash

# Script to recover files after timeout in fully associative cache tests
# Usage: ./recover_timeout_files.sh [test_name] [target]

set -e

TEST_NAME=${1:-"hello_world"}
TARGET=${2:-"cv32a6_imac_sv32"}
DATE=$(date +%Y-%m-%d)
OUTPUT_DIR="out_${DATE}/veri-testharness_sim"

echo "=== CVA6 Timeout File Recovery Script ==="
echo "Test: ${TEST_NAME}"
echo "Target: ${TARGET}"
echo "Output directory: ${OUTPUT_DIR}"

# Check if simulation completed successfully
ISS_FILE="${OUTPUT_DIR}/${TEST_NAME}.${TARGET}.log.iss"
if [[ -f "${ISS_FILE}" ]]; then
    if grep -q "*** SUCCESS ***" "${ISS_FILE}"; then
        echo "✅ Found SUCCESS in ${ISS_FILE}"
        SUCCESS_FOUND=true
    else
        echo "❌ No SUCCESS found in ${ISS_FILE}"
        SUCCESS_FOUND=false
    fi
else
    echo "❌ ISS file not found: ${ISS_FILE}"
    exit 1
fi

if [[ "${SUCCESS_FOUND}" == "true" ]] || [[ "$1" == "--force" ]]; then
    if [[ "$1" == "--force" ]]; then
        echo "⚠️  Forcing recovery despite test failure"
    fi
    echo ""
    echo "=== Recovering files ==="
    
    # Create output directory if needed
    mkdir -p "${OUTPUT_DIR}"
    
    # Move VCD file if present
    if [[ -f "verilator.vcd" ]]; then
        echo "Moving VCD file..."
        mv "verilator.vcd" "${OUTPUT_DIR}/${TEST_NAME}.${TARGET}.vcd"
        echo "✅ VCD file moved to ${OUTPUT_DIR}/${TEST_NAME}.${TARGET}.vcd"
    else
        echo "⚠️  No verilator.vcd file found"
    fi
    
    # Generate log file from trace if needed
    LOG_FILE="${OUTPUT_DIR}/${TEST_NAME}.${TARGET}.log"
    if [[ ! -s "${LOG_FILE}" ]] && [[ -f "trace_rvfi_hart_00.dasm" ]]; then
        echo "Generating log file from trace..."
        cp "trace_rvfi_hart_00.dasm" "${LOG_FILE}"
        echo "✅ Log file generated: ${LOG_FILE}"
    elif [[ -s "${LOG_FILE}" ]]; then
        echo "✅ Log file already exists: ${LOG_FILE}"
    else
        echo "⚠️  Cannot generate log file - no trace found"
    fi
    
    echo ""
    echo "=== Recovery Complete ==="
    echo "Files in ${OUTPUT_DIR}:"
    ls -lh "${OUTPUT_DIR}/${TEST_NAME}.${TARGET}."*
    
else
    echo ""
    echo "❌ Test did not complete successfully - no file recovery performed"
    exit 1
fi