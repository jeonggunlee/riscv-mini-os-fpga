RTL := rtl/rv32_alu.v rtl/rv32_regfile.v rtl/rv32_csr.v rtl/rv32_core.v rtl/simple_timer.v rtl/rv32_soc.v rtl/uart_rx.v
CROSS ?= riscv64-unknown-elf
RISCV_GCC := $(CROSS)-gcc
RISCV_OBJCOPY := $(CROSS)-objcopy
RISCV_OBJDUMP := $(CROSS)-objdump
PYTHON ?= python3

FW_NAME := nexys_hello
FW_BUILD := build/firmware
FW_ELF := $(FW_BUILD)/$(FW_NAME).elf
FW_BIN := $(FW_BUILD)/$(FW_NAME).bin
FW_HEX := firmware/$(FW_NAME).hex
C_DEMO_NAME := c_demo
C_DEMO_ASM := $(FW_BUILD)/$(C_DEMO_NAME).s
C_DEMO_ELF := $(FW_BUILD)/$(C_DEMO_NAME).elf
C_DEMO_BIN := $(FW_BUILD)/$(C_DEMO_NAME).bin
C_DEMO_HEX := firmware/$(C_DEMO_NAME).hex
C_DEMO_DIS := $(FW_BUILD)/$(C_DEMO_NAME).dis
CFLAGS_RV32I := -march=rv32i -mabi=ilp32 -O1 -ffreestanding -fno-builtin \
	-fno-pic -fno-asynchronous-unwind-tables -msmall-data-limit=0

.PHONY: all firmware firmware-disasm c-demo c-demo-disasm mini-os mini-os-disasm sim sim-c-demo sim-mini-os lint vivado manual-pdf clean

all: firmware

firmware: $(FW_HEX)

$(FW_BUILD):
	mkdir -p $@

$(FW_ELF): firmware/$(FW_NAME).S firmware/linker.ld | $(FW_BUILD)
	$(RISCV_GCC) -march=rv32i -mabi=ilp32 -mno-relax \
		-nostdlib -nostartfiles -Wl,--build-id=none,--no-relax \
		-T firmware/linker.ld -o $@ $<

$(FW_BIN): $(FW_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(FW_HEX): $(FW_BIN) scripts/bin2hex.py
	$(PYTHON) scripts/bin2hex.py --max-bytes 8192 $< $@

firmware-disasm: $(FW_ELF)
	$(RISCV_OBJDUMP) -d -M no-aliases,numeric $(FW_ELF)

# C -> compiler-generated assembly -> ELF -> raw binary -> $readmemh HEX.
c-demo: $(C_DEMO_ASM) $(C_DEMO_HEX) $(C_DEMO_DIS)

$(C_DEMO_ASM): firmware/$(C_DEMO_NAME).c | $(FW_BUILD)
	$(RISCV_GCC) $(CFLAGS_RV32I) -S -o $@ $<

$(C_DEMO_ELF): $(C_DEMO_ASM) firmware/linker.ld | $(FW_BUILD)
	$(RISCV_GCC) -march=rv32i -mabi=ilp32 -mno-relax \
		-nostdlib -nostartfiles -Wl,--build-id=none,--no-relax \
		-Wl,-Map=$(FW_BUILD)/$(C_DEMO_NAME).map \
		-T firmware/linker.ld -o $@ $<

$(C_DEMO_BIN): $(C_DEMO_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(C_DEMO_HEX): $(C_DEMO_BIN) scripts/bin2hex.py
	$(PYTHON) scripts/bin2hex.py --max-bytes 8192 $< $@

$(C_DEMO_DIS): $(C_DEMO_ELF)
	$(RISCV_OBJDUMP) -d -S -M no-aliases,numeric $< > $@

c-demo-disasm: $(C_DEMO_DIS)
	cat $(C_DEMO_DIS)

sim:
	mkdir -p build
	iverilog -g2012 -Wall -o build/tb_core $(RTL) tb/tb_rv32_core.v
	vvp build/tb_core

sim-c-demo: c-demo
	bash scripts/run_c_demo_sim.sh

lint:
	verilator --lint-only -Wall --top-module rv32_soc $(RTL)

vivado: firmware
	vivado -mode batch -source scripts/build_nexys_a7.tcl

clean:
	rm -rf build

# Mini OS: boot.S + trap.S + kernel.c -> ELF -> raw binary -> $readmemh HEX.
# Two images share the sources and differ only in the timer period:
#   firmware/mini_os.hex            FPGA, MINI_OS_TICK cycles (10 ms at 12.5 MHz)
#   build/firmware/mini_os_sim.hex  simulation, MINI_OS_SIM_TICK cycles
MINI_OS_NAME := mini_os
MINI_OS_SRCS := firmware/boot.S firmware/trap.S firmware/kernel.c firmware/minifs.c
MINI_OS_TICK ?= 125000
MINI_OS_SIM_TICK ?= 2000
MINI_OS_ELF := $(FW_BUILD)/$(MINI_OS_NAME).elf
MINI_OS_BIN := $(FW_BUILD)/$(MINI_OS_NAME).bin
MINI_OS_HEX := firmware/$(MINI_OS_NAME).hex
MINI_OS_DIS := $(FW_BUILD)/$(MINI_OS_NAME).dis
MINI_OS_SIM_ELF := $(FW_BUILD)/$(MINI_OS_NAME)_sim.elf
MINI_OS_SIM_BIN := $(FW_BUILD)/$(MINI_OS_NAME)_sim.bin
MINI_OS_SIM_HEX := $(FW_BUILD)/$(MINI_OS_NAME)_sim.hex
MINI_OS_LDFLAGS := -mno-relax -nostdlib -nostartfiles \
	-Wl,--build-id=none,--no-relax -T firmware/linker.ld

mini-os: $(MINI_OS_HEX) $(MINI_OS_DIS)

$(MINI_OS_ELF): $(MINI_OS_SRCS) firmware/minifs.h firmware/linker.ld | $(FW_BUILD)
	$(RISCV_GCC) $(CFLAGS_RV32I) -DTICK_CYCLES=$(MINI_OS_TICK)u $(MINI_OS_LDFLAGS) \
		-Wl,-Map=$(FW_BUILD)/$(MINI_OS_NAME).map -o $@ $(MINI_OS_SRCS)

$(MINI_OS_SIM_ELF): $(MINI_OS_SRCS) firmware/minifs.h firmware/linker.ld | $(FW_BUILD)
	$(RISCV_GCC) $(CFLAGS_RV32I) -DTICK_CYCLES=$(MINI_OS_SIM_TICK)u $(MINI_OS_LDFLAGS) \
		-Wl,-Map=$(FW_BUILD)/$(MINI_OS_NAME)_sim.map -o $@ $(MINI_OS_SRCS)

$(MINI_OS_BIN): $(MINI_OS_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(MINI_OS_SIM_BIN): $(MINI_OS_SIM_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(MINI_OS_HEX): $(MINI_OS_BIN) scripts/bin2hex.py
	$(PYTHON) scripts/bin2hex.py --max-bytes 8192 $< $@

$(MINI_OS_SIM_HEX): $(MINI_OS_SIM_BIN) scripts/bin2hex.py
	$(PYTHON) scripts/bin2hex.py --max-bytes 8192 $< $@

$(MINI_OS_DIS): $(MINI_OS_ELF)
	$(RISCV_OBJDUMP) -d -M no-aliases,numeric $< > $@

mini-os-disasm: $(MINI_OS_DIS)
	cat $(MINI_OS_DIS)

sim-mini-os: $(MINI_OS_SIM_HEX)
	bash scripts/run_mini_os_sim.sh

# docs/MANUAL.md -> docs/MANUAL.pdf (Python-Markdown + headless Chrome + PyMuPDF).
manual-pdf:
	$(PYTHON) scripts/build_manual_pdf.py

.PHONY: shell-guide-pdf
shell-guide-pdf:
	$(PYTHON) scripts/build_manual_pdf.py --md docs/SHELL_BINARY_GUIDE.md \
		--pdf docs/SHELL_BINARY_GUIDE.pdf \
		--subtitle "확장판 · RV32I ISA와 데이터패스 · SHELL_MODE · UART · syscall · MiniFS · 앱 실행" \
		--board "AMD ZCU104 (xczu7ev-ffvc1156-2-e), PL RISC-V 12.5 MHz" \
		--toolchain "RISC-V GNU Toolchain (-march=rv32i -mabi=ilp32), Vivado, Icarus Verilog" \
		--footer-title "RISC-V Mini Shell과 바이너리 실행"

# ZCU104 keeps the same 12.5 MHz CPU/timer clock as Nexys A7.
# Force firmware compilation here so TICK_CYCLES cannot be stale after a
# previous make invocation with a different MINI_OS_TICK value.
.PHONY: vivado-zcu104 program-zcu104 sim-zcu104 test-zcu104
vivado-zcu104:
	$(MAKE) -B mini-os MINI_OS_TICK=125000
	mkdir -p build/zcu104
	vivado -mode batch -nojournal -log build/zcu104/build.log -source scripts/build_zcu104.tcl

program-zcu104:
	vivado -mode batch -nojournal -log build/zcu104/program.log -source scripts/program_zcu104.tcl

sim-zcu104: $(MINI_OS_SIM_HEX)
	bash scripts/run_zcu104_sim.sh

# Opens UART before programming so the boot banner is not missed.
test-zcu104:
	$(PYTHON) scripts/test_zcu104_uart.py --program

# Interactive shell image: 32 KiB program RAM, reserved app window, UART RX.
SHELL_ELF := $(FW_BUILD)/mini_shell.elf
SHELL_BIN := $(FW_BUILD)/mini_shell.bin
SHELL_HEX := firmware/mini_shell.hex
SHELL_SIM_ELF := $(FW_BUILD)/mini_shell_sim.elf
SHELL_SIM_BIN := $(FW_BUILD)/mini_shell_sim.bin
SHELL_SIM_HEX := $(FW_BUILD)/mini_shell_sim.hex
.PHONY: mini-shell sim-shell vivado-zcu104-shell program-zcu104-shell test-zcu104-shell

APP_ELF := $(FW_BUILD)/hello_app.elf
APP_BIN := $(FW_BUILD)/hello_app.bin
APP_HEX := $(FW_BUILD)/hello_app.hex
.PHONY: hello-app

$(APP_ELF): firmware/hello_app.c firmware/app.ld | $(FW_BUILD)
	$(RISCV_GCC) $(CFLAGS_RV32I) -mno-relax -nostdlib -nostartfiles \
		-Wl,--build-id=none,--no-relax -T firmware/app.ld -o $@ firmware/hello_app.c

$(APP_BIN): $(APP_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(APP_HEX): $(APP_BIN) scripts/bin2hex.py
	$(PYTHON) scripts/bin2hex.py --max-bytes 8192 $< $@

hello-app: $(APP_BIN) $(APP_HEX)

$(SHELL_ELF): $(MINI_OS_SRCS) firmware/minifs.h firmware/linker_shell.ld | $(FW_BUILD)
	$(RISCV_GCC) $(CFLAGS_RV32I) -DSHELL_MODE -DTICK_CYCLES=125000u \
		-mno-relax -nostdlib -nostartfiles -Wl,--build-id=none,--no-relax \
		-T firmware/linker_shell.ld -o $@ $(MINI_OS_SRCS)

$(SHELL_SIM_ELF): $(MINI_OS_SRCS) firmware/minifs.h firmware/linker_shell.ld | $(FW_BUILD)
	$(RISCV_GCC) $(CFLAGS_RV32I) -DSHELL_MODE -DTICK_CYCLES=2000u \
		-mno-relax -nostdlib -nostartfiles -Wl,--build-id=none,--no-relax \
		-T firmware/linker_shell.ld -o $@ $(MINI_OS_SRCS)

$(SHELL_BIN): $(SHELL_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(SHELL_SIM_BIN): $(SHELL_SIM_ELF)
	$(RISCV_OBJCOPY) -O binary $< $@

$(SHELL_HEX): $(SHELL_BIN) scripts/bin2hex.py
	$(PYTHON) scripts/bin2hex.py --max-bytes 32768 $< $@

$(SHELL_SIM_HEX): $(SHELL_SIM_BIN) scripts/bin2hex.py
	$(PYTHON) scripts/bin2hex.py --max-bytes 32768 $< $@

mini-shell: $(SHELL_HEX)

sim-shell: $(SHELL_SIM_HEX) $(APP_HEX)
	bash scripts/run_shell_sim.sh

vivado-zcu104-shell:
	$(MAKE) -B mini-shell
	mkdir -p build/zcu104_shell
	SHELL_BUILD=1 vivado -mode batch -nojournal -log build/zcu104_shell/build.log -source scripts/build_zcu104.tcl

program-zcu104-shell:
	SHELL_BUILD=1 vivado -mode batch -nojournal -log build/zcu104_shell/program.log -source scripts/program_zcu104.tcl

test-zcu104-shell:
	$(PYTHON) scripts/test_zcu104_shell.py --program

.PHONY: test-zcu104-app
test-zcu104-app: hello-app
	$(MAKE) test-zcu104-shell
	$(PYTHON) scripts/upload_app.py --file $(APP_BIN) --name hello.app --run
