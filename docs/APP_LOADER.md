# Mini Shell의 최소 실행 파일

프로세서·OS 원리부터 실제 명령어와 실습까지 다루는 교재는
[Shell과 바이너리 실행 상세 문서](SHELL_BINARY_GUIDE.md)와
[인쇄용 PDF](SHELL_BINARY_GUIDE.pdf)를 참고하세요.

이 버전은 ELF나 Linux 프로세스를 실행하지 않습니다. `app_main()`을
`0x0000_4000`에 고정 링크한 **RV32I flat binary**를 MiniFS 파일로 저장하고,
`run`이 그 바이트를 실행 가능한 RAM으로 복사해 함수처럼 호출합니다.
앱이 `return`하면 셸의 `rv> ` 프롬프트로 돌아옵니다.

| 주소 | 용도 |
|---|---|
| `0x0000_0000`–`0x0000_3FFF` | Mini Shell 코드·데이터·task stack |
| `0x0000_4000`–`0x0000_5FFF` | 앱 실행 창, 8 KiB |
| `0x0000_6000`–`0x0000_7FFF` | 커널 스택 예약 영역 |
| `0x8010_0000`–`0x8010_1FFF` | MiniFS RAM disk |

앱은 셸과 같은 M-mode와 같은 task stack을 사용합니다. 메모리 보호·프로세스
격리·앱별 스케줄링은 없습니다. 신뢰할 수 없는 파일은 **실행하지 마세요**.
이 첫 버전은 앱의 `.bss`가 없어야 하고, libc 없이 `-march=rv32i
-mabi=ilp32`로 빌드해야 합니다. 예제는 [hello_app.c](../firmware/hello_app.c)입니다.

```bash
make hello-app          # build/firmware/hello_app.bin, 0x4000에 링크
make sim-shell          # 실제 RV32I core가 파일에서 앱을 로드·실행·복귀하는지 검사
make vivado-zcu104-shell
make test-zcu104-app    # 실제 보드 재구성, 업로드, run까지 자동 검사
```

이미 새 셸 비트스트림이 보드에서 실행 중이라면, UART 터미널을 닫고 다음만
실행해도 됩니다.

```bash
python3 scripts/upload_app.py --file build/firmware/hello_app.bin --name hello.app --run
```

앱은 `SYS_PUTC=1`을 `ecall`로 호출해 `Hello from loaded app!`를 출력한 뒤
정상 반환합니다. `upload` 명령은 파일 이름, 바이너리 바이트 수, 8자리
16진수 byte-sum을 받은 뒤 ASCII hex를 스트리밍으로 수신합니다. 호스트 스크립트가
이를 자동으로 처리합니다. MiniFS 파일은 12바이트의 `APP1` 헤더(매직, payload
크기, byte-sum)와 payload로 구성됩니다. `run`은 헤더·길이·checksum을 확인한
뒤 payload를 `0x4000`에 복사합니다. 앱 payload 최대 크기는 **6644바이트**입니다.

현재 앱 ABI의 한계: 고정 주소만 지원하며 재배치, ELF 로딩, `.bss` 초기화,
인수 전달, 사용자 모드, 메모리 보호, 비정상 종료 복구는 없습니다. 앱이 반환하지
않거나 불법 명령을 실행하면 셸로 돌아오지 않을 수 있습니다. 앱 코드와 파일은
전원 차단 또는 FPGA 재구성 후 사라집니다.
