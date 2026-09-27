/* Local teaching content: no network dependency. Snippets describe this repository. */
(() => {
  const escape = text => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
  const code = text => `<pre class="code-panel"><code>${escape(text)}</code></pre>`;
  const table = (heads, rows) => `<table class="lesson-table"><thead><tr>${heads.map(h => `<th>${h}</th>`).join('')}</tr></thead><tbody>${rows.map(row => `<tr>${row.map(cell => `<td>${cell}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
  const pair = (left, right) => `<div class="detail-pair">${left}<div class="lesson-prose">${right}</div></div>`;
  const lessons = [
    {
      before: '목표와 결과', title: '학습 순서', heading: '코드와 파형을 연결하는 여섯 가지 질문',
      body: table(['순서', '질문', '확인할 파일 / 증거'], [
        ['1 · 구조', '어떤 상태를 저장하고 언제 변경하는가?', 'rv32_core.v · regfile · clock edge'],
        ['2 · 주소', 'RAM과 UART를 어떻게 구분하는가?', 'rv32_soc.v · dmem_addr · wstrb'],
        ['3 · 프로그램', 'C 변수와 반복문이 무엇으로 바뀌는가?', 'c_demo.c → c_demo.s'],
        ['4 · 이미지', 'label이 어떻게 실제 주소가 되는가?', 'linker.ld → c_demo.elf → c_demo.hex'],
        ['5 · 실행', '자체 CPU가 올바른 결과를 만드는가?', 'tb_c_demo.v · PASS'],
        ['6 · 관측', '55가 언제 RAM에 저장되는가?', 'c_demo.vcd · signature_value']
      ]),
      notes: ['처음부터 파일 전체를 외우기보다 하나의 동작을 끝까지 추적한다. 이번 자료의 중심은 C에서 계산한 55가 register를 지나 RAM 주소 0x400에 기록되는 과정이다. 각 단계에서 코드와 관측 신호를 연결하면 HDL과 C의 역할이 분명해진다.', '발표 화면에서는 한 장씩 읽고, N 또는 해설 버튼으로 배경 설명을 펼친다. R 또는 읽기 버튼은 모든 슬라이드와 해설을 연속 문서로 보여준다. 실습할 때에는 PC, instruction, 데이터, write enable을 함께 관찰한다.']
    },
    {
      before: '지원 ISA', title: 'Clock edge와 상태 변경', heading: '조합 회로가 계산하고, rising edge가 저장한다',
      body: pair(code('always @* begin\n    next_pc = pc + 4;\n    // decode → operand → 결과 선택\nend\n\nalways @(posedge clk) begin\n    if (rst) pc <= RESET_PC;\n    else if (take_trap) pc <= csr_mtvec;\n    else pc <= next_pc;\nend'), '<p><b>Edge 직후:</b> 새 PC와 register 값이 출력된다.</p><p><b>Cycle 도중:</b> instruction memory, decoder, ALU와 read mux의 출력이 안정된다.</p><p><b>다음 edge:</b> rd_we가 켜진 register와 wstrb가 켜진 memory byte를 기록한다.</p><p>single-cycle은 이 조합 경로 전체가 한 주기 안에 안정되어야 한다는 의미다.</p>'),
      notes: ['Verilog의 always @*는 소프트웨어가 한 줄씩 시간을 쓰며 실행된다는 뜻이 아니다. 입력 변화에 따라 출력이 정해지는 조합 회로를 기술한다. 기본값을 먼저 주고 opcode별로 덮어쓰는 방식은 모든 경로에서 출력을 결정하여 latch가 생기지 않게 한다.', 'posedge 블록의 nonblocking assignment(<=)는 edge에서 이전 값을 읽고 갱신을 예약한다. PC가 바뀌면 새 명령어가 다시 조합 회로에 전파된다. VCD에서 같은 시각에 여러 값이 변하는 것은 시뮬레이터의 delta-cycle 갱신 때문이며 추가 CPU cycle이 아니다.', '현재 core의 주소 계산과 branch 비교는 일부가 별도 +, 비교 연산으로 작성되어 있다. 개념 데이터패스 그림의 ALU는 실행 계산 전체를 뜻하며, 모든 연산이 rv32_alu 인스턴스 하나를 공유한다는 뜻은 아니다.']
    },
    {
      before: '명령 실행', title: '명령어 비트 해독', heading: '0x00e787b3에서 ADD를 찾는 방법',
      body: table(['필드', 'instruction bit', '값', '의미'], [
        ['opcode', '[6:0]', '0110011', 'register-register OP'],
        ['rd', '[11:7]', '01111 = 15', '결과 x15(a5)'],
        ['funct3', '[14:12]', '000', 'ADD/SUB 계열'],
        ['rs1', '[19:15]', '01111 = 15', '이전 sum'],
        ['rs2', '[24:20]', '01110 = 14', '현재 i'],
        ['funct7', '[31:25]', '0000000', 'SUB가 아닌 ADD 선택']
      ]) + '<p class="footnote">PC=0x18: <code>add x15,x15,x14</code> → rd_we=1, rd_data=rs1_data+rs2_data. 다음 edge에 x15 갱신.</p>',
      notes: ['Compiler가 선택한 명령을 decoder는 문자열로 읽지 않는다. 32개의 bit를 고정 위치로 분리하여 opcode, funct3, funct7 조합을 검사한다. 이 예의 machine word는 현재 c_demo.dis의 0x18에 있는 값이다.', '입력 x15와 출력 x15가 같아도 문제가 없다. 조합식 read는 갱신 전 register 값을 제공하고 다음 rising edge에서 덧셈 결과가 기록된다. 첫 반복에서 x15=0, x14=1이므로 결과는 1이다.', 'LUI와 JAL 등 다른 형식에서는 같은 bit 위치가 immediate 일부로 쓰인다. Decoder가 opcode를 먼저 확인하는 이유다. 명령 형식마다 immediate 조합 함수를 따로 두는 것도 이 차이를 처리하기 위해서다.']
    },
    {
      before: 'CSR와 Trap', title: 'Byte lane과 write strobe', heading: '주소와 byte enable을 함께 읽어야 한다',
      body: table(['명령 / 주소', 'dmem_wstrb', 'dmem_wdata', '기록되는 위치'], [
        ['SB · 0x1000_0000 · 문자 C', '0001', '0x43434343', 'UART의 하위 byte 0x43'],
        ['SB · RAM 주소 끝 bit=01', '0010', 'byte를 4번 복제', 'aligned word의 [15:8]'],
        ['SH · RAM 주소 끝 bit=10', '1100', 'halfword를 2번 복제', 'aligned word의 [31:16]'],
        ['SW · RAM 0x400 · 합계 55', '1111', '0x00000037', '4개 byte 전부'],
        ['LW · RAM 0x400', '0000', 'write 값은 무관', 'read만 수행']
      ]) + '<p class="footnote">RAM word index = byte address &gt;&gt; 2. 따라서 <code>0x400 / 4 = 256</code>, 즉 <code>mem[256]</code>이다.</p>',
      notes: ['32-bit bus의 데이터에는 네 byte가 들어 있다. SB에서는 데이터를 32-bit로 복제해도 write enable이 하나만 켜지므로 한 byte만 기록된다. UART에 C를 쓰는 순간 dmem_wdata가 0x43434343인 이유가 여기에 있다.', 'Load는 memory가 aligned word를 반환하고 core가 address[1:0]만큼 8-bit 단위로 shift한다. LB/LH는 부호를 확장하고 LBU/LHU는 상위를 0으로 채운다. 현재 설계는 자연 정렬을 가정하며 경계를 넘는 misaligned load/store를 처리하지 않는다.', 'MMIO 장치는 RAM과 동일한 byte enable 처리를 반드시 갖는 것은 아니다. 현재 timer는 byte enable 전체를 전달받지 않으므로 소프트웨어에서 정렬된 SW를 사용하는 것이 이 구현의 계약이다.']
    },
    {
      before: 'CSR와 Trap', title: 'timer_wr 논리식', heading: 'timer_sel && (|dwstrb)를 회로로 읽기',
      body: pair(code("wire timer_sel =\n    (daddr[31:12] == 20'h10001);\n\nwire timer_wr =\n    timer_sel && (|dwstrb);\n\n// reduction OR:\n// |dwstrb = dwstrb[3] | dwstrb[2]\n//         | dwstrb[1] | dwstrb[0]"), '<p><b>주소 검사:</b> 0x1000_1000–0x1000_1FFF page에 접근하면 timer_sel=1.</p><p><b>쓰기 검사:</b> byte enable 중 하나라도 켜지면 reduction OR 결과가 1.</p><p><b>둘 다 1:</b> timer의 wr_en을 켜서 clock edge에서 값을 기록한다.</p><p>Timer read는 dwstrb=0000이므로 timer_wr=0이다.</p>'),
      notes: ['|dwstrb에서 |는 operand가 하나인 reduction OR다. 두 vector를 bit별로 OR하는 a | b와 달리 4-bit 입력 전체를 1-bit 결과로 줄인다. 바깥의 &&는 두 조건의 논리 AND이다.', 'Timer page 안에서 주소 bit 2만 선택에 사용된다. 따라서 0x10001000과 0x10001008은 같은 mtime register에 대응하는 alias다. 완전히 다른 register가 추가된 것이 아니다.', '현재 timer_wr는 SB/SH도 받아들이지만 simple_timer에는 strobe 입력이 없다. 결과적으로 low 32-bit 전체를 갱신한다. 주석과 슬라이드는 실제 회로의 동작을 설명하며 byte-write 지원을 추가한 것은 아니다.']
    },
    {
      before: 'UART 설계', title: 'Reset과 두 clock', heading: '100 MHz 입력에서 CPU clock을 만드는 과정',
      body: table(['단계', '구현', '관찰 / 이유'], [
        ['입력', 'CLK100MHZ · E3', '주기 10 ns'],
        ['분주', 'cpu_div <= cpu_div + 1', 'counter bit 2는 8주기마다 한 번 반복'],
        ['clock 배선', 'BUFG(cpu_div[2])', 'CPU clock 12.5 MHz · 주기 80 ns'],
        ['reset', 'CPU_RESETN · C12', '비동기 assert, 각 domain에서 두 단계로 해제'],
        ['경로 분석', 'create_generated_clock -divide_by 8', 'CPU↔UART 경로도 related clock으로 timing 분석']
      ]),
      notes: ['한 번 토글하는 시간과 한 주기를 혼동하지 않는다. bit 2는 4개의 입력 clock마다 토글하고 8개마다 같은 위상으로 돌아오므로 주파수는 100/8=12.5 MHz다. BUFG는 이 신호를 FPGA global clock network로 배포한다.', 'CPU domain에서 나온 valid는 80 ns 동안 유지된다. UART는 100 MHz에서 이를 받아 첫 byte를 capture한 뒤 busy가 되므로 남은 valid 구간을 새 요청으로 받지 않는다. 이 연결은 현재 주파수/baud 설정과 related-clock timing 제약에 기대고 있다.', '같은 구조를 서로 독립적인 clock에 그대로 적용할 수는 없다. 그런 확장에서는 handshake 동기화 또는 FIFO가 필요하다. 현재 C testbench는 board top 대신 rv32_soc만 사용하므로 이 두-clock 경로를 검증한 결과는 아니다.']
    },
    {
      before: 'ABI와 컴파일 옵션', title: 'C 시작점과 런타임', heading: '운영체제 없이 C 함수가 시작되는 이유',
      body: pair(code('__attribute__((section(".text.start"),\n               noreturn))\nvoid _start(void) {\n    // 계산 → signature → UART\n    for (;;) { }\n}\n\n// linker.ld\nENTRY(_start)\nKEEP(*(.text.start))'), '<p>CPU의 reset PC는 0이다. Linker가 .text.start를 RAM 시작 주소 0에 놓는다.</p><p>현재 -O1 생성 코드는 stack 접근과 함수 호출 없이 실행된다. uart_putc의 동작도 함수 안에 펼쳐져 있다.</p><p>일반적인 C 프로그램에는 startup assembly로 sp 초기화와 .bss 초기화 등을 준비해야 한다.</p>'),
      notes: ['ENTRY(_start)는 ELF entry 정보를 지정한다. CPU가 ELF header를 읽는 것은 아니다. 실제로 reset PC=0이고 그 위치에 _start의 instruction이 놓여 있다는 두 조건이 맞아야 실행된다. HEX에는 ELF header가 없다.', '현재 예제는 compiler가 stack을 사용하지 않는 코드를 생성했기에 별도 crt0 없이 성공했다. 최적화 수준 변경, 지역 배열 추가, 함수 호출 추가 등은 stack 사용을 유발할 수 있다. 현재 register file reset은 sp도 0으로 만들므로 이것을 유효한 stack 초기화로 생각하면 안 된다.', 'sum_limit=10은 .data 초기값이 HEX에 들어가 RAM에 적재된다. .bss는 ELF에서는 NOLOAD이며, 이 SoC의 mem 초기화가 공간을 0으로 채운다. 더 일반적인 환경에서는 startup code가 .data 복사와 .bss zeroing을 책임진다.']
    },
    {
      before: 'C에서 Assembly로', title: 'volatile과 MMIO', heading: '반복해서 읽어야 하는 값과 반드시 써야 하는 값',
      body: pair(code('volatile uint32_t sum_limit = 10u;\n\nvolatile uint32_t *const signature =\n    (volatile uint32_t *)0x400u;\n\nwhile ((*uart_ready & 1u) == 0u) { }\n*uart_tx = value;\n*signature = sum;'), '<p><b>sum_limit:</b> 반복 조건을 평가할 때 memory read가 유지된다.</p><p><b>UART:</b> polling할 때마다 상태를 다시 읽고 문자를 실제로 store한다.</p><p><b>Signature:</b> C 코드가 값을 다시 읽지 않아도 관측용 write를 유지한다.</p><p>volatile은 접근을 유지하는 C 규칙이며, cache flush나 CPU fence 기능은 아니다.</p>'),
      notes: ['상수 10을 사용하는 단순 반복문은 최적화 결과 sum=55라는 상수로 바뀔 수 있다. 이 데모는 volatile sum_limit을 사용하여 실제 반복문과 load/branch를 관측할 수 있도록 했다.', 'volatile uint32_t *const에서 volatile은 가리키는 데이터 접근에 적용되고, const는 pointer 변수 자체를 바꾸지 못하게 한다. 둘은 다른 역할이다. UART_TX pointer가 uint8_t인 것은 byte store인 SB를 생성하려는 의도다.', 'Signature 주소 0x400은 현재 작은 이미지 영역 밖에 있다. Linker가 이 주소를 전용 section으로 예약한 것은 아니므로 프로그램 크기가 커지면 충돌할 수 있다. 확장할 때에는 signature section과 stack 영역을 linker script에서 명시적으로 분리해야 한다.']
    },
    {
      before: 'Symbol과 Relocation', title: '첫 여섯 명령 추적', heading: '_start에서 반복문 입구까지',
      body: table(['PC', '명령', '실행 후 변화'], [
        ['0x00', 'lui a5,%hi(.LANCHOR0)', 'x15=0 · 주소 상위 부분 준비'],
        ['0x04', 'lw a5,%lo(.LANCHOR0)(a5)', 'Memory[0x68]=10 → x15'],
        ['0x08', 'beqz a5,.L2', '10≠0 → 다음 PC=0x0C'],
        ['0x0C', 'li a4,1', 'x14=1 · i 초기화'],
        ['0x10', 'li a5,0', 'x15=0 · 이제 합계로 사용'],
        ['0x14', 'lui a3,%hi(.LANCHOR0)', 'x13=0 · 반복 load의 주소 base']
      ]),
      notes: ['이 표의 PC는 실행하려는 instruction의 주소이며 실행 후 변화는 다음 rising edge에서 register에 반영되는 값이다. x15는 처음부터 끝까지 sum이라는 C 변수에 고정 배정된 register가 아니다. 처음에는 limit을 읽는 임시값이고 그 뒤 합계 누적용으로 재사용된다.', 'sum_limit이 0이면 beqz가 0x2C로 이동한다. 이 경우 x15는 이미 0이므로 li a5,0을 건너뛰어도 0이라는 올바른 합계가 저장된다. 현재 입력 10에서는 분기가 실행되지 않는다.', '이 데모에서 주소 0x68, 0x2C와 register 배정은 현재 GCC 9.3.0 및 옵션으로 만든 결과다. C 소스나 옵션이 바뀌면 .dis와 waveform probe 이름의 의미를 다시 맞춰야 한다.']
    },
    {
      before: 'Symbol과 Relocation', title: '반복문 단계 실행', heading: '명령 하나씩 실행하며 register 변화를 확인',
      body: '<p class="lesson-caption">현재 disassembly에 근거한 교육용 모델 · RTL simulator가 아님 · limit=10 고정</p><div class="trace-controls"><button id="traceReset">처음으로</button><button id="traceNext">다음 명령 실행 →</button><span id="traceStatus" role="status"></span></div><div id="traceState" class="trace-state"></div><div id="traceCode"></div><p id="traceExplanation" class="explain-band"></p>',
      notes: ['시작 상태는 PC=0x18, sum=0, i=1, 주소 base x13=0이다. 버튼을 누를 때마다 ADD, ADDI, 주소 복원 ADDI, LW, BGEU의 순서로 다음 상태를 계산한다. 다섯 명령을 지나면 다음 반복의 ADD로 돌아간다.', '주소 복원 ADDI를 생략하면 안 된다. LW 후 a2는 주소 0x68이 아닌 읽어온 값 10을 담는다. 다음 반복의 load 전에 a2를 다시 0x68로 만들어야 한다. 이 설명에서는 실제 생성 코드의 그 명령을 모두 보여준다.', '마지막 반복에서 sum=55, i=11이 되고 unsigned 비교 10≥11이 거짓이므로 PC=0x2C로 진행한다. 이어지는 SW를 한 번 더 실행하면 signature가 55로 바뀐다. 화면의 상태는 RTL 실행 결과를 대신하는 검증이 아니라 명령 의미를 학습하는 모델이다.']
    },
    {
      before: 'HEX 적재와 실행', title: '파일과 재현 명령', heading: '각 산출물이 무엇을 담는지 구분하기',
      body: table(['파일', '내용', '열어 볼 때의 목적'], [
        ['firmware/c_demo.c', '원본 C', '알고리즘과 MMIO pointer 확인'],
        ['build/firmware/c_demo.s', 'compiler assembly', 'C가 어떤 명령 흐름으로 바뀌었나'],
        ['build/firmware/c_demo.elf', 'link된 실행 이미지', '주소·symbol·section'],
        ['build/firmware/c_demo.dis', 'ELF의 objdump 결과', 'PC · machine code · 실제 ISA 명령'],
        ['build/firmware/c_demo.bin', 'raw binary', '주소순 byte 배열'],
        ['firmware/c_demo.hex', '32-bit word 텍스트', '$readmemh 입력'],
        ['build/c_demo.vcd', '시간별 signal 변화', '계산과 저장 시점 확인']
      ]),
      notes: ['프로젝트 루트에서 make c-demo를 실행하면 .c→.s→.elf→.bin→.hex와 .dis가 만들어진다. make c-demo-disasm은 disassembly를 터미널에 보여준다. .dis는 .s 텍스트를 직접 변환한 결과가 아니라 최종 ELF를 objdump로 읽은 결과다.', 'make sim-c-demo는 firmware 생성 의존성을 먼저 처리하고 RTL을 컴파일한 뒤 vvp로 실행한다. 시스템의 Icarus를 우선 사용하며 현재 프로젝트에 풀어 둔 build/tools/iverilog도 대안으로 사용한다. make clean은 이 로컬 도구까지 삭제한다.', 'objdump의 -S는 debug 정보가 있을 때 소스 혼합 표시를 요청한다. 현재 C 빌드에는 -g가 없으므로 C 소스 줄이 함께 나타난다고 보장하지 않는다. -M no-aliases,numeric은 li/beqz 대신 실제 instruction과 x번호를 보여준다.']
    },
    {
      before: 'VCD로 계산 관찰', title: '시뮬레이션 검증 범위', heading: 'PASS가 확인한 경계를 분명히 하자',
      body: pair(code('rv32_soc #(\n  .MEM_WORDS(2048),\n  .MEM_HEX("firmware/c_demo.hex")\n) dut (\n  .uart_tx_ready(1\'b1),\n  ...\n);\n\n// 1000 clocks 후:\n// mem[256] === 55\n// received[] == "C OK\\n"'), '<p><b>확인:</b> 자체 CPU에서 생성 HEX를 실행하고 합계와 MMIO 출력 byte를 비교.</p><p><b>Clock:</b> #5마다 반전 → 테스트의 주기는 10 ns. reset은 22 ns에 해제.</p><p><b>경계:</b> UART serializer와 실제 D4 핀은 이 testbench에 포함되지 않는다.</p><p>Behavioral simulation 성공과 FPGA timing closure는 서로 다른 검증이다.</p>'),
      notes: ['C testbench는 nexys_a7_top이 아니라 rv32_soc를 직접 인스턴스화한다. ready가 항상 1이므로 UART busy 동안 polling하는 경로를 시험하지 않으며, 출력 byte를 UART transmitter 대신 testbench가 받는다. 따라서 115200 baud 직렬 파형을 검증한 것은 아니다.', '수신 배열은 처음 5개 byte만 기록한다. 이 테스트는 기대한 첫 다섯 문자와 최종 signature를 확인하며, 추가 byte가 없는지나 모든 ISA 명령이 정확한지까지 검증하지 않는다. 여기는 작은 프로그램에 대한 end-to-end smoke test다.', 'xvlog는 Verilog 분석, xelab는 hierarchy elaboration, xsim은 시간에 따른 simulation을 수행한다. 현재 설치의 XSim은 내부 Tcl 예외로 실행하지 못했고, 실제 PASS와 VCD는 Icarus Verilog로 생성했다.']
    },
    {
      before: 'Hello 펌웨어', title: 'Signature 저장 edge', heading: 'write 요청과 저장된 값은 한 edge를 사이에 둔다',
      body: table(['현재 VCD 시간', 'CPU / bus 상태', 'RAM 0x400'], [
        ['575 ns 직후', 'PC=0x2C · instruction=0x40f02023', '아직 0'],
        ['575–585 ns', 'addr=0x400 · data=0x37 · strobe=1111', 'write 요청이 안정되는 구간'],
        ['585 ns rising edge', 'posedge 블록이 store를 반영', 'mem[256] ← 55'],
        ['585 ns의 갱신 후', 'PC=0x30 · signature_write=0', 'signature_value=0x37 유지']
      ]) + '<p class="footnote">타임스케일 1 ps에서 <code>#585000 = 585 ns</code>. 같은 timestamp의 갱신 순서는 물리적인 추가 clock을 의미하지 않는다.</p>',
      notes: ['현재 VCD 파일에서 이 이벤트를 확인했다. signature_write는 저장 완료 알림이 아니라 현재 bus가 signature 주소에 write하려 한다는 조합식 표시다. 저장은 해당 조건이 유효한 rising edge에서 일어난다.', 'signature_write_data와 signature_write_strobe는 bus를 직접 연결한 probe다. signature 주소가 아닌 UART write에서도 바뀐다. 따라서 값의 의미는 signature_write=1인 구간에서 해석해야 한다. 반면 signature_value는 mem[256]의 실제 내용이다.', 'sum_x15는 초기에 sum_limit=10, 계산 중 합계, 계산 후 UART 상태값을 표시한다. VCD 화면에서 55 이후 값이 바뀌어도 RAM의 결과가 지워진 것이 아니다. Signature가 0x37을 유지하는지 확인하면 된다.']
    },
    {
      before: 'Hello 펌웨어', title: 'UART ASCII 해석', heading: '43 20 4F 4B 0A는 C OK와 줄바꿈이다',
      body: table(['HEX', '10진수', 'ASCII 의미', '관측 시 주의'], [
        ['0x43', '67', 'C', '첫 번째 byte'],
        ['0x20', '32', '공백', '문자가 안 보여도 하나의 byte'],
        ['0x4F', '79', 'O', '숫자 0(0x30)과 다름'],
        ['0x4B', '75', 'K', '네 번째 byte'],
        ['0x0A', '10', 'LF / \\n', '출력 줄바꿈']
      ]) + '<p class="footnote">유효한 문자는 <code>uart_valid=1</code>일 때의 <code>uart_data</code>다. valid=0일 때 data가 이전 문자로 남는 것은 정상이다.</p>',
      notes: ['C 문자열 "C OK\\n"은 다섯 개의 출력 byte와 문자열 종료를 나타내는 NUL 0x00으로 저장된다. 프로그램은 NUL을 발견하면 종료하므로 UART에는 다섯 byte만 쓴다. newline 0x0A와 NUL 0x00은 서로 다른 값이다.', 'C 데모의 sb a2,0(a4)가 실행되면 core는 byte를 네 lane에 복제하고 strobe=0001을 만든다. UART MMIO는 하위 byte를 capture한다. VCD에서 0x43434343과 0x43은 각각 32-bit bus와 8-bit UART data를 관측한 결과다.', '실제 board UART에서는 이 byte를 start 0, data LSB부터 8 bit, stop 1로 직렬화한다. 하지만 이 VCD의 uart_data는 병렬 byte interface다. 직렬 TX 신호를 보려면 uart_tx를 포함하는 별도 testbench가 필요하다.']
    },
    {
      before: 'Hello 펌웨어', title: 'VCD 실습 순서', heading: '파형을 열고 결과를 확인하는 순서',
      body: table(['단계', '할 일', '기대 결과'], [
        ['1', 'make sim-c-demo 실행', 'PASS와 build/c_demo.vcd 생성'],
        ['2', 'VS Code VCD viewer에서 파일 열기', 'tb_c_demo scope 탐색'],
        ['3', 'clk, rst, debug_pc, sum_x15, loop_i_x14 추가', 'reset 후 PC와 계산 진행 확인'],
        ['4', 'signature_write/data/strobe/value 추가', '정확한 이름은 아래 해설 참조'],
        ['5', '575–595 ns 구간 확대', '585 ns 이후 signature_value=0x37'],
        ['6', 'uart_valid, uart_data 추가', '43 → 20 → 4F → 4B → 0A']
      ]),
      notes: ['정확한 top-level probe 이름은 signature_write, signature_write_data, signature_write_strobe, signature_value다. dmem_addr와 insn은 tb_c_demo.dut.cpu 아래에서 찾을 수 있다. 이름이 비슷한 bus 신호가 여러 scope에 있으므로 전체 경로를 확인한다.', 'PC, instruction, address는 hexadecimal 표시가 편하고 sum_x15와 loop_i_x14는 unsigned decimal 표시가 편하다. UART data는 ASCII 또는 hex로 보면 문자와 byte 값을 쉽게 연결할 수 있다. 우선 전체 시간을 맞춘 뒤 저장 edge 주변을 확대한다.', '프로그램을 바꿔 재실행했다면 viewer를 reload하여 최신 VCD를 읽는다. 주소, register 배정, 시간은 현재 빌드의 값이다. 새로운 firmware에서는 .dis에서 SW의 PC부터 다시 확인하는 것이 안전하다.']
    }
  ];

  const notes = {
    '표지': ['이 프로젝트는 CPU RTL, 주변장치, 펌웨어 toolchain, FPGA 구현, 시뮬레이션을 한 저장소에서 연결한다. 목표는 학습용 RV32I processor 위에서 나중에 timer와 context switch를 가진 작은 OS를 실행하는 것이다.', '현재 확인된 결과는 FPGA bitstream과 timing report, 그리고 별도 C 데모의 RTL simulation이다. 실제 보드 관측 완료와 OS 구현 완료를 뜻하지는 않는다.'],
    '목표와 결과': ['RV32I core는 정수 연산, load/store, branch/jump를 수행하며 최소 CSR/trap 경로를 포함한다. Nexys top은 8 KiB memory와 UART TX를 연결한다. 이러한 블록을 주소 맵으로 묶은 전체가 SoC다.', 'FPGA 빌드의 Hello assembly와 simulation의 C 데모를 구분해서 읽는다. C 데모는 계산 결과를 자동 검사하는 검증용이며 현재 기본 bitstream에는 Hello assembly가 들어 있다.'],
    '전체 구조': ['Firmware HEX는 memory의 초기 내용이고 bitstream은 FPGA 회로와 초기 설정을 담는다. 두 파일은 역할이 다르다. HEX만으로 FPGA에 CPU가 만들어지지 않으며 Verilog를 구현한 bitstream도 필요하다.', 'CPU는 명령어의 bit pattern을 읽어 register와 memory를 변경한다. UART 주소로 store하면 주소 decode가 RAM 대신 주변장치를 선택한다. 그 결과가 board top의 실제 TX pin에 연결된다.'],
    'Single-cycle 데이터패스': ['한 cycle에는 instruction fetch, operand read, 연산, data read, write-back 선택이 모두 들어간다. 실제 register write는 다음 edge다. 긴 load 경로가 clock period를 제한하는 이유를 여기서 이해할 수 있다.', '동기식 FPGA BRAM은 주소를 clock에 맞춰 받아 결과를 내므로 현재 조합식 memory interface에 곧바로 대체할 수 없다. BRAM을 쓰려면 fetch/load를 여러 cycle로 나누거나 pipeline과 stall을 설계해야 한다.'],
    '지원 ISA': ['기본 정수 RV32I 명령의 교육용 구현이다. CSR 연산은 별도의 Zicsr 성격이며 ECALL/MRET와 최소 machine-mode 기능도 포함한다. 지원 목록은 완전한 표준 적합성 검증을 뜻하지 않는다.', 'FENCE는 outstanding transaction이 없는 현재 구조에서 NOP로 처리된다. misaligned access와 EBREAK 등 예외 처리는 아직 완전하지 않다. 실행 코드를 만들 때에는 rv32i/ilp32 옵션으로 불필요한 확장 명령 생성을 막는다.'],
    'RTL 모듈': ['실제 hierarchy는 nexys_a7_top 아래에 soc와 serial이 있고, soc 아래에 cpu와 timer가 있다. cpu 내부에는 rf, alu, csr가 있다. 슬라이드의 core 카드는 내부 확대 설명이다.', '분리된 module은 역할을 좁혀 읽기와 검증을 쉽게 한다. ALU만의 연산, register file의 x0 동작, CSR의 interrupt enable을 각각 확인한 뒤 SoC 차원의 프로그램 실행을 시험할 수 있다.'],
    '명령 실행': ['이 예는 초기 Hello assembly의 sb gp,0(ra)이다. ra에는 UART base, gp에는 문자가 있으며 통상 함수 호출 ABI 역할과 다르게 일반 register처럼 쓰고 있다. 함수 호출을 사용하지 않는 독립 assembly 데모이기 때문이다.', '주소 계산은 core의 rs1_data+imm_s 표현이고 실제 RTL에서는 별도의 덧셈식이다. UART store가 accept되면 soc는 data와 valid를 register로 내보낸다. 다음 UART clock edge에서 serializer가 이를 수신한다.'],
    '메모리 맵': ['보드 top의 MEM_WORDS=2048이므로 유효 RAM은 0x00000000부터 0x00001FFF까지다. rv32_soc의 default parameter는 16384 words지만 보드에서 override한다.', '프로그램은 RAM 주소와 MMIO 주소를 모두 load/store로 접근한다. 현재 unmapped data read는 0, instruction fetch는 NOP을 반환하고 access fault를 발생시키지 않는다. Memory 보호가 있는 OS 수준의 동작은 추가 구현이다.'],
    'CSR와 Trap': ['timer_irq 자체가 높다는 것만으로 CPU가 handler로 이동하지 않는다. mstatus.MIE와 mie.MTIE까지 모두 켜져야 irq_pending이 1이다. CSR block은 mip.MTIP에는 외부 timer level을 반영한다.', 'Trap이 선택되면 core는 현재 instruction의 register/CSR/memory write를 억제하고 mepc에 현재 PC를 저장한다. 이 구현은 pending timer IRQ를 동기 exception보다 우선한다. Handler는 ECALL을 재실행하지 않도록 필요한 경우 mepc를 4 증가시켜야 하지만 interrupt 복귀에서는 중단 명령을 재실행한다.', '현재 mstatus는 MIE/MPIE만 구현하며 full privilege state와 CSR 접근 권한 검사는 완전하지 않다. MRET는 mepc로 PC를 돌리고 MPIE를 MIE로 복구한다.'],
    'Timer와 Scheduler': ['Timer는 CPU/SoC clock마다 mtime을 1 증가시킨다. 현재 FPGA 설정 12.5 MHz에서는 10 ms가 125000 tick이다. mtime≥mtimecmp 조건을 사용하므로 일치 순간을 놓쳐도 IRQ level이 유지된다.', 'Handler는 다음 compare 값을 미래로 옮겨 IRQ를 해제해야 한다. 현재 MMIO는 low word만 노출하고 mtimecmp high word는 0이므로 장시간 실행을 위한 완전한 64-bit timer interface가 필요하다.', 'Context switch는 하드웨어가 x1–x31을 자동 저장하는 기능이 아니다. Handler assembly가 task context를 저장하고 scheduler가 다음 task를 선택한 뒤 복원해야 한다. 현재는 이를 위한 최소 RTL 기반까지만 있다.'],
    'Nexys A7 연결': ['Pin 이름 UART_RXD_OUT은 USB-UART bridge가 받는 방향을 기준으로 붙은 보드 이름이며 FPGA 입장에서는 송신 출력이다. XDC는 이 top port를 D4에 연결한다.', '100 MHz에서 single-cycle 경로가 timing을 만족하지 못했기 때문에 CPU clock을 12.5 MHz로 낮췄다. 최종 timing 충족은 사용한 constraint 내의 결과이며 실제 board test와 별도로 해석한다.'],
    'UART 설계': ['한 frame은 start 1개, data 8개, stop 1개로 총 10 bit이다. 100 MHz에서 정수 divider 868을 사용하면 실제 baud는 약 115207이고 한 문자 전송에 약 86.8 μs가 필요하다.', 'ready는 !busy이다. Firmware는 ready를 확인하고 byte를 쓰며, transmitter는 idle일 때 valid를 받아 frame을 capture한다. 현재 serial module에는 receive 기능이나 FIFO가 없다.'],
    '펌웨어 빌드': ['make firmware는 nexys_hello.S를 assembler/linker로 처리한다. .S는 전처리가 가능한 assembly source 확장자이고 C에서 -S로 생성한 .s도 assembler 입력으로 쓸 수 있다.', 'objcopy가 ELF header와 symbol을 제거한 raw byte image를 만든다. bin2hex.py는 네 byte씩 little-endian 값으로 읽어 8자리 hex 한 줄을 쓴다. 파일 끝의 불완전한 word는 0으로 padding하며 8 KiB 초과를 검사한다.'],
    'C 데모의 목표': ['화면의 코드는 동작 요약이며 실제 c_demo.c에는 volatile과 명시적인 주소 상수가 있다. 실제 프로그램은 sum_limit을 memory에서 반복해서 읽고 signature에 volatile store한다.', 'RAM의 결과는 계산 경로를 검증하고 UART 문자열은 branch/load-byte/store-byte 경로를 검증한다. Signature라는 말은 여기서 testbench가 확인할 결과 저장 위치를 뜻하며 암호학적 signature가 아니다.'],
    'ABI와 컴파일 옵션': ['ISA는 instruction encoding과 동작, ABI는 함수 간 값 전달과 저장 규칙이다. x10을 a0라고 쓰는 것은 다른 register를 추가하는 것이 아니라 같은 register에 관례적인 별칭을 붙이는 것이다.', 'a0–a7은 인자 전달에 쓰이고 a0–a1은 반환값에 쓰인다. s0–s11은 callee가 보존해야 하고 a/t register는 caller가 필요한 값을 보존한다. 현재 loop의 a4/a5 용도는 compiler의 임시 배정이며 ABI가 i와 sum에 강제한 배정이 아니다.', '일반적인 ILP32 함수 진입 stack은 16-byte 정렬을 유지해야 한다. 따라서 함수 예제를 확장할 때 8 byte만 sp에서 빼는 식의 코드를 그대로 사용하면 표준 호출 규약과 맞지 않을 수 있다.'],
    'C에서 Assembly로': ['-S는 assembly 출력 단계에서 멈추게 한다. .s에는 아직 symbol과 pseudo instruction이 남아 있고 실제 memory 주소는 link 단계에서 확정된다.', 'Loop의 add는 sum을 증가시키고 addi는 i를 증가시킨다. 그 다음 sum_limit 주소를 a2에 복원한 뒤 lw로 값을 읽고 bgeu로 다음 반복 여부를 판단한다. Unsigned C 변수이므로 unsigned branch가 선택된 것이다.', '화면 명령의 시작 전에는 limit=0 검사 등이 있다. 전체 실행 흐름은 c_demo.s와 c_demo.dis에서 확인한다. 재현은 간략화한 gcc 명령보다 프로젝트의 전체 옵션을 포함한 make c-demo를 사용한다.'],
    'Symbol과 Relocation': ['.LANCHOR0는 compiler 내부 label이다. 현재 .data의 sum_limit과 같은 위치를 가리키며 linker 결과 주소는 0x68이다. 파일 크기나 section 배치가 바뀌면 주소도 바뀔 수 있다.', 'RISC-V I-type immediate는 signed 12-bit이다. 주소를 구성할 때 %hi는 단순 상위 bit 절단만 하는 것이 아니라 low 12-bit의 부호를 보정한다. 예를 들어 0x1800은 LUI 2와 signed offset -2048로 구성한다.'],
    'Assembly와 Disassembly': ['li a4,1은 ADDI로, beqz는 x0와 비교하는 BEQ로, j는 rd=x0인 JAL로 바뀐다. 모든 pseudo instruction이 한 명령이 되는 것은 아니다. 큰 상수를 만드는 li는 여러 instruction으로 확장될 수 있다.', 'Disassembly의 왼쪽 열은 byte address, 가운데 열은 32-bit machine word, 오른쪽은 해석한 명령이다. -M no-aliases,numeric 옵션이 실제 instruction 이름과 register 번호를 표시하게 한다.'],
    'ELF에서 HEX까지': ['0x000007b7을 little-endian memory에 놓으면 가장 낮은 주소의 byte는 b7이다. VCD의 instruction bus는 32-bit 값 000007b7을 보여준다. Byte dump와 word dump가 반대로 보이는 이유가 이것이다.', 'HEX의 한 줄은 ASCII로 표현한 32-bit word이며 ELF의 문자열 출력물이 아니다. Program text, read-only 문자열, 초기화된 data가 binary image에 포함된다. .dis의 instruction 줄만 긁어 HEX로 만들면 data를 잃을 수 있다.'],
    'HEX 적재와 실행': ['$readmemh는 simulation 초기화 시 mem array의 초기값을 채운다. RTL initial에서 먼저 전체 memory를 0으로 채우고 파일의 word를 앞에서부터 덮어쓴다. 이미지가 전체 memory보다 짧다는 경고는 이 초기화 구조에서는 예상되는 결과다.', 'Reset 해제 후 첫 rising edge에서 PC=0의 LUI가 retire된다. 그 다음 PC=4, 8 등으로 진행한다. Testbench는 최종 RAM 값과 첫 다섯 UART byte를 검사하며 실패하면 $fatal을 실행한다.'],
    'VCD로 계산 관찰': ['파형 그림은 계산 구간을 압축한 개념도다. 실제 x15는 초기 limit 읽기 때문에 10을 거친 뒤 0,1,3…55로 바뀌고 UART 구간에서는 상태값으로 다시 바뀐다.', 'sum_x15, loop_i_x14는 debug용 hierarchical wire다. CPU instruction으로 읽은 값이 아니라 testbench가 내부 register array를 직접 관측한 값이다. Compiler가 register를 다르게 배정하면 이 이름과 C 변수의 대응도 달라진다.'],
    'Hello 펌웨어': ['이 페이지는 FPGA 기본 이미지 nexys_hello.hex의 프로그램이다. C 데모의 C OK와 달리 Hello Nexys A7!을 출력한다. .org 0x100에 문자열이 배치되고 pointer를 한 byte씩 증가시키며 NUL까지 출력한다.', 'ra, sp, gp, tp를 일반 변수용으로 사용한 독립 assembly다. C 함수를 호출하거나 stack을 쓰는 startup으로 그대로 재사용하면 안 된다. UART data를 쓰기 전에 ready를 polling하는 순서를 익히는 예제다.'],
    'Vivado 구현 결과': ['이 수치는 저장소에 있는 Nexys Hello 이미지의 Vivado 2022.1 구현 report에서 읽은 값이다. 슬라이드 업데이트가 새로운 구현 run을 의미하지 않는다. WNS 3.850 ns와 WHS 0.139 ns는 각각 최악 setup/hold 여유다.', 'Distributed RAM은 LUT 기반 storage다. 현재 memory는 2개 조합 read port와 byte write를 사용한다. CPU RTL만 보고 BRAM을 사용한다고 추측하지 말고 utilization report의 Block RAM Tile과 LUT as Memory를 확인한다.'],
    '실행 방법': ['make c-demo 및 make sim-c-demo는 C 이미지와 simulation 경로다. make vivado의 의존성은 firmware이며 nexys_a7_top은 firmware/nexys_hello.hex를 읽도록 되어 있다. 두 경로가 자동 연결된 것은 아니다.', 'C 데모를 board에 올리려면 top의 image 선택과 Vivado 빌드 의존성 등을 변경하고 다시 구현해야 한다. 현재 슬라이드 업데이트는 그 하드웨어 변경을 수행하지 않는다. 기본 Hello board 확인은 115200-8-N-1 terminal을 열고 reset 후 출력을 보는 방식이다.'],
    '검증과 한계': ['문법 분석 통과, 특정 프로그램 simulation 통과, FPGA timing 충족, 실제 보드 동작은 각각 다른 검증 결과다. Xvlog만으로 모든 module 연결과 시간 동작이 검증되었다고 해석하면 안 된다.', '현재 C 데모 PASS는 일부 명령과 memory/UART 경로를 실제로 시험한 유용한 증거다. 하지만 전체 ISA, CSR 접근 권한, trap nesting, timer wraparound의 모든 경우를 검증한 것은 아니다.'],
    '다음 로드맵': ['다음 소프트웨어 단계는 stack 초기화와 trap entry assembly다. Timer handler에서 현재 register context를 저장하고 다음 task context를 복원한 뒤 MRET를 실행한다. 두 task가 번갈아 실행되는 것을 먼저 확인한다.', '그 이후에 syscall, pipeline, hazard 처리, memory stall을 순서대로 추가할 수 있다. Pipeline stall은 instruction 진행을 하드웨어가 잠시 멈추는 것이고 context switch는 OS가 실행 task 상태를 바꾸는 것이므로 다른 계층의 개념이다.'],
    '마무리': ['이번 학습의 기준은 C의 sum, assembly의 a5, RTL의 register file, VCD의 sum_x15와 RAM signature를 하나의 경로로 연결해서 설명할 수 있는가이다.', '직접 재현하려면 make sim-c-demo 후 최신 VCD를 열고 store edge를 확인한다. 상세 해설을 함께 읽거나 인쇄하려면 읽기 모드(R)를 켠 뒤 P를 사용한다.']
  };

  for (const lesson of lessons) {
    const anchor = [...document.querySelectorAll('.slide')].find(s => s.dataset.title === lesson.before);
    const section = document.createElement('section');
    section.className = 'slide detail-slide';
    section.dataset.title = lesson.title;
    section.innerHTML = `<header><span class="num"></span><div><p class="overline">STEP BY STEP · CODE TO WAVEFORM</p><h2>${lesson.heading}</h2></div></header>${lesson.body}`;
    anchor.before(section);
    notes[lesson.title] = lesson.notes;
  }
  let chapter = 0;
  for (const slide of document.querySelectorAll('.slide')) {
    const number = slide.querySelector('.num');
    if (number) number.textContent = String(++chapter).padStart(2, '0');
    const aside = document.createElement('aside');
    aside.className = 'lesson-notes';
    aside.setAttribute('aria-label', `${slide.dataset.title} 상세 해설`);
    aside.innerHTML = `<h3>${slide.dataset.title} · 상세 해설</h3>${notes[slide.dataset.title].map((p, i) => `<p><b>${i + 1}.</b> ${escape(p)}</p>`).join('')}`;
    slide.append(aside);
  }

  // Educational stepper mirrors the fixed loop in the current c_demo.dis.
  const rows = [
    ['0x18', 'add a5,a5,a4'], ['0x1C', 'addi a4,a4,1'],
    ['0x20', 'addi a2,a3,104'], ['0x24', 'lw a2,0(a2)'],
    ['0x28', 'bgeu a2,a4,0x18'], ['0x2C', 'sw a5,1024(zero)']
  ];
  let state;
  const render = explanation => {
    document.querySelector('#traceState').innerHTML = [
      ['sum / x15', state.sum], ['i / x14', state.i], ['a2 / x12', state.a2], ['RAM 0x400', state.ram]
    ].map(([label, value]) => `<span><small>${label}</small><b>${value}</b></span>`).join('');
    document.querySelector('#traceCode').innerHTML = table(['다음 실행 PC', 'instruction'], rows.map((row, i) => row.map(value => `<span class="${i === state.step ? 'trace-current' : ''}">${value}</span>`)));
    document.querySelector('#traceExplanation').textContent = explanation;
    document.querySelector('#traceStatus').textContent = state.done ? '완료 · signature=55' : `${state.count}개 명령 실행`;
    document.querySelector('#traceNext').disabled = state.done;
  };
  const reset = () => {
    state = {step: 0, sum: 0, i: 1, a2: 0, ram: 0, count: 0, done: false};
    render('PC=0x18 직전의 초기 상태. 다음 명령 실행을 눌러 ADD 결과부터 확인하세요.');
  };
  document.querySelector('#traceReset').addEventListener('click', reset);
  document.querySelector('#traceNext').addEventListener('click', () => {
    if (state.done) return;
    let explanation;
    switch (state.step) {
      case 0: explanation = `ADD: 이전 합계 ${state.sum} + 현재 i ${state.i} → ${state.sum + state.i}`; state.sum += state.i; state.step++; break;
      case 1: state.i++; explanation = `ADDI: 다음 반복 후보 i=${state.i}`; state.step++; break;
      case 2: state.a2 = 104; explanation = 'ADDI: a2를 sum_limit 주소 0x68(104)로 다시 설정'; state.step++; break;
      case 3: state.a2 = 10; explanation = 'LW: Memory[0x68]=10을 a2에 읽음. a2는 이제 주소가 아닌 limit 값'; state.step++; break;
      case 4: {
        const taken = state.a2 >= state.i;
        explanation = `BGEU: ${state.a2} ≥ ${state.i} → ${taken ? '참, PC=0x18로 반복' : '거짓, PC=0x2C의 SW로 진행'}`;
        state.step = taken ? 0 : 5; break;
      }
      case 5: state.ram = state.sum; state.done = true; state.step = -1; explanation = 'SW: address=0x400, data=55, strobe=1111. Edge에서 signature RAM을 갱신'; break;
    }
    state.count++;
    render(explanation);
  });
  reset();
})();
