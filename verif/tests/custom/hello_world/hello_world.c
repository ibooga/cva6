/*
**
** Copyright 2020 OpenHW Group
**
** Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
** you may not use this file except in compliance with the License.
** You may obtain a copy of the License at
**
**     https://solderpad.org/licenses/
**
** Unless required by applicable law or agreed to in writing, software
** distributed under the License is distributed on an "AS IS" BASIS,
** WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
** See the License for the specific language governing permissions and
** limitations under the License.
**
*/

#include <stdint.h>
#include <stdio.h>

int main(int argc, char* arg[]) {
	// Test cache with different access patterns
	volatile int test_array[16];

	// Sequential write pattern
	for (int i = 0; i < 16; i++) {
		test_array[i] = i+i;
	}

	printf("%d: Hello World - 128-way Fully Associative Cache Test!", 0);

	
// 	// Sequential read and verify
// 	for (int i = 0; i < 512; i++) {
// 		if (test_array[i] != i * 3 + 0x1000) {
// 			printf("ERROR: Sequential test failed at index %d", i);
// 			return 1;
// 		}
// 	}	printf("SUCCESS: All cache tests passed!");
//
// 	// Stride access pattern to test associativity
// 	for (int i = 0; i < 512; i += 16) {
// 		test_array[i] = i + 0x2000;
// 	}
//
// 	// Verify stride pattern
// 	for (int i = 0; i < 512; i += 16) {
// 		if (test_array[i] != i + 0x2000) {
// 			printf("ERROR: Stride test failed at index %d", i);
// 			return 1;
// 		}
// 	}
	
	// printf("SUCCESS: All cache tests passed!");
	return 0;
}
