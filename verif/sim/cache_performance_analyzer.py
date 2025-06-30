#!/usr/bin/env python3
"""
Cache Performance Analysis using vcd_parsealyze
Focused investigation of 463x performance degradation in fully associative WT_CLN cache
"""

import sys
import os
sys.path.append('/home/cai/cache_project/sandbox/cva6/tools/vcd_parsealyze')

from vcd import VCDParser, VCDWatcher, VCDTracker
import time

class CacheActivityTracker(VCDTracker):
    """Track cache miss/hit patterns and memory requests"""
    
    def __init__(self, name):
        super().__init__()
        self.name = name
        self.cache_misses = 0
        self.cache_hits = 0
        self.memory_requests = 0
        self.axi_transactions = 0
        self.cache_stalls = 0
        self.activity_samples = []
        self.start_time = None
        self.last_activity_time = 0
        
    def start(self, watched_signals):
        """Initialize tracking"""
        self.start_time = time.time()
        print(f"[{self.name}] Starting cache activity tracking...")
        
    def update(self, timestamp, watched_signals):
        """Track cache and memory activity"""
        # Sample activity every 1000 time units
        if timestamp % 1000 == 0:
            activity_count = 0
            
            # Check for cache miss indicators
            if 'cache_miss' in watched_signals:
                if watched_signals['cache_miss'] == '1':
                    self.cache_misses += 1
                    activity_count += 1
                    
            # Check for cache hit indicators  
            if 'cache_hit' in watched_signals:
                if watched_signals['cache_hit'] == '1':
                    self.cache_hits += 1
                    
            # Check for memory requests
            if 'axi_req_valid' in watched_signals:
                if watched_signals['axi_req_valid'] == '1':
                    self.memory_requests += 1
                    activity_count += 1
                    
            # Check for AXI transactions
            if 'axi_ar_valid' in watched_signals:
                if watched_signals['axi_ar_valid'] == '1':
                    self.axi_transactions += 1
                    activity_count += 1
                    
            # Check for cache stalls
            if 'cache_stall' in watched_signals:
                if watched_signals['cache_stall'] == '1':
                    self.cache_stalls += 1
                    activity_count += 1
                    
            # Track activity density
            if activity_count > 0:
                self.activity_samples.append((timestamp, activity_count))
                self.last_activity_time = timestamp
                
            # Report progress every 100k time units
            if timestamp % 100000 == 0 and timestamp > 0:
                cycles = timestamp // 2
                print(f"[{self.name}] Progress: {cycles:,} cycles, "
                      f"misses: {self.cache_misses}, "
                      f"mem_reqs: {self.memory_requests}, "
                      f"axi_txns: {self.axi_transactions}")
                
    def get_summary(self):
        """Return analysis summary"""
        total_cycles = self.last_activity_time // 2 if self.last_activity_time else 0
        
        summary = {
            'name': self.name,
            'total_cycles': total_cycles,
            'cache_misses': self.cache_misses,
            'cache_hits': self.cache_hits,
            'memory_requests': self.memory_requests,
            'axi_transactions': self.axi_transactions,
            'cache_stalls': self.cache_stalls,
            'activity_samples': len(self.activity_samples),
            'hit_rate': self.cache_hits / (self.cache_hits + self.cache_misses) if (self.cache_hits + self.cache_misses) > 0 else 0
        }
        
        return summary

class CacheWatcher(VCDWatcher):
    """Watch cache-related signals for performance analysis"""
    
    def __init__(self, name):
        self.name = name
        self.tracker = CacheActivityTracker(name)
        
        # Define signals to watch (flexible signal names)
        self.sensitivity_list = [
            # Cache signals
            'req_i', 'gnt_o', 'data_req_i', 'data_rsp_o',
            # AXI signals
            'axi_req_o', 'axi_rsp_i', 'ar_valid', 'aw_valid', 'r_valid', 'w_valid',
            # Clock/reset
            'clk_i', 'rst_ni'
        ]
        
        self.watched_signals = self.sensitivity_list.copy()
        
        # Add tracker
        self.add_tracker(self.tracker)
        
    def update(self, timestamp, changed_signals):
        """Called when watched signals change"""
        # Create signal map for tracker
        signal_map = {}
        
        # Map actual signals to expected names
        for sig_id, value in changed_signals.items():
            # This would need actual signal mapping based on VCD content
            signal_map[sig_id] = value
            
        # Update tracker
        self.tracker.update(timestamp, signal_map)

def analyze_vcd_performance(vcd_file, name, max_time=None):
    """Analyze VCD file for cache performance issues"""
    print(f"\n=== Analyzing {name} ===")
    print(f"VCD file: {vcd_file}")
    
    # Create watcher
    watcher = CacheWatcher(name)
    
    # Create parser
    parser = VCDParser()
    parser.add_watcher(watcher)
    
    start_time = time.time()
    
    try:
        # Parse VCD file with timeout
        print(f"Parsing VCD file...")
        with open(vcd_file, 'r') as f:
            parser.parse(f, max_time=max_time)
            
    except Exception as e:
        print(f"Error parsing {name}: {e}")
        return None
        
    parse_time = time.time() - start_time
    print(f"Parsing completed in {parse_time:.1f} seconds")
    
    # Get analysis results
    summary = watcher.tracker.get_summary()
    
    print(f"\n=== {name} Analysis Results ===")
    print(f"Total cycles: {summary['total_cycles']:,}")
    print(f"Cache misses: {summary['cache_misses']:,}")
    print(f"Cache hits: {summary['cache_hits']:,}")
    print(f"Hit rate: {summary['hit_rate']:.2%}")
    print(f"Memory requests: {summary['memory_requests']:,}")
    print(f"AXI transactions: {summary['axi_transactions']:,}")
    print(f"Cache stalls: {summary['cache_stalls']:,}")
    print(f"Activity samples: {summary['activity_samples']:,}")
    
    return summary

def main():
    print("=== CVA6 Cache Performance Analysis with vcd_parsealyze ===")
    
    # VCD files to analyze
    normal_vcd = "/home/cai/cache_project/sandbox/cva6/verif/sim/out_2025-06-19/veri-testharness_sim/wt_hello_world.cv32a6_imac_sv32.vcd"
    fa_vcd = "/home/cai/cache_project/sandbox/cva6/verif/sim/out_2025-06-20/veri-testharness_sim/hello_world.cv32a6_imac_sv32.vcd"
    
    # Check files exist
    if not os.path.exists(normal_vcd):
        print(f"Normal cache VCD not found: {normal_vcd}")
        return
        
    if not os.path.exists(fa_vcd):
        print(f"Fully associative VCD not found: {fa_vcd}")
        return
    
    # Analyze normal cache first (smaller file)
    print("Analyzing normal WT cache baseline...")
    normal_summary = analyze_vcd_performance(normal_vcd, "Normal WT Cache")
    
    # Analyze fully associative cache with time limit to prevent excessive runtime
    print("\nAnalyzing fully associative WT_CLN cache (limited analysis)...")
    fa_summary = analyze_vcd_performance(fa_vcd, "Fully Associative WT_CLN", max_time=600000)  # Limit to 300k time units
    
    # Compare results
    if normal_summary and fa_summary:
        print(f"\n=== Performance Comparison ===")
        
        if normal_summary['total_cycles'] > 0 and fa_summary['total_cycles'] > 0:
            cycle_ratio = fa_summary['total_cycles'] / normal_summary['total_cycles']
            miss_ratio = fa_summary['cache_misses'] / max(normal_summary['cache_misses'], 1)
            mem_req_ratio = fa_summary['memory_requests'] / max(normal_summary['memory_requests'], 1)
            
            print(f"Cycle count ratio: {cycle_ratio:.1f}x")
            print(f"Cache miss ratio: {miss_ratio:.1f}x") 
            print(f"Memory request ratio: {mem_req_ratio:.1f}x")
            
            if cycle_ratio > 100:
                print(f"\n🚨 SEVERE PERFORMANCE DEGRADATION DETECTED! 🚨")
                print(f"Fully associative cache is {cycle_ratio:.0f}x slower")
                print(f"\nPossible root causes:")
                print(f"- Cache replacement algorithm inefficiency with 128 ways")
                print(f"- Address decoding issues with INDEX_WIDTH=0")
                print(f"- Infinite loops or excessive cache miss handling")
                print(f"- AXI protocol stalls or deadlocks")
                
    print(f"\n=== Next Steps ===")
    print(f"1. Open VCD files in GTKWave for visual analysis:")
    print(f"   gtkwave {normal_vcd} gtkwave_cache_analysis.gtkw")
    print(f"   gtkwave {fa_vcd} gtkwave_cache_analysis.gtkw")
    print(f"2. Focus on cache replacement logic and address calculation")
    print(f"3. Look for signal patterns indicating infinite loops")
    print(f"4. Examine AXI transaction timing and stalls")

if __name__ == "__main__":
    main()