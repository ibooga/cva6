#include <stdio.h>
#include <stdlib.h>

int main() {
    printf("Hello World! Testing 128-way fully associative cache.\n");
    
    // Simple test to stress the cache
    volatile int *test_array = (volatile int*)malloc(8192 * sizeof(int));
    if (test_array == NULL) {
        printf("ERROR: Memory allocation failed!\n");
        return 1;
    }
    
    // Write pattern to memory
    for (int i = 0; i < 8192; i++) {
        test_array[i] = i * 2;
    }
    
    // Read back and verify pattern
    for (int i = 0; i < 8192; i++) {
        if (test_array[i] != i * 2) {
            printf("ERROR: Memory verification failed at index %d! Expected %d, got %d\n", 
                   i, i * 2, test_array[i]);
            return 1;
        }
    }
    
    printf("Cache test PASSED! All memory operations completed successfully.\n");
    return 0;
}