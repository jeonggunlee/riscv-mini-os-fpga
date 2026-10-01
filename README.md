# Single-cycle RV32I SoC

**ZCU104 지원:** `make vivado-zcu104`로 Mini OS 비트스트림을 생성하고,
`make test-zcu104`로 PL 다운로드 및 실제 USB UART 출력을 검사합니다.
핀, 클럭, 테스트, 제한 사항은 [ZCU104 실행 안내](docs/ZCU104.md)를 참고하세요.
입력 가능한 Mini Shell은 별도 이미지로 `make vivado-zcu104-shell`,
`make test-zcu104-shell`을 사용합니다.
고정 주소 RV32I 앱을 MiniFS에 업로드해 `run`으로 실행하는 최소 버전은
[앱 로더 안내](docs/APP_LOADER.md)를 참고하세요.
Shell mode와 바이너리 실행을 프로세서·OS 관점에서 학습하는 교재는
[상세 기술 문서](docs/SHELL_BINARY_GUIDE.md) / [인쇄용 PDF](docs/SHELL_BINARY_GUIDE.pdf)에 있습니다.
현재 코어의 46개 명령·데이터패스·CSR, 실제 실행 추적, 메모리·스택 배치,
실습 절차, 연습문제 35개와 해설을 포함하며
`make shell-guide-pdf`로 PDF를 다시 생성합니다.

교육용으로 만든 합성 가능한 단일 사이클 RISC-V 코어입니다. 벤더 IP 없이 작성했으며,
코어와 보드 구성 기준 8 KiB 프로그램/데이터 RAM, 8 KiB RAM disk,
UART 출력 레지스터, timer를 포함합니다.

## 구성

- `rtl/rv32_core.v`: RV32I 단일 사이클 데이터패스/제어
- `rtl/rv32_regfile.v`, `rtl/rv32_alu.v`: 레지스터 파일과 ALU
- `rtl/rv32_csr.v`: M-mode 최소 CSR와 trap/`mret`
- `rtl/rv32_soc.v`: 메모리와 MMIO를 연결한 예제 SoC
- `rtl/simple_timer.v`: `mtime`/`mtimecmp` 기반 timer interrupt
- `tb/tb_rv32_core.v`: 산술, RAM, branch, UART smoke test
- `firmware/boot.S`, `firmware/trap.S`, `firmware/kernel.c`: timer 선점 round-robin mini OS
- `firmware/minifs.c`, `firmware/minifs.h`: RAM disk 기반 MiniFS
- `docs/MINIFS.md`: 디스크 형식, API, syscall, 제한 사항
- `docs/MANUAL.md` / `docs/MANUAL.pdf`: 개념부터 RTL, toolchain, 스크립트, mini OS까지의 상세 매뉴얼 (`make manual-pdf`로 PDF 재생성)

지원 범위는 RV32I 정수 명령, `FENCE`(NOP 취급), CSR 명령, `ECALL`, `MRET`,
machine timer interrupt입니다. 압축 명령, 원자적 명령, MMU, U-mode는 지원하지
않습니다. 메모리 접근과 명령어는 자연 정렬된다고 가정합니다.
정렬 위반 trap, `EBREAK`, 접근 오류 trap은 이 첫 버전에는 포함하지 않았습니다.

## 메모리 맵

| 주소 | 기능 |
|---|---|
| `0x0000_0000`–`0x0000_1FFF` | Mini OS 프로그램/데이터 RAM (8 KiB); Mini Shell 이미지는 `0x7FFF`까지 32 KiB |
| `0x1000_0000` | UART TX, 하위 8비트 쓰기 |
| `0x1000_0004` | UART TX ready, bit 0 읽기 |
| `0x1000_1000` | `mtime` 하위 32비트 |
| `0x1000_1004` | `mtimecmp` 하위 32비트 |
| `0x8010_0000`–`0x8010_1FFF` | MiniFS RAM disk (8 KiB) |

## 시뮬레이션

Icarus Verilog가 설치되어 있다면 `make sim`, Verilator가 있다면 `make lint`를
실행합니다. 현재 환경에 도구가 없다면 Ubuntu 계열에서 `iverilog` 또는
`verilator` 패키지를 설치하면 됩니다.

FPGA에서는 `rv32_soc`의 `uart_tx_valid/data`를 실제 UART 송신기 모듈에 연결하고,
보드 clock/reset에 맞춘 top module과 핀 제약 파일을 추가해야 합니다. `MEM_HEX`
parameter로 `$readmemh` 형식의 펌웨어 이미지를 초기화할 수 있습니다.

## Nexys A7-100T

`nexys_a7_top`은 보드의 100 MHz clock으로 UART를 구동하고, single-cycle CPU는
BUFG를 거친 12.5 MHz clock으로 구동합니다. USB-UART는 115200-8-N-1입니다.
CPU reset 버튼은 `CPU_RESETN`, 실행 PC 일부는 16개 LED에 표시됩니다.

```bash
make firmware
make vivado
vivado -mode batch -source scripts/program_nexys_a7.tcl
```

`make firmware`는 `riscv64-unknown-elf-gcc`로 RV32I ELF를 링크하고,
`objcopy`로 raw binary를 만든 다음 `scripts/bin2hex.py`로 little-endian 32-bit
`$readmemh` 파일을 생성합니다. 생성 중간 파일은 `build/firmware`에 있습니다.
역어셈블 결과는 `make firmware-disasm`으로 확인할 수 있습니다.

### C firmware end-to-end 예제

`firmware/c_demo.c`는 1부터 10까지 더한 결과 55를 RAM `0x400`에 기록하고
UART로 `C OK\n`을 출력하는 freestanding C 프로그램입니다. 다음 명령은 C에서
assembly, ELF, binary, HEX를 차례로 만든 뒤 그 HEX를 실제 `rv32_soc`에 적재하여
시뮬레이션합니다.

```bash
make c-demo
make c-demo-disasm
make sim-c-demo
```

생성된 compiler assembly와 disassembly는 각각 `build/firmware/c_demo.s`,
`build/firmware/c_demo.dis`에 있습니다. 시뮬레이션은 RAM signature와 UART의
5개 byte를 자동 검사합니다.

생성 bitstream은 `build/vivado/nexys_a7_rv32i.bit`입니다. USB-UART 터미널을
115200 baud로 열면 `Hello Nexys A7!`가 출력됩니다. Vivado Hardware Manager가
보드를 찾지 못하면 JTAG USB 연결과 보드 전원을 확인하십시오.

Vivado 2022.1, `xc7a100tcsg324-1`로 구현 검증했으며 최종 WNS는 3.850 ns,
WHS는 0.139 ns입니다. Slice LUT 4,614개(7.28%), register 1,372개(1.08%)를
사용합니다. 조합식 2-port 메모리 때문에 8 KiB RAM은 block RAM이 아니라
distributed RAM으로 구현됩니다.

> 주의: 이 구조는 학습용 single-cycle 설계라서 instruction/data read가 조합식입니다.
> 동기식 FPGA BRAM을 효율적으로 쓰려면 이후 multi-cycle 또는 pipeline 구조로 바꾸는
> 것이 좋습니다.

### Mini OS (preemptive round-robin)

`firmware/boot.S`, `firmware/trap.S`, `firmware/kernel.c`는 이 SoC의 timer
interrupt와 `ECALL`/`MRET` 위에서 도는 최소 OS입니다. `boot.S`가 스택과 `.bss`,
`mtvec`를 준비하고, `trap.S`가 x1–x31과 `mepc`를 중단된 task의 스택에 128-byte
frame으로 저장한 뒤 `trap_handler()`가 돌려준 frame으로 `sp`를 바꿔 복원합니다
(이 한 줄이 context switch). `kernel.c`는 `mtimecmp`를 재설정하고 idle, A, B, C 네
슬롯을 round-robin으로 돌리며 `ecall`(a7 = 번호)로 `putc`/`yield`/`gettick`
syscall을 제공합니다. MiniFS용 `create`/`write`/`read`/`delete`/`list`
서비스도 추가되었습니다. task A/B는 선점될 때까지 문자를 출력하고 task C는
MiniFS 생성·기록·읽기·삭제 데모를 마친 후 한 글자씩 출력하며 `yield`합니다.

```bash
make mini-os        # firmware/mini_os.hex (TICK_CYCLES=125000, 12.5 MHz에서 10 ms)
make sim-mini-os    # 짧은 tick 이미지로 RTL 시뮬레이션, build/mini_os.vcd 생성
```

시뮬레이션은 UART 부팅 메시지, MiniFS 데모 완료, A/B/C 스케줄링, timer IRQ와
예상 밖 trap 0회를 확인하고 PASS를 출력합니다. FPGA에서
실행하려면 `nexys_a7_top.v`의 `MEM_HEX`를 `firmware/mini_os.hex`로 바꾸고
재합성합니다. timer MMIO가 하위 32비트만 노출하므로 약 343초 후에는 reset이
필요합니다.

## Web slide

오늘 구현한 CPU, SoC, Nexys A7 연결, C/assembly/HEX 변환, VCD 검증, firmware
toolchain 및 Vivado 결과를 단계별로 설명하는 42장 발표 자료는 `slides/index.html`에
있습니다. 브라우저에서 직접 열거나 다음처럼
로컬 서버를 실행합니다.

```bash
python3 -m http.server 8000 --directory slides
```

그 후 `http://localhost:8000`을 엽니다. `./start.sh` / `./stop.sh`로 서버를 시작하거나
종료할 수도 있습니다. 이미 열려 있다면 새로고침해 최신 내용을 읽습니다.

- 방향키·Page Up/Down·Space: 슬라이드 이동
- `O`: 전체 목차, `Escape`: 목차/해설 닫기
- `N` 또는 **해설**: 현재 페이지의 상세 설명
- `R` 또는 **읽기**: 모든 슬라이드와 해설을 연속 문서로 표시
- `P`: 인쇄/PDF 저장. 읽기 모드에서 인쇄하면 해설도 포함

각 페이지는 코드와 실제 산출물에 근거한 해설을 포함합니다. 반복문 단계 실행 페이지는
ADD → ADDI → 주소 복원 → LW → BGEU → 최종 SW를 버튼으로 추적하는 교육용 모델입니다.
RTL 시뮬레이션 자체는 `make sim-c-demo`로 실행합니다.

상세 설명 및 추가 페이지는 `slides/lessons.js`, 관련 레이아웃은 `slides/lessons.css`에
있습니다. 외부 라이브러리나 서버 API 없이 로컬 파일로도 사용할 수 있습니다.
시뮬레이션용 `c_demo.hex`와 FPGA 기본 이미지 `nexys_hello.hex`의 차이도 명시했습니다.
