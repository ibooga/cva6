#\!/bin/bash
make clean
make verilate target=cv32a6_imac_sv32
# Compile hello_world 
$CVA6_REPO_DIR/tools/riscv_toolchain/bin/riscv-none-elf-gcc ../tests/custom/hello_world/hello_world.c \
    -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -g \
    ../tests/custom/common/syscalls.c ../tests/custom/common/crt.S \
    -lgcc -T../tests/custom/common/test.ld -o hello_world.elf
# Run test  
timeout 300 ./work-ver/Variane_testharness +permissive-off hello_world.elf

