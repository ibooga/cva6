#!/usr/bin/env python3
"""
VCD Analysis Script for CVA6 Fully Associative Cache Performance Investigation
"""

import sys
import re
import subprocess
from pathlib import Path

def analyze_vcd_header(vcd_file):
    """Extract basic information from VCD header"""
    print(f"=== Analyzing VCD: {vcd_file} ===")
    
    # Get file size
    size_mb = Path(vcd_file).stat().st_size / (1024 * 1024)
    print(f"File size: {size_mb:.1f} MB")
    
    # Parse VCD header for signals
    with open(vcd_file, 'r') as f:
        lines = []
        in_header = True
        for i, line in enumerate(f):
            if i > 10000:  # Limit header reading
                break
            lines.append(line.strip())
            if line.startswith('$dumpvars') or line.startswith('#'):
                in_header = False
                break
    
    # Find cache-related signals
    cache_signals = []
    axi_signals = []
    
    for line in lines:
        if line.startswith('$var'):
            parts = line.split()
            if len(parts) >= 4:
                signal_name = parts[4]
                if 'cache' in signal_name.lower() or 'dcache' in signal_name.lower():
                    cache_signals.append(signal_name)
                elif 'axi' in signal_name.lower():
                    axi_signals.append(signal_name)
    
    print(f"Found {len(cache_signals)} cache-related signals")
    print(f"Found {len(axi_signals)} AXI-related signals")
    
    # Show first few cache signals
    if cache_signals:
        print("Cache signals (first 10):")
        for sig in cache_signals[:10]:
            print(f"  {sig}")
    
    return cache_signals, axi_signals

def extract_timing_info(vcd_file):
    """Extract basic timing information from VCD"""
    print(f"\n=== Timing Analysis ===")
    
    try:
        # Use grep to find timestamp patterns
        result = subprocess.run(['grep', '-E', '^#[0-9]+', vcd_file], 
                              capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            timestamps = []
            for line in result.stdout.split('\n')[:1000]:  # First 1000 timestamps
                if line.startswith('#'):
                    try:
                        ts = int(line[1:])
                        timestamps.append(ts)
                    except ValueError:
                        continue
            
            if timestamps:
                total_time = max(timestamps) - min(timestamps)
                print(f"Simulation time span: {min(timestamps)} to {max(timestamps)}")
                print(f"Total simulation time: {total_time} time units")
                print(f"Number of timestamp entries (sampled): {len(timestamps)}")
                
                # Estimate cycles (assuming 2 time units per cycle)
                cycles = total_time // 2
                print(f"Estimated cycles: {cycles}")
                
                return cycles
                
    except subprocess.TimeoutExpired:
        print("Timeout while extracting timing info")
    except Exception as e:
        print(f"Error extracting timing: {e}")
    
    return None

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 analyze_vcd.py <vcd_file>")
        sys.exit(1)
    
    vcd_file = sys.argv[1]
    if not Path(vcd_file).exists():
        print(f"VCD file not found: {vcd_file}")
        sys.exit(1)
    
    # Analyze VCD structure
    cache_signals, axi_signals = analyze_vcd_header(vcd_file)
    
    # Extract timing information
    cycles = extract_timing_info(vcd_file)
    
    # Provide analysis summary
    print(f"\n=== Analysis Summary ===")
    print(f"VCD file: {vcd_file}")
    if cycles:
        print(f"Estimated cycles: {cycles:,}")
        if cycles > 100000:
            print("⚠️  HIGH CYCLE COUNT - Performance issue detected")
        else:
            print("✅ Normal cycle count")
    
    print(f"Cache signals available: {len(cache_signals)}")
    print(f"AXI signals available: {len(axi_signals)}")
    
    # Suggest next steps
    print(f"\n=== Suggested Investigation ===")
    print("1. Open in GTKWave to visually inspect cache behavior:")
    print(f"   gtkwave {vcd_file}")
    print("2. Focus on these signal groups:")
    print("   - Cache miss/hit signals")
    print("   - AXI read/write requests")
    print("   - Memory access patterns")
    print("   - Cache replacement activity")

if __name__ == "__main__":
    main()