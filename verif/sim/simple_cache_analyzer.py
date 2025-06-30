#!/usr/bin/env python3
"""
Simple VCD Analysis for Cache Performance Issues
Using basic VCD parsing to identify the 463x slowdown in fully associative cache
"""

import sys
import os
import time

# Add vcd_parsealyze to path
sys.path.append('/home/cai/cache_project/sandbox/cva6/tools/vcd_parsealyze')

import vcd

class SimpleCacheTracker(vcd.VCDTracker):
    """Simple tracker to count cache and memory activity"""
    
    def __init__(self):
        super().__init__()
        self.cycle_count = 0
        self.signal_activity = 0
        self.axi_activity = 0
        self.cache_activity = 0
        self.last_timestamp = 0
        self.sample_count = 0
        
    def start(self):
        print("Starting cache activity tracking...")
        
    def update(self):
        # Count basic activity
        self.sample_count += 1
        current_time = self.parser.now
        
        # Count cycles (assuming 2 time units per cycle)
        if current_time > self.last_timestamp:
            self.cycle_count = current_time // 2
            self.last_timestamp = current_time
            
        # Count signal activity in current sample
        activity_this_sample = 0
        
        # Check for any signal changes (simplified)
        for signal_id in self.parser.scope.children:
            if hasattr(self.parser.scope.children[signal_id], 'value'):
                activity_this_sample += 1
                
        self.signal_activity += activity_this_sample
        
        # Report progress every 10000 samples
        if self.sample_count % 10000 == 0:
            print(f"Progress: {self.cycle_count:,} cycles, {self.sample_count:,} samples, "
                  f"avg activity: {self.signal_activity/self.sample_count:.1f}")

class SimpleCacheWatcher(vcd.VCDWatcher):
    """Simple watcher for cache signals"""
    
    def __init__(self, parser, name):
        self.name = name
        self.tracker = SimpleCacheTracker()
        
        # Basic clock/reset sensitivity
        super().__init__(
            parser,
            sensitive=["*clk*", "*rst*"],  # Generic clock/reset patterns
            watch=["*"],  # Watch all signals (simplified)
            trackers=[self.tracker]
        )
        
    def should_notify(self):
        # Notify on any activity for maximum signal capture
        return True

def analyze_vcd_simple(vcd_file, name, time_limit=None):
    """Simple VCD analysis focused on timing and activity patterns"""
    print(f"\n=== Analyzing {name} ===")
    print(f"File: {vcd_file}")
    
    file_size_mb = os.path.getsize(vcd_file) / (1024 * 1024)
    print(f"VCD size: {file_size_mb:.1f} MB")
    
    # Use basic timestamp extraction for reliable cycle counting
    print("Extracting timing information...")
    
    try:
        # Quick timestamp analysis using grep
        import subprocess
        result = subprocess.run(['grep', '-E', '^#[0-9]+', vcd_file], 
                              capture_output=True, text=True, timeout=60)
        
        if result.returncode == 0:
            timestamps = []
            lines = result.stdout.split('\n')
            
            # Sample timestamps (not all for performance)
            for i, line in enumerate(lines):
                if line.startswith('#') and i % 100 == 0:  # Sample every 100th
                    try:
                        ts = int(line[1:])
                        timestamps.append(ts)
                    except ValueError:
                        continue
                        
            if timestamps:
                total_time = max(timestamps) - min(timestamps)
                cycles = total_time // 2
                
                print(f"Time range: {min(timestamps)} to {max(timestamps)}")
                print(f"Total cycles: {cycles:,}")
                print(f"Timestamp samples: {len(timestamps):,}")
                print(f"MB per 1000 cycles: {(file_size_mb * 1000 / cycles):.2f}")
                
                return {
                    'name': name,
                    'file_size_mb': file_size_mb,
                    'cycles': cycles,
                    'timestamp_samples': len(timestamps)
                }
                
    except Exception as e:
        print(f"Error in timestamp analysis: {e}")
        
    # Fallback: Try VCD parsing with limit
    try:
        print("Attempting VCD parsing...")
        parser = vcd.VCDParser()
        watcher = SimpleCacheWatcher(parser, name)
        
        start_time = time.time()
        
        with open(vcd_file, 'r') as f:
            # Read limited portion for large files
            if file_size_mb > 500:  # Limit parsing for large files
                print("Large file detected, limiting analysis...")
                content = f.read(10 * 1024 * 1024)  # Read first 10MB
                from io import StringIO
                limited_file = StringIO(content)
                parser.parse(limited_file)
            else:
                parser.parse(f)
                
        parse_time = time.time() - start_time
        print(f"VCD parsing completed in {parse_time:.1f} seconds")
        
        tracker = watcher.tracker
        return {
            'name': name,
            'file_size_mb': file_size_mb,
            'cycles': tracker.cycle_count,
            'samples': tracker.sample_count,
            'signal_activity': tracker.signal_activity
        }
        
    except Exception as e:
        print(f"VCD parsing failed: {e}")
        return None

def main():
    print("=== Simple Cache Performance Analysis ===")
    
    # VCD files
    normal_vcd = "/home/cai/cache_project/sandbox/cva6/verif/sim/out_2025-06-19/veri-testharness_sim/wt_hello_world.cv32a6_imac_sv32.vcd"
    fa_vcd = "/home/cai/cache_project/sandbox/cva6/verif/sim/out_2025-06-20/veri-testharness_sim/hello_world.cv32a6_imac_sv32.vcd"
    
    # Check files exist
    if not os.path.exists(normal_vcd):
        print(f"Normal cache VCD not found: {normal_vcd}")
        return
        
    if not os.path.exists(fa_vcd):
        print(f"Fully associative VCD not found: {fa_vcd}")
        return
    
    # Analyze normal cache
    normal_results = analyze_vcd_simple(normal_vcd, "Normal WT Cache")
    
    # Analyze fully associative cache
    fa_results = analyze_vcd_simple(fa_vcd, "Fully Associative WT_CLN")
    
    # Compare results
    if normal_results and fa_results:
        print(f"\n=== Performance Comparison ===")
        
        cycle_ratio = fa_results['cycles'] / normal_results['cycles'] if normal_results['cycles'] > 0 else 0
        size_ratio = fa_results['file_size_mb'] / normal_results['file_size_mb']
        
        print(f"{'Metric':<25} {'Normal':<15} {'Fully Assoc':<15} {'Ratio':<10}")
        print(f"{'='*70}")
        print(f"{'File size (MB)':<25} {normal_results['file_size_mb']:<15.1f} {fa_results['file_size_mb']:<15.1f} {size_ratio:<10.1f}x")
        print(f"{'Cycles':<25} {normal_results['cycles']:<15,} {fa_results['cycles']:<15,} {cycle_ratio:<10.1f}x")
        print(f"{'MB per 1K cycles':<25} {normal_results['file_size_mb']*1000/normal_results['cycles']:<15.2f} {fa_results['file_size_mb']*1000/fa_results['cycles']:<15.2f} {'-':<10}")
        
        if cycle_ratio > 100:
            print(f"\n🚨 SEVERE PERFORMANCE ISSUE CONFIRMED! 🚨")
            print(f"Fully associative cache is {cycle_ratio:.0f}x slower ({cycle_ratio:.1f}x precisely)")
            print(f"VCD file is {size_ratio:.1f}x larger")
            
            print(f"\nRoot cause investigation priorities:")
            print(f"1. Cache replacement algorithm with INDEX_WIDTH=0 (128 ways in 1 set)")
            print(f"2. Address decoding logic for fully associative mode")
            print(f"3. Infinite loops in cache miss handling")
            print(f"4. AXI protocol deadlocks or excessive retries")
            
    print(f"\n=== Recommended Actions ===")
    print(f"1. Open VCD files in GTKWave for visual inspection:")
    print(f"   gtkwave {normal_vcd}")
    print(f"   gtkwave {fa_vcd}")
    print(f"2. Compare cache behavior patterns between configurations")
    print(f"3. Focus on cache replacement and address calculation logic")

if __name__ == "__main__":
    main()