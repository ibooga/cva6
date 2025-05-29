#define CACHE_SIZE 2048  // 2KB cache
#define CACHE_LINE_SIZE 128  // 128-bit cache line = 16 bytes
#define CACHE_SETS 16   // CV32A60X has 16 cache sets
#define SET_STRIDE (CACHE_SIZE / CACHE_SETS)  // 128 bytes per set

// Arrays designed to map to different cache sets
// Each element spaced by SET_STRIDE to hit different sets
int set_test_data[CACHE_SETS * 4];  // 64 ints = 256 bytes, spans multiple sets

// Cache stress test function - designed to exercise different sets
void cache_test() {
    // PHASE 1: Initialize data across multiple cache sets
    // Each access should map to a different cache set
    for (int set = 0; set < CACHE_SETS; set++) {
        int base_idx = set * 4;  // 4 ints per set (16 bytes)
        for (int offset = 0; offset < 4; offset++) {
            set_test_data[base_idx + offset] = set * 100 + offset;
        }
    }
    
    // PHASE 2: Strided access pattern to hit all sets sequentially
    int sum = 0;
    for (int stride = 0; stride < 4; stride++) {
        for (int set = 0; set < CACHE_SETS; set++) {
            sum += set_test_data[set * 4 + stride];
        }
    }
    
    // PHASE 3: Reverse order to test replacement patterns
    for (int set = CACHE_SETS - 1; set >= 0; set--) {
        for (int offset = 3; offset >= 0; offset--) {
            set_test_data[set * 4 + offset] += sum + set;
        }
    }
    
    // PHASE 4: Cross-set conflict pattern
    // Access pattern designed to cause conflicts between sets
    for (int iteration = 0; iteration < 3; iteration++) {
        for (int set = 0; set < CACHE_SETS; set += 2) {  // Even sets
            sum += set_test_data[set * 4];
            sum += set_test_data[((set + 8) % CACHE_SETS) * 4];  // Potential conflict
        }
        for (int set = 1; set < CACHE_SETS; set += 2) {  // Odd sets
            sum += set_test_data[set * 4 + 1];
            sum += set_test_data[((set + 8) % CACHE_SETS) * 4 + 1];
        }
    }
    
    // PHASE 5: Random-like access using prime number stride
    // This should create different patterns in set-assoc vs fully-assoc modes
    for (int i = 0; i < 32; i++) {
        int idx = (i * 7) % (CACHE_SETS * 4);  // Prime stride pattern
        set_test_data[idx] = set_test_data[idx] + i;
        sum += set_test_data[idx];
    }
    
    // Store final result to prevent optimization
    set_test_data[0] = sum;
}

int main() {
    cache_test();
    
    // Calculate checksum to ensure test completed
    int checksum = 0;
    for (int i = 0; i < CACHE_SETS * 4; i++) {
        checksum += set_test_data[i];
    }
    
    // Signal success (test completed)
    return 0;
}