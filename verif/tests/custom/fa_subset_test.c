#include <stdint.h>
#include "env/encoding.h"

#define SET_STRIDE 16  // 16 ints = 64 bytes between sets

volatile uint32_t fa_data[256];

int main() {
    // Configure mhpmcounter3 to track L1 D-cache misses (event id 2)
    write_csr(mhpmevent3, 2);
    write_csr(mhpmcounter3, 0);

    // Access 8 unique cache lines (within FA capacity)
    for (int i = 0; i < 8; i++) {
        fa_data[i * SET_STRIDE] = i;
    }

    uint32_t misses_first = read_csr(mhpmcounter3);
    if (misses_first != 8) {
        return 1; // expect one miss per line
    }

    // Access 16 unique lines spanning all sets
    write_csr(mhpmcounter3, 0);
    for (int i = 0; i < 16; i++) {
        fa_data[i * SET_STRIDE] += 1;
    }

    uint32_t misses_second = read_csr(mhpmcounter3);
    // Only the first 8 lines should hit, remaining should miss
    if (misses_second <= 8) {
        return 2;
    }

    return 0;
}
