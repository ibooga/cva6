#!/usr/bin/env python3
"""
Focused Cache Behavior Analysis
Identify why fully associative cache takes 500x more cycles than normal cache
"""

import subprocess
import sys
import re
import os
from pathlib import Path

def analyze_cache_signals(vcd_file, name, sample_limit=100000):
    """Extract cache-specific behavior patterns"""
    print(f"\n=== Cache Behavior Analysis: {name} ===")
    
    file_size_mb = Path(vcd_file).stat().st_size / (1024 * 1024)
    print(f"VCD size: {file_size_mb:.1f} MB")
    
    results = {}
    
    # Key cache signals to analyze
    cache_signals = [
        'req_i',           # Cache requests
        'gnt_o',           # Cache grants
        'miss_o',          # Cache misses
        'data_req',        # Data requests
        'data_rsp',        # Data responses
        'valid',           # Valid signals
        'ready',           # Ready signals
        'axi_req',         # AXI requests
        'axi_rsp',         # AXI responses
        'ar_valid',        # AXI AR channel
        'aw_valid',        # AXI AW channel
        'r_valid',         # AXI R channel
        'w_valid',         # AXI W channel
        'stall',           # Stall conditions
        'flush'            # Cache flushes
    ]
    
    print("Extracting cache signal activity...")
    
    for signal in cache_signals:
        try:
            # Count signal transitions 
            cmd = ['grep', '-c', signal, vcd_file]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                count = int(result.stdout.strip())
                results[signal] = count
                print(f"  {signal}: {count:,} transitions")
            else:
                results[signal] = 0
                
        except Exception as e:
            print(f"  Error analyzing {signal}: {e}")
            results[signal] = 0
    
    return results

def extract_timing_analysis(vcd_file, name):
    """Extract detailed timing information"""
    print(f"\n=== Timing Analysis: {name} ===")
    
    try:
        # Get comprehensive timestamp analysis
        cmd = ['grep', '-E', '^#[0-9]+', vcd_file]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        
        if result.returncode == 0:
            timestamps = []
            lines = result.stdout.split('\n')
            
            # Sample every 100th timestamp for efficiency
            for i, line in enumerate(lines):
                if line.startswith('#') and i % 100 == 0:
                    try:
                        ts = int(line[1:])
                        timestamps.append(ts)
                    except ValueError:
                        continue
            
            if timestamps:
                min_time = min(timestamps)
                max_time = max(timestamps)
                total_time = max_time - min_time
                cycles = total_time // 2
                
                print(f"Time range: {min_time} to {max_time}")
                print(f"Total simulation time: {total_time} time units")
                print(f"Estimated cycles: {cycles:,}")
                print(f"Timestamp samples analyzed: {len(timestamps):,}")
                
                # Calculate activity density
                if len(timestamps) > 1:
                    avg_time_step = total_time / len(timestamps)
                    print(f"Average time step: {avg_time_step:.1f} time units")
                
                return {
                    'cycles': cycles,
                    'total_time': total_time,
                    'samples': len(timestamps),
                    'avg_step': avg_time_step if len(timestamps) > 1 else 0
                }
        
    except Exception as e:
        print(f"Error in timing analysis: {e}")
    
    return None

def detect_stall_patterns(vcd_file, name):
    """Look for patterns indicating stalls or deadlocks"""
    print(f"\n=== Stall/Deadlock Detection: {name} ===")
    
    try:
        # Look for repetitive patterns in signal changes
        cmd = ['head', '-n', '50000', vcd_file]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            lines = result.stdout.split('\n')
            
            # Look for repeated signal sequences
            signal_sequences = []
            current_timestamp = None
            current_signals = []
            
            for line in lines[-1000:]:  # Analyze last 1000 lines of sample
                line = line.strip()
                
                if line.startswith('#'):
                    if current_signals:
                        signal_sequences.append(tuple(current_signals))
                    current_signals = []
                    current_timestamp = line
                elif line and not line.startswith('$'):
                    current_signals.append(line)
            
            # Check for repeated patterns (indicating loops/stalls)
            if signal_sequences:
                from collections import Counter
                pattern_counts = Counter(signal_sequences)
                repeated_patterns = [(pattern, count) for pattern, count in pattern_counts.items() if count > 2]
                
                if repeated_patterns:
                    print(f"⚠️  Found {len(repeated_patterns)} repeated signal patterns")
                    print("Most frequent patterns:")
                    for i, (pattern, count) in enumerate(repeated_patterns[:3]):
                        print(f"  Pattern {i+1}: {count} repetitions, {len(pattern)} signals")
                        if len(pattern) < 5:  # Show short patterns
                            for sig in pattern:
                                print(f"    {sig}")
                else:
                    print("✅ No obvious repeated patterns detected")
                    
                return len(repeated_patterns)
    
    except Exception as e:
        print(f"Error in stall detection: {e}")
    
    return 0

def compare_cache_performance(normal_results, fa_results):
    """Compare normal vs fully associative cache performance"""
    print(f"\n=== CACHE PERFORMANCE COMPARISON ===")
    
    print(f"{'Signal':<15} {'Normal':<12} {'Fully Assoc':<12} {'Ratio':<8} {'Issue'}")
    print("="*65)
    
    critical_issues = []
    
    for signal in normal_results:
        normal_count = normal_results[signal]
        fa_count = fa_results.get(signal, 0)
        
        if normal_count > 0:
            ratio = fa_count / normal_count
            issue = ""
            
            if ratio > 100:
                issue = "🚨 CRITICAL"
                critical_issues.append((signal, ratio))
            elif ratio > 10:
                issue = "⚠️  HIGH"
            elif ratio > 3:
                issue = "⚠️  ELEVATED"
            else:
                issue = "✅ OK"
                
            print(f"{signal:<15} {normal_count:<12,} {fa_count:<12,} {ratio:<8.1f} {issue}")
        elif fa_count > 0:
            print(f"{signal:<15} {normal_count:<12,} {fa_count:<12,} {'∞':<8} 🚨 NEW")
            critical_issues.append((signal, float('inf')))
    
    return critical_issues

def main():
    print("=== CVA6 Cache Behavior Analysis ===")
    print("Investigating 500x cycle increase in fully associative cache")
    
    # VCD files to analyze
    normal_vcd = "/home/cai/cache_project/sandbox/cva6/verif/sim/out_2025-06-19/veri-testharness_sim/wt_hello_world.cv32a6_imac_sv32.vcd"
    fa_vcd = "/home/cai/cache_project/sandbox/cva6/verif/sim/out_2025-06-20/veri-testharness_sim/hello_world.cv32a6_imac_sv32.vcd"
    
    # Check if files exist
    if not os.path.exists(normal_vcd):
        print(f"❌ Normal cache VCD not found: {normal_vcd}")
        return
        
    if not os.path.exists(fa_vcd):
        print(f"❌ Fully associative VCD not found: {fa_vcd}")
        return
    
    # Analyze both configurations
    print("🔍 Analyzing Normal WT Cache...")
    normal_signals = analyze_cache_signals(normal_vcd, "Normal WT Cache")
    normal_timing = extract_timing_analysis(normal_vcd, "Normal WT Cache")
    normal_stalls = detect_stall_patterns(normal_vcd, "Normal WT Cache")
    
    print("\n🔍 Analyzing Fully Associative WT_CLN Cache...")
    fa_signals = analyze_cache_signals(fa_vcd, "Fully Associative WT_CLN")
    fa_timing = extract_timing_analysis(fa_vcd, "Fully Associative WT_CLN")
    fa_stalls = detect_stall_patterns(fa_vcd, "Fully Associative WT_CLN")
    
    # Compare results
    critical_issues = compare_cache_performance(normal_signals, fa_signals)
    
    # Summary analysis
    print(f"\n=== ROOT CAUSE ANALYSIS SUMMARY ===")
    
    if normal_timing and fa_timing:
        cycle_ratio = fa_timing['cycles'] / normal_timing['cycles']
        print(f"Cycle count ratio: {cycle_ratio:.1f}x slower")
        
        if fa_timing['avg_step'] > normal_timing['avg_step'] * 2:
            print(f"⚠️  Average time step is {fa_timing['avg_step']/normal_timing['avg_step']:.1f}x longer")
    
    if fa_stalls > normal_stalls * 2:
        print(f"🚨 Excessive stall patterns detected: {fa_stalls} vs {normal_stalls}")
    
    if critical_issues:
        print(f"\n🎯 TOP ISSUES TO INVESTIGATE:")
        critical_issues.sort(key=lambda x: x[1], reverse=True)
        for i, (signal, ratio) in enumerate(critical_issues[:5]):
            if ratio == float('inf'):
                print(f"  {i+1}. {signal}: Only present in FA cache - investigate why")
            else:
                print(f"  {i+1}. {signal}: {ratio:.0f}x more activity - likely bottleneck")
    
    print(f"\n=== NEXT STEPS ===")
    print("1. Focus investigation on signals with highest activity ratios")
    print("2. Check cache state machine for the top issue signals")
    print("3. Look for infinite loops in cache replacement or address decoding")
    print("4. Consider testing intermediate associativity levels")

if __name__ == "__main__":
    main()