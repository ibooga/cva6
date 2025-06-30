// Simple test program to exercise the WT_CLN cache
int main() {
    // Simple loop that will exercise cache
    volatile int sum = 0;
    for (int i = 0; i < 1000; i++) {
        sum += i;
    }
    return sum;
}