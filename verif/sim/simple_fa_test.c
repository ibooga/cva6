// Simple fully associative cache test
// Exit with code 0 for success, 1 for failure

#define TOHOST_ADDR 0x80001000

static inline void write_tohost(int value) {
    volatile int *tohost = (volatile int *) TOHOST_ADDR;
    *tohost = value;
}

int main() {
    // Test different memory access patterns to stress the cache
    volatile int test_data[1024];
    
    // Sequential write pattern
    for (int i = 0; i < 1024; i++) {
        test_data[i] = i + 0x1000;
    }
    
    // Sequential read and verify
    for (int i = 0; i < 1024; i++) {
        if (test_data[i] != i + 0x1000) {
            write_tohost(1); // Test failed
            return 1;
        }
    }
    
    // Stride pattern to test associativity
    for (int i = 0; i < 1024; i += 8) {
        test_data[i] = i + 0x2000;
    }
    
    // Verify stride pattern
    for (int i = 0; i < 1024; i += 8) {
        if (test_data[i] != i + 0x2000) {
            write_tohost(1); // Test failed
            return 1;
        }
    }
    
    // Random access pattern
    test_data[0] = 0xDEADBEEF;
    test_data[100] = 0xCAFEBABE;
    test_data[500] = 0x12345678;
    test_data[1023] = 0x87654321;
    
    // Verify random access
    if (test_data[0] != 0xDEADBEEF ||
        test_data[100] != 0xCAFEBABE ||
        test_data[500] != 0x12345678 ||
        test_data[1023] != 0x87654321) {
        write_tohost(1); // Test failed
        return 1;
    }
    
    write_tohost(1); // Test passed!
    return 0;
}