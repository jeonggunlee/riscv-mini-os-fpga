# MiniFS: RAM disk 파일 시스템

현재 Mini OS는 별도의 8 KiB RAM disk를 `0x8010_0000`에 매핑합니다. 이 주소는
기존 Mini OS의 코드·스택용 8 KiB RAM(0x0000_0000–0x0000_1FFF) 및
Mini Shell의 32 KiB RAM(0x0000_0000–0x0000_7FFF)과 겹치지 않습니다.
RISC-V 코어는 일반 `LB`/`SB`/`LW`/`SW`로 접근하고, `rv32_soc.v`가 주소를
RAM disk 배열로 연결합니다. 현재 구현은 조합식 읽기를 위해 FPGA의
distributed RAM을 사용합니다.

| 블록 | 바이트 오프셋 | 용도 |
|---|---:|---|
| 0 | 0–511 | magic `MFS1`, 버전, 블록 개수·크기 |
| 1–2 | 512–1535 | 파일 엔트리 32개 × 24바이트 |
| 3–15 | 1536–8191 | 파일 데이터, 총 6656바이트 |

각 엔트리는 `name[16]`, `size`, `start_block`으로 구성됩니다. 파일 데이터는
연속된 512바이트 블록에 놓이며, 할당기는 다른 파일과 겹치지 않는 첫 연속 구간을
찾습니다. 따라서 총 여유 공간이 충분해도 단편화 때문에 큰 파일을 만들지 못할
수 있습니다. `fs_delete()`는 엔트리와 블록을 해제하지만 데이터 바이트를 지우지는
않습니다. 빈 파일은 `start_block=0`, `size=0`입니다.

펌웨어 API는 `firmware/minifs.h`에 있습니다:

```c
fs_init();                        /* magic이 없으면 포맷, 있으면 보존 */
fs_create("hello.txt");
fs_write("hello.txt", data, size); /* 기록한 바이트 수 또는 -1 */
fs_read("hello.txt", buf, cap);   /* 읽은 바이트 수 또는 -1 */
fs_delete("hello.txt");
fs_list(callback);                 /* 각 파일의 이름과 크기 전달 */
```

이름은 1–15바이트의 NUL 종료 문자열이며 공백과 `/`는 허용하지 않습니다.
`fs_read()`는 버퍼가 파일 전체보다 작으면 부분 읽기 없이 `-1`을 돌려줍니다.
`fs_write()`는 기존 파일의 내용을 전체 교체합니다. 실패 시에는 이전 파일의
메타데이터를 유지합니다. 여러 작업이 동시에 API를 직접 호출하는 경우를 위한
잠금은 없지만, 현재 OS의 파일 시스템 접근은 인터럽트가 비활성화된 trap handler
내의 `ecall` 서비스에서 직렬화됩니다.

| `a7` | 서비스 | 인수 | 반환 `a0` |
|---:|---|---|---|
| 4 | `SYS_FS_CREATE` | `a0=name` | 0 또는 -1 |
| 5 | `SYS_FS_WRITE` | `a0=name`, `a1=data`, `a2=size` | 바이트 수 또는 -1 |
| 6 | `SYS_FS_READ` | `a0=name`, `a1=buffer`, `a2=capacity` | 바이트 수 또는 -1 |
| 7 | `SYS_FS_DELETE` | `a0=name` | 0 또는 -1 |
| 8 | `SYS_FS_LIST` | 없음 | UART에 목록 출력, 0 |

task C는 부팅 후 `hello.txt`를 생성·기록·나열·읽기·삭제하고, 읽은 내용과
삭제 후 파일 부재를 확인해 `[MiniFS] PASS`를 출력합니다. 이후 기존처럼 `C`를
출력하고 `yield`합니다. task A/B의 출력이 데모 문자열 사이에 끼어드는 것은
선점형 스케줄링의 정상 동작입니다.

```bash
make mini-os
make sim-mini-os
```

시뮬레이션은 MiniFS 완료, timer IRQ, syscall, A/B/C 스케줄링을 검사합니다.
보드용 Mini OS bitstream에는 `make vivado-zcu104` 또는 Nexys A7의 Mini OS
설정을 사용합니다. ZCU104에서 입력 가능한 셸은 별도 이미지로
`make vivado-zcu104-shell`을 실행합니다. RAM disk는 CPU 리셋에서는 유지되지만
FPGA 재구성·전원 차단 후에는 사라집니다. 초기화 시 superblock이 없으면
자동 포맷합니다. 파일 권한·디렉터리·저널링·영구 저장 장치는 지원하지 않습니다.

Mini Shell에서 `cat`은 `fs_read_at()`을 통해 64바이트씩 읽으므로 큰 파일도
전체를 스택에 올리지 않습니다. `write`는 한 줄 텍스트로 파일 전체를 교체하며
없는 파일이면 먼저 생성합니다. 기본 셸 입력은 ASCII 한 줄 최대 95자입니다.
셸은 M-mode에서 동작하므로 입력 포인터를 격리하지 않는 교육용 구성입니다.
