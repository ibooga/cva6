#!/usr/bin/env python3
"""
Advanced Cache Set Analysis Tool for CVA6 Hybrid Cache Testing

This tool analyzes the cache access patterns from the updated test to see
if different cache configurations actually exercise different sets.
"""

import os
import re
import sys
from collections import defaultdict

# Cache configuration for CV32A60X
CACHE_SIZE = 2048  # 2KB
CACHE_SETS = 16    # 16 sets
CACHE_WAYS = 8     # 8-way set associative  
CACHE_LINE_SIZE = 16  # 16 bytes per cache line
SET_SIZE = CACHE_SIZE // CACHE_SETS  # 128 bytes per set

def analyze_address_to_set(addr):
    """Convert memory address to cache set index"""
    # For CV32A60X: cache line is 16 bytes, so bottom 4 bits are offset
    # Next log2(CACHE_SETS) bits are the set index
    cache_line_addr = addr >> 4  # Remove byte offset
    set_index = cache_line_addr & (CACHE_SETS - 1)  # Get set index (bottom 4 bits)
    tag = cache_line_addr >> 4  # Remaining bits are tag
    return set_index, tag

def parse_simulation_log(log_file):
    """Parse simulation log to extract memory access patterns"""
    accesses = []
    set_usage = defaultdict(int)
    
    print(f"Analyzing: {log_file}")
    
    try:
        with open(log_file, 'r') as f:
            content = f.read()
            
        # Look for any memory access patterns or addresses in the log
        # This is a simplified parser - actual implementation depends on log format
        addr_patterns = [
            r'0x([0-9a-fA-F]+)',  # Hexadecimal addresses
            r'addr[:\s]+([0-9a-fA-F]+)',  # addr: format
            r'address[:\s]+([0-9a-fA-F]+)',  # address: format
        ]
        
        for pattern in addr_patterns:
            matches = re.findall(pattern, content)
            for match in matches:
                try:
                    addr = int(match, 16)
                    set_idx, tag = analyze_address_to_set(addr)
                    accesses.append((addr, set_idx, tag))
                    set_usage[set_idx] += 1
                except ValueError:
                    continue
    
    except FileNotFoundError:
        print(f"Warning: {log_file} not found")
        return [], {}
    
    return accesses, set_usage

def create_set_heatmap(set_usage, config_name):
    """Create a text-based heatmap showing set usage"""
    print(f"\n=== {config_name} Cache Set Usage ===")
    
    if not set_usage:
        print("No cache access data found")
        return
    
    max_accesses = max(set_usage.values()) if set_usage else 1
    
    print("Set  Usage  Heatmap")
    print("---  -----  -------")
    
    for set_idx in range(CACHE_SETS):
        accesses = set_usage.get(set_idx, 0)
        if max_accesses > 0:
            intensity = int((accesses / max_accesses) * 10)
            heatmap_char = str(intensity) if intensity < 10 else 'X'
        else:
            heatmap_char = '0'
        
        bar = '█' * min(accesses // max(max_accesses // 20, 1), 20)
        print(f" {set_idx:2d}   {accesses:4d}  {heatmap_char} {bar}")
    
    # Summary statistics
    total_accesses = sum(set_usage.values())
    used_sets = len([s for s in set_usage.values() if s > 0])
    
    print(f"\nSummary:")
    print(f"- Total accesses: {total_accesses}")
    print(f"- Sets used: {used_sets}/{CACHE_SETS} ({used_sets/CACHE_SETS*100:.1f}%)")
    print(f"- Max accesses per set: {max_accesses}")
    print(f"- Average per used set: {total_accesses/max(used_sets,1):.1f}")

def analyze_cache_comparison(results_dir):
    """Analyze cache access patterns for all four configurations"""
    
    configurations = [
        ('wt', 'WT (Standard)'),
        ('wt_hyb', 'WT_HYB (Hybrid)'), 
        ('wt_hyb_force_set_ass', 'WT_HYB_FORCE_SET_ASS'),
        ('wt_hyb_force_full_ass', 'WT_HYB_FORCE_FULL_ASS')
    ]
    
    print("CVA6 Cache Set Analysis - Updated Multi-Set Test")
    print("=" * 50)
    
    all_results = {}
    
    for config_dir, config_name in configurations:
        log_paths = [
            f"{results_dir}/{config_dir}/out_*/veri-testharness_sim/cache_test_loop.cv32a60x.log.iss",
            f"{results_dir}/{config_dir}/out_*/veri-testharness_sim/cache_test_loop.cv32a60x.log",
            f"{results_dir}/{config_dir}/simulation.log"
        ]
        
        for log_pattern in log_paths:
            # Expand glob pattern manually by checking if file exists
            import glob
            matching_files = glob.glob(log_pattern)
            
            for log_file in matching_files:
                if os.path.exists(log_file):
                    accesses, set_usage = parse_simulation_log(log_file)
                    if set_usage:  # Found some data
                        all_results[config_name] = set_usage
                        create_set_heatmap(set_usage, config_name)
                        break
            if config_name in all_results:
                break
    
    # Cross-configuration comparison
    if len(all_results) > 1:
        print("\n" + "=" * 50)
        print("CROSS-CONFIGURATION COMPARISON")
        print("=" * 50)
        
        # Compare set usage patterns
        config_names = list(all_results.keys())
        print(f"Set   " + "  ".join(f"{name[:12]:>12}" for name in config_names))
        print("---   " + "  ".join("-" * 12 for _ in config_names))
        
        for set_idx in range(CACHE_SETS):
            row = f" {set_idx:2d}   "
            for config_name in config_names:
                accesses = all_results[config_name].get(set_idx, 0)
                row += f"{accesses:>12}  "
            print(row)
    
    return all_results

if __name__ == "__main__":
    if len(sys.argv) > 1:
        results_dir = sys.argv[1]
    else:
        # Find the most recent results directory
        dirs = [d for d in os.listdir('.') if d.startswith('cache_comparison_')]
        if dirs:
            results_dir = sorted(dirs)[-1]
            print(f"Using most recent results: {results_dir}")
        else:
            print("No cache comparison results found")
            sys.exit(1)
    
    if not os.path.exists(results_dir):
        print(f"Results directory not found: {results_dir}")
        sys.exit(1)
    
    analyze_cache_comparison(results_dir)