#!/usr/bin/env python3
"""
Cache Signal Analysis to Identify Performance Bottleneck Root Cause
Focus on specific signals that could cause 465x slowdown in fully associative cache
"""

import subprocess
import sys
import os
from pathlib import Path

def extract_signal_activity(vcd_file, signal_patterns, name, time_limit=None):
    """Extract activity for specific signal patterns"""
    print(f"\n=== Signal Activity Analysis: {name} ===")
    
    results = {}
    
    for pattern in signal_patterns:
        try:
            # Count occurrences of signal pattern
            cmd = ['grep', '-c', pattern, vcd_file]
            if time_limit:
                cmd = ['timeout', str(time_limit), 'grep', '-c', pattern, vcd_file]
                
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                count = int(result.stdout.strip())
                results[pattern] = count
                print(f"{pattern}: {count:,} occurrences")
            else:
                results[pattern] = 0
                
        except Exception as e:
            print(f"Error analyzing {pattern}: {e}")
            results[pattern] = 0
            
    return results

def analyze_cache_states(vcd_file, name, sample_size=1000):
    """Analyze cache state transitions and potential loops"""
    print(f"\n=== Cache State Analysis: {name} ===")
    
    try:
        # Extract a sample of the VCD for state analysis
        cmd = ['head', '-n', str(sample_size * 10), vcd_file]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode != 0:
            print("Failed to extract VCD sample")
            return {}
            
        lines = result.stdout.split('\n')
        
        # Look for state machine patterns
        state_transitions = 0
        cache_requests = 0
        axi_requests = 0
        timestamp_count = 0
        
        for line in lines:
            line = line.strip()
            
            if line.startswith('#'):
                timestamp_count += 1
            elif 'req' in line.lower() and ('1' in line or '0' in line):
                cache_requests += 1
            elif 'axi' in line.lower() and ('valid' in line.lower()):
                axi_requests += 1
            elif 'state' in line.lower():
                state_transitions += 1
                
        print(f"Sample analysis ({sample_size} lines):")
        print(f"  Timestamps: {timestamp_count}")
        print(f"  Cache requests: {cache_requests}")  
        print(f"  AXI requests: {axi_requests}")
        print(f"  State transitions: {state_transitions}")
        
        if timestamp_count > 0:
            print(f"  Activity density: {(cache_requests + axi_requests)/timestamp_count:.2f} events/timestamp")
            
        return {
            'timestamps': timestamp_count,
            'cache_requests': cache_requests,
            'axi_requests': axi_requests,
            'state_transitions': state_transitions
        }
        
    except Exception as e:
        print(f"Error in state analysis: {e}")
        return {}

def find_repetitive_patterns(vcd_file, name):
    """Look for repetitive signal patterns that indicate loops"""
    print(f"\n=== Repetitive Pattern Analysis: {name} ===")
    
    try:
        # Extract middle section to look for steady-state patterns
        file_size = Path(vcd_file).stat().st_size
        
        if file_size > 100 * 1024 * 1024:  # Large files
            # Use sed to extract middle section
            start_line = 50000
            num_lines = 1000
            cmd = ['sed', '-n', f'{start_line},{start_line + num_lines}p', vcd_file]
        else:
            # Use tail/head for smaller files
            cmd = ['tail', '-n', '10000', vcd_file]
            
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode != 0:
            print("Failed to extract pattern sample")
            return
            
        lines = result.stdout.split('\n')
        
        # Look for repeated sequences
        signal_sequences = []
        current_timestamp = None
        current_sequence = []
        
        for line in lines[:500]:  # Limit analysis
            line = line.strip()
            
            if line.startswith('#'):
                if current_sequence:
                    signal_sequences.append(current_sequence)
                current_sequence = []
                current_timestamp = line
            elif line and not line.startswith('$'):
                current_sequence.append(line)
                
        # Find common patterns
        if signal_sequences:
            # Simple pattern detection: look for sequences that appear multiple times
            from collections import Counter
            sequence_counts = Counter(tuple(seq) for seq in signal_sequences[:20])
            
            repeated_patterns = [(seq, count) for seq, count in sequence_counts.items() if count > 1]
            
            if repeated_patterns:
                print(f"Found {len(repeated_patterns)} repeated signal patterns")
                print("Most common patterns:")
                for i, (pattern, count) in enumerate(repeated_patterns[:3]):
                    print(f"  Pattern {i+1}: {count} occurrences, {len(pattern)} signals")
                    
                if len(repeated_patterns) > 5:
                    print("⚠️  Many repeated patterns detected - possible infinite loop!")
            else:
                print("No obvious repeated patterns found")
        else:
            print("Could not extract signal sequences")
            
    except Exception as e:
        print(f"Error in pattern analysis: {e}")

def main():
    print("=== Cache Signal Analysis for Performance Bottleneck ===")
    
    # VCD files
    normal_vcd = "/home/cai/cache_project/sandbox/cva6/verif/sim/out_2025-06-19/veri-testharness_sim/wt_hello_world.cv32a6_imac_sv32.vcd"
    fa_vcd = "/home/cai/cache_project/sandbox/cva6/verif/sim/out_2025-06-20/veri-testharness_sim/hello_world.cv32a6_imac_sv32.vcd"
    
    # Key signal patterns to analyze
    cache_signals = [
        'req_i',
        'gnt_o', 
        'data_req',
        'data_rsp',
        'cache_miss',
        'cache_hit'
    ]
    
    axi_signals = [
        'axi_req_o',
        'axi_rsp_i',
        'ar_valid',
        'aw_valid',
        'r_valid',
        'w_valid',
        'r_ready',
        'w_ready'
    ]
    
    performance_signals = [
        'valid',
        'ready',
        'stall',
        'flush',
        'miss',
        'hit'
    ]
    
    all_signals = cache_signals + axi_signals + performance_signals
    
    print(f"Analyzing {len(all_signals)} signal patterns...")
    
    # Analyze normal cache
    if os.path.exists(normal_vcd):
        normal_results = extract_signal_activity(normal_vcd, all_signals, "Normal WT Cache")
        normal_states = analyze_cache_states(normal_vcd, "Normal WT Cache")
        find_repetitive_patterns(normal_vcd, "Normal WT Cache")
    else:
        print(f"Normal cache VCD not found: {normal_vcd}")
        return
    
    # Analyze fully associative cache (with limits for large file)
    if os.path.exists(fa_vcd):
        fa_results = extract_signal_activity(fa_vcd, all_signals, "Fully Associative WT_CLN", time_limit=60)
        fa_states = analyze_cache_states(fa_vcd, "Fully Associative WT_CLN", sample_size=500)
        find_repetitive_patterns(fa_vcd, "Fully Associative WT_CLN")
    else:
        print(f"Fully associative VCD not found: {fa_vcd}")
        return
    
    # Compare signal activity
    print(f"\n=== Signal Activity Comparison ===")
    print(f"{'Signal':<15} {'Normal':<15} {'Fully Assoc':<15} {'Ratio':<10}")
    print(f"{'='*65}")
    
    for signal in all_signals:
        normal_count = normal_results.get(signal, 0)
        fa_count = fa_results.get(signal, 0)
        
        if normal_count > 0:
            ratio = fa_count / normal_count
            print(f"{signal:<15} {normal_count:<15,} {fa_count:<15,} {ratio:<10.1f}x")
        elif fa_count > 0:
            print(f"{signal:<15} {normal_count:<15,} {fa_count:<15,} {'∞':<10}")
    
    # Identify potential culprits
    print(f"\n=== Root Cause Analysis ===")
    
    culprit_signals = []
    for signal in all_signals:
        normal_count = normal_results.get(signal, 0)
        fa_count = fa_results.get(signal, 0)
        
        if normal_count > 0 and fa_count / normal_count > 100:
            culprit_signals.append((signal, fa_count / normal_count))
    
    if culprit_signals:
        print("🔍 High-activity signals (potential culprits):")
        culprit_signals.sort(key=lambda x: x[1], reverse=True)
        for signal, ratio in culprit_signals[:5]:
            print(f"  {signal}: {ratio:.0f}x more activity")
            
        print(f"\n💡 Investigation priorities:")
        print(f"1. Focus on signals with highest activity ratios")
        print(f"2. Check for infinite loops in cache replacement logic")
        print(f"3. Examine AXI protocol handling for deadlocks")
        print(f"4. Verify address decoding with INDEX_WIDTH=0")
    else:
        print("No obvious high-activity signals detected in this analysis")
        print("Consider deeper VCD inspection with GTKWave")

if __name__ == "__main__":
    main()