/*
 * Cache Block Sweep Test - Exercise Maximum Blocks Efficiently
 * 
 * Optimized for: Maximum cache block exercise, minimum execution time
 * Strategy: Strategic access pattern to hit all 16 sets + exceed FA capacity
 */

#include <stdlib.h>

// Target: Hit all 16 cache sets + overflow FA lookup table (8 entries)
volatile int sweep_data[256];  // 1KB array, sufficient to hit all sets

int main() {
    int result = 0;
    
    // SWEEP 1: Hit all 16 cache sets sequentially
    // Each access is 64 bytes apart (4 cache lines) to ensure different sets
    for (int i = 0; i < 16; i++) {
        sweep_data[i * 16] = i;           // Write to each set
        result += sweep_data[i * 16];     // Read from each set
    }
    
    // SWEEP 2: Overflow FA lookup table (>8 unique addresses)
    // Use prime stride (17) to create distributed access pattern
    for (int i = 0; i < 12; i++) {       // 12 > 8 (FA limit)
        int idx = (i * 17) % 256;
        sweep_data[idx] = idx;
        result += sweep_data[idx];
    }
    
    // SWEEP 3: Mixed access - combine set conflicts + FA overflow
    for (int i = 0; i < 8; i++) {
        sweep_data[i] = i;                // Low addresses  
        sweep_data[i + 128] = i + 128;    // High addresses (different sets)
        result += sweep_data[i] + sweep_data[i + 128];
    }
    
    // Ensure successful completion by calling exit(0)
    exit(0);
    return 0;  // Should never reach here
}