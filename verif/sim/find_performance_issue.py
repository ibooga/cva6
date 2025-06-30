#!/usr/bin/env python3
"""
Cache Performance Bottleneck Analysis
Systematically analyze VCD files to identify why fully associative cache is 463x slower
"""

import subprocess
import sys
import re
from pathlib import Path

def analyze_cache_activity(vcd_file, name):
    """Analyze cache-related activity patterns in VCD file"""
    print(f"\n=== Analyzing {name} ===")
    print(f"File: {vcd_file}")
    
    # Get file size and basic stats
    size_mb = Path(vcd_file).stat().st_size / (1024 * 1024)
    print(f"VCD size: {size_mb:.1f} MB")
    
    # Extract timestamps to understand simulation length
    try:
        result = subprocess.run(['grep', '-E', '^#[0-9]+', vcd_file], 
                              capture_output=True, text=True, timeout=60)
        
        if result.returncode == 0:
            timestamps = []
            for line in result.stdout.split('\n'):
                if line.startswith('#'):
                    try:
                        ts = int(line[1:])
                        timestamps.append(ts)
                    except ValueError:
                        continue
            
            if timestamps:
                cycles = max(timestamps) // 2
                print(f"Total cycles: {cycles:,}")
                print(f"MB per 1000 cycles: {(size_mb * 1000 / cycles):.2f}")
                
                return cycles, size_mb
    
    except Exception as e:
        print(f"Error analyzing {name}: {e}")
    
    return None, size_mb

def find_repeated_patterns(vcd_file, name):
    """Look for repeated signal patterns that might indicate loops or excessive activity"""
    print(f"\n=== Looking for repeated patterns in {name} ===")
    
    try:
        # Sample the middle section of the VCD file to look for patterns
        result = subprocess.run(['sed', '-n', '100000,200000p', vcd_file], 
                              capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            lines = result.stdout.split('\n')
            
            # Count signal transitions
            signal_changes = {}
            current_time = 0
            
            for line in lines:
                line = line.strip()
                if line.startswith('#'):
                    try:
                        current_time = int(line[1:])
                    except ValueError:
                        continue
                elif len(line) > 1 and not line.startswith('$'):
                    # Signal change line (simplified parsing)
                    if current_time in signal_changes:
                        signal_changes[current_time] += 1
                    else:
                        signal_changes[current_time] = 1
            
            if signal_changes:
                avg_changes = sum(signal_changes.values()) / len(signal_changes)
                max_changes = max(signal_changes.values())
                print(f"Average signal changes per time unit: {avg_changes:.1f}")
                print(f"Maximum signal changes per time unit: {max_changes}")
                
                # Look for time periods with excessive activity
                high_activity_periods = [t for t, changes in signal_changes.items() 
                                       if changes > avg_changes * 3]
                
                if high_activity_periods:
                    print(f"High activity periods found: {len(high_activity_periods)}")
                    print(f"Sample timestamps: {high_activity_periods[:5]}")
                else:
                    print("No unusual activity patterns detected")
                
                return avg_changes, max_changes
    
    except Exception as e:
        print(f"Error finding patterns in {name}: {e}")
    
    return None, None

def analyze_axi_activity(vcd_file, name):
    """Look for AXI-related activity patterns"""
    print(f"\n=== Analyzing AXI activity in {name} ===")
    
    try:
        # Look for AXI signal patterns
        axi_patterns = [
            'axi_req_o',
            'axi_rsp_i', 
            'ar_valid',
            'aw_valid',
            'r_valid',
            'w_valid'
        ]
        
        for pattern in axi_patterns:
            result = subprocess.run(['grep', '-c', pattern, vcd_file], 
                                  capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                count = int(result.stdout.strip())
                print(f"{pattern}: {count} occurrences")
    
    except Exception as e:
        print(f"Error analyzing AXI activity in {name}: {e}")

def main():
    # Analyze both VCD files
    normal_vcd = "/home/cai/cache_project/sandbox/cva6/verif/sim/out_2025-06-19/veri-testharness_sim/wt_hello_world.cv32a6_imac_sv32.vcd"
    fa_vcd = "/home/cai/cache_project/sandbox/cva6/verif/sim/out_2025-06-20/veri-testharness_sim/hello_world.cv32a6_imac_sv32.vcd"
    
    print("=== CVA6 Cache Performance Bottleneck Analysis ===")
    print("Comparing normal WT cache vs fully associative WT_CLN cache")
    
    # Basic analysis
    normal_cycles, normal_size = analyze_cache_activity(normal_vcd, "Normal WT Cache")
    fa_cycles, fa_size = analyze_cache_activity(fa_vcd, "Fully Associative WT_CLN Cache")
    
    # Performance comparison
    if normal_cycles and fa_cycles:
        slowdown = fa_cycles / normal_cycles
        size_ratio = fa_size / normal_size
        print(f"\n=== Performance Comparison ===")
        print(f"Cycle count ratio: {slowdown:.1f}x slower")
        print(f"VCD size ratio: {size_ratio:.1f}x larger")
        print(f"Activity density ratio: {(size_ratio/slowdown):.1f}x")
        
        if slowdown > 100:
            print("🚨 SEVERE PERFORMANCE ISSUE DETECTED!")
            print("Possible causes:")
            print("- Infinite loops in cache logic")
            print("- Excessive cache miss/replacement activity")
            print("- AXI protocol stalls or deadlocks")
            print("- Address decoding issues with INDEX_WIDTH=0")
    
    # Pattern analysis
    find_repeated_patterns(normal_vcd, "Normal WT Cache")
    find_repeated_patterns(fa_vcd, "Fully Associative WT_CLN Cache")
    
    # AXI analysis
    analyze_axi_activity(normal_vcd, "Normal WT Cache")
    analyze_axi_activity(fa_vcd, "Fully Associative WT_CLN Cache")
    
    print(f"\n=== Recommendations ===")
    print("1. Focus investigation on cache replacement logic for 128-way associativity")
    print("2. Check for infinite loops in address decoding with INDEX_WIDTH=0")
    print("3. Examine AXI request/response patterns for deadlocks")
    print("4. Review cache miss handling in fully associative mode")
    print("5. Open VCD files in GTKWave for visual analysis:")
    print(f"   gtkwave {normal_vcd}")
    print(f"   gtkwave {fa_vcd}")

if __name__ == "__main__":
    main()