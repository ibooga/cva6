#!/usr/bin/env python3
"""
Deep Analysis of req_i Signal Pattern
Why does fully associative cache have 5.2x more req_i transitions?
"""

import subprocess
import sys
import re
from collections import defaultdict

def extract_req_pattern(vcd_file, name, limit=50000):
    """Extract req_i signal pattern and timing"""
    print(f"\n=== req_i Pattern Analysis: {name} ===")
    
    try:
        # Extract first portion of VCD with timestamps and req_i changes
        cmd = ['head', '-n', str(limit), vcd_file]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode != 0:
            print("Failed to extract VCD content")
            return None
            
        lines = result.stdout.split('\n')
        
        # Parse timestamps and req_i signal changes
        current_time = 0
        req_events = []
        req_current_state = None
        
        # Find req_i signal identifier
        req_id = None
        in_header = True
        
        for line in lines:
            line = line.strip()
            
            if line.startswith('$var') and 'req_i' in line:
                parts = line.split()
                if len(parts) >= 4:
                    req_id = parts[3]  # Signal identifier
                    print(f"Found req_i signal ID: {req_id}")
                    
            elif line.startswith('$dumpvars') or line.startswith('#'):
                in_header = False
                
            if not in_header:
                if line.startswith('#'):
                    try:
                        current_time = int(line[1:])
                    except ValueError:
                        continue
                        
                elif req_id and line.startswith(('0', '1')) and line.endswith(req_id):
                    # req_i signal change
                    new_state = line[0]
                    if new_state != req_current_state:
                        req_events.append((current_time, new_state))
                        req_current_state = new_state
        
        if req_events:
            print(f"Found {len(req_events)} req_i transitions")
            
            # Analyze patterns
            request_periods = []
            high_periods = []
            
            for i in range(len(req_events) - 1):
                current_time, current_state = req_events[i]
                next_time, next_state = req_events[i + 1]
                period = next_time - current_time
                
                request_periods.append(period)
                
                if current_state == '1':  # High period
                    high_periods.append(period)
            
            if request_periods:
                avg_period = sum(request_periods) / len(request_periods)
                min_period = min(request_periods)
                max_period = max(request_periods)
                
                print(f"Request period stats:")
                print(f"  Average: {avg_period:.1f} time units")
                print(f"  Min: {min_period} time units") 
                print(f"  Max: {max_period} time units")
                
                # Look for very short periods (potential rapid cycling)
                short_periods = [p for p in request_periods if p < 10]
                if short_periods:
                    print(f"⚠️  {len(short_periods)} very short periods (<10 units) detected")
                    print(f"     Shortest: {min(short_periods)} units")
                
                # Look for stuck high periods
                if high_periods:
                    avg_high = sum(high_periods) / len(high_periods)
                    max_high = max(high_periods)
                    print(f"High period stats:")
                    print(f"  Average high: {avg_high:.1f} time units")
                    print(f"  Max high: {max_high} time units")
                    
                    if max_high > avg_high * 10:
                        print(f"🚨 Very long high period detected: {max_high} units")
                
                return {
                    'total_transitions': len(req_events),
                    'avg_period': avg_period,
                    'min_period': min_period,
                    'max_period': max_period,
                    'short_periods': len(short_periods),
                    'avg_high': avg_high if high_periods else 0,
                    'max_high': max_high if high_periods else 0
                }
        else:
            print("No req_i transitions found")
            return None
            
    except Exception as e:
        print(f"Error analyzing req_i pattern: {e}")
        return None

def check_cache_controller_state(cache_file):
    """Check cache controller state machine for potential issues"""
    print(f"\n=== Cache Controller State Analysis ===")
    
    try:
        # Look for state machine definitions in cache controller
        result = subprocess.run(['grep', '-n', '-A', '10', '-B', '5', 'state.*enum\\|typedef.*state', cache_file], 
                              capture_output=True, text=True)
        
        if result.returncode == 0:
            print("Found state machine definitions:")
            print(result.stdout)
        else:
            print("No obvious state machine enums found")
            
        # Look for always blocks that might cause request cycling
        result = subprocess.run(['grep', '-n', '-A', '5', 'always.*req_i\\|req_i.*always', cache_file], 
                              capture_output=True, text=True)
        
        if result.returncode == 0:
            print("\nFound req_i related always blocks:")
            print(result.stdout)
            
    except Exception as e:
        print(f"Error checking controller state: {e}")

def investigate_request_generation():
    """Look for what generates cache requests"""
    print(f"\n=== Request Generation Investigation ===")
    
    cache_files = [
        "/home/cai/cache_project/sandbox/cva6/core/cache_subsystem/wt_cln_dcache.sv",
        "/home/cai/cache_project/sandbox/cva6/core/cache_subsystem/wt_cln_dcache_ctrl.sv",
        "/home/cai/cache_project/sandbox/cva6/core/cache_subsystem/wt_cln_dcache_missunit.sv"
    ]
    
    for cache_file in cache_files:
        try:
            # Look for req_i signal usage
            result = subprocess.run(['grep', '-n', '-B', '2', '-A', '2', 'req_i', cache_file], 
                                  capture_output=True, text=True)
            
            if result.returncode == 0:
                print(f"\n--- {cache_file} ---")
                lines = result.stdout.split('\n')
                for line in lines[:20]:  # Show first 20 matches
                    if line.strip():
                        print(line)
                        
        except Exception as e:
            print(f"Error checking {cache_file}: {e}")

def main():
    print("=== Deep req_i Signal Analysis ===")
    print("Investigating why fully associative cache has 5.2x more req_i activity")
    
    # VCD files
    normal_vcd = "/home/cai/cache_project/sandbox/cva6/verif/sim/out_2025-06-19/veri-testharness_sim/wt_hello_world.cv32a6_imac_sv32.vcd"
    fa_vcd = "/home/cai/cache_project/sandbox/cva6/verif/sim/out_2025-06-20/veri-testharness_sim/hello_world.cv32a6_imac_sv32.vcd"
    
    # Analyze req_i patterns
    normal_pattern = extract_req_pattern(normal_vcd, "Normal WT Cache")
    fa_pattern = extract_req_pattern(fa_vcd, "Fully Associative WT_CLN")
    
    # Compare patterns
    if normal_pattern and fa_pattern:
        print(f"\n=== req_i Pattern Comparison ===")
        print(f"{'Metric':<20} {'Normal':<15} {'Fully Assoc':<15} {'Ratio'}")
        print("="*65)
        
        metrics = ['total_transitions', 'avg_period', 'min_period', 'max_period', 'short_periods']
        
        for metric in metrics:
            normal_val = normal_pattern[metric]
            fa_val = fa_pattern[metric]
            
            if normal_val > 0:
                ratio = fa_val / normal_val
                print(f"{metric:<20} {normal_val:<15.1f} {fa_val:<15.1f} {ratio:.2f}x")
            else:
                print(f"{metric:<20} {normal_val:<15.1f} {fa_val:<15.1f} N/A")
    
    # Check cache controller logic
    check_cache_controller_state("/home/cai/cache_project/sandbox/cva6/core/cache_subsystem/wt_cln_dcache_ctrl.sv")
    
    # Investigate request generation
    investigate_request_generation()
    
    print(f"\n=== ANALYSIS CONCLUSIONS ===")
    print("1. Compare req_i period patterns between normal and FA cache")
    print("2. Look for rapid cycling or stuck states in FA cache")
    print("3. Check cache controller state machine for infinite loops")
    print("4. Investigate if address decoding causes request retries")

if __name__ == "__main__":
    main()