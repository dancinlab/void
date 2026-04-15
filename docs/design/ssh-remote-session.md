# SSH 원격 세션 — 설계 리서치

Status: research-only (Task #31, BACKLOG)
Phase target: 5 (UI/Layout 병행)
Author: design doc, no implementation

## 1. Goal

VOID 탭 하나를 원격 셸로 사용한다. 사용자는 탭 생성 시 호스트를 지정하면 해당 탭의 PTY 뒤에 `ssh host` 프로세스가 붙어, 로컬 셸 탭과 동일한 입출력 모델(grid + vt_parser + ansi 렌더) 위에서 동작한다. 원격 세션의 키 입력, 리사이즈, 스크롤백, 마우스 트래킹, void-protocol 감지는 로컬 탭과 동일한 경로를 재사용한다.

비목표가 아닌 최소 성공 기준:
- `ssh user@host` 상당 기능을 탭 안에서 쓴다.
- 세션 종료 시 탭이 자연스럽게 닫힌다.
- 리사이즈(SIGWINCH) 전파가 동작한다 (PTY 슬레이브가 원격에 winsize를 전달).

## 2. Constraints

- HEXA-FIRST: `.hexa` 외 새 파일 금지. 신규 extern FFI는 가급적 없음.
- L0 보호: `core/sys/pty.hexa`, `core/sys/term.hexa`, 기타 L0 파일은 수정 금지. 신규 API는 L1/Layer 4(ui)에만 추가.
- 6-layer: 원격 세션은 Layer 1(PTY)에서 프로세스 교체만 일어나고, Layer 3(vt/grid)부터는 로컬과 동일 경로를 탄다. 새 레이어 없음.
- 보안/자격증명 저장 금지: VOID 내부에 비밀번호/키를 저장하지 않는다.

## 3. Options considered

### Option A — `ssh` 바이너리를 서브프로세스로 PTY에 붙인다

로컬 셸 대신 `execvp("ssh", ["ssh", host, ...])`를 자식 프로세스에서 호출한다. 기존 `pty_open` + fork/dup2 경로를 그대로 쓰고, `execl(shell, ...)` 자리만 `ssh` 호출로 바꾸면 된다. pty.hexa는 L0이므로 수정 불가 — 대신 tab_mux에서 새 함수 `mux_spawn_remote`가 직접 동일한 fork/exec 패턴을 쓰거나, pty.hexa에 `pty_spawn_cmd(argv)` 같은 일반화 API 추가 여부는 별도 승인 대상.

Pros:
- 프로토콜 코드 0 LOC. SSH2 transport/auth/channel 전부 OpenSSH에 위임.
- known_hosts / ssh-agent / ssh_config / ProxyJump / ControlMaster 자동 상속.
- 기존 vt_parser/grid/ansi 경로 100% 재사용. 리사이즈는 PTY 마스터에 `ioctl(TIOCSWINSZ)`만 전달하면 OpenSSH가 SSH `window-change` 메시지로 번역.
- 디버깅 용이: 실패 시 셸에서 동일 명령으로 재현 가능.

Cons:
- `ssh` 바이너리 의존 (macOS/Linux 모두 기본 제공이므로 현실적으로 무부담).
- Conductor-style (iTerm2) 원격 파일 핸들링 같은 advanced 기능은 불가 — 단일 스트림만.
- 재연결 시 전체 셸 히스토리 손실 (원격 세션 상태는 서버 쪽에 없음).

### Option B — libssh2 / libssh extern FFI

`.hexa`에서 `extern fn ssh2_*` 선언을 두고 libssh2를 링크한다. 자체 소켓을 열고 transport/userauth/channel-exec를 직접 돌린다.

Pros:
- 서브프로세스 없음. 단일 프로세스 내 세션 관리.
- advanced: SFTP, port forward, exec 채널 다중화, agent 프로토콜 직접 조작 가능.
- 재연결/keepalive를 VOID가 직접 제어.

Cons:
- 새 C 의존성 추가 (libssh2 + openssl/libressl). macOS에 기본 없음.
- "HEXA-only" 원칙과 충돌. extern 표면 수십 개 증가.
- known_hosts/ssh_config 재구현 또는 우회 필요.
- 보안 부담: crypto 라이브러리 취약점이 VOID 프로세스 보안 경계.

### Option C — 순수 HEXA SSH2 구현

`core/net/ssh/` 아래에 transport(chacha20-poly1305/ed25519), userauth, channel 레이어를 모두 `.hexa`로 작성.

Pros:
- 100% HEXA. 의존성 완벽 제로.
- 장기적으로 VOID만의 프로토콜 최적화 여지 (void-protocol과 상호작용).

Cons:
- 스코프가 터미널 에뮬레이터 본체와 맞먹음. crypto primitive부터 필요.
- 감사되지 않은 crypto → 실제 사용 불가 수준의 위험.
- Phase 5 범위를 한참 벗어남. 최소 분기 단위의 작업.

## 4. Recommendation

**Option A를 Phase 5에서 채택한다.** 이유:

1. 새 extern 0개로 가능 (tab_mux가 pty.hexa의 공개 API만 쓰는 기존 경계 유지).
2. 즉시 사용 가능. 사용자 관점에서 "탭 하나 열고 원격 접속"이 바로 성립.
3. iTerm2도 기본 경로는 동일한 모델 — `ssh` 프로세스를 PTY에 붙이고 그 위에 선택적 헬퍼(Conductor)를 얹는다. 업계 검증된 접근.
4. B/C는 향후 벡터로 남긴다 — SFTP 패널이나 네이티브 재연결 UX가 필요해지면 그때 B를 얹는다. Option A는 B의 전제와 충돌하지 않는다 (공존 가능).

## 5. Integration points

아래는 변경될 파일과 새 공개 함수 목록. L0는 건드리지 않는다.

### 5.1 `ui/tab_mux.hexa` (수정 — 공개 API 추가)

신규 함수:

```
pub fn mux_spawn_remote(ring: map, grid_rows: int, grid_cols: int, host: string) -> map
```

구현 스케치:
- `pty_open()` 호출해 master/slave 확보.
- 자식 프로세스에서 `execvp("ssh", ["ssh", host])`를 호출해야 하는데, 현재 pty.hexa의 `pty_spawn_shell`은 `$SHELL`을 하드코딩 — 재사용 불가.
- 해결책 두 가지 (승인 필요):
  - **(A1) pty.hexa에 `pty_spawn_cmd(master, slave, argv: []string) -> int` 신규 공개 함수 추가.** L0 변경이므로 유저 명시 승인 필요. 가장 깔끔.
  - **(A2) tab_mux가 자체적으로 fork/dup2/execvp를 호출.** 이 경우 tab_mux에 fork/setsid/dup2/close/execvp extern을 재선언해야 하므로 중복. pty.hexa의 L0 경계를 더럽힘.
- A1을 권장. core-lockdown.json에 "pty_spawn_cmd 추가는 L0 확장이며 기존 함수 변경 없음"으로 명시.
- 나머지 grid/parser/tab 바인딩은 `mux_spawn`과 동일.

탭 레코드에 원격 메타 저장:
```
tab["kind"] = "remote"   // or "local"
tab["remote_host"] = host
```

### 5.2 `ui/tab_input.hexa` (수정)

- 새 키 바인딩: `Alt+s` → 인라인 미니 프롬프트(단일 라인 입력, statusbar 자리 재사용) → Enter 시 `mux_spawn_remote(ring, rows, cols, entered_host)` 호출.
- 기존 탭 생성 키(`Ctrl+t` 등)는 `mux_spawn` 그대로.

### 5.3 `ui/tab_session.hexa` (수정)

- 직렬화 시 `kind`, `remote_host` 필드 포함.
- 복원 시 `kind == "remote"`면 `mux_spawn_remote(..., remote_host)`로 재스폰. 원격 서버 상태는 저장하지 않음 (fresh 재접속).

### 5.4 렌더 / VT / 마우스 — 변경 없음

원격 셸이 내려보내는 바이트 스트림은 로컬과 동일하게 `vt_process`를 통과한다. 변경 불필요.

### 5.5 리사이즈 전파

기존 main 이벤트 루프의 resize 감지 부분은 grid만 리사이즈하고 있다. PTY 마스터에 `ioctl(TIOCSWINSZ, &winsize)`를 쏘는 코드가 현재 누락(로컬 탭도 동일 이슈). 이 누락은 Task #31 범위를 벗어나지만, 원격의 경우 OpenSSH가 `window-change`로 릴레이해주기 때문에 이 ioctl만 들어가면 양쪽이 동시에 해결된다. 별도 태스크로 분리 권장 (`pty_resize(master, rows, cols)` 추가 — L0 확장).

## 6. Security model

- **자격증명 저장 금지.** VOID는 host string만 안다. 키/암호는 전혀 취급하지 않는다.
- **ssh-agent 상속.** 자식 프로세스가 `SSH_AUTH_SOCK` 환경을 상속받으므로 별도 처리 불필요.
- **known_hosts.** OpenSSH가 처리. 첫 접속 시 fingerprint 프롬프트가 PTY 스트림으로 그대로 탭에 나타나고, 사용자가 `yes` 입력 — 로컬 셸 체험과 동일.
- **sshconfig.** `~/.ssh/config`의 alias/ProxyJump/IdentityFile/ControlMaster가 자동 적용됨. VOID가 `-F` 등 재정의하지 않는다.
- **프로세스 격리.** 원격 탭은 일반 자식 프로세스로 동작. VOID 프로세스 메모리에 원격 트래픽이 평문으로 존재하지 않음 (커널 PTY 버퍼만 경유).

## 7. Open questions

1. **SIGWINCH 전파.** 현재 로컬 탭도 PTY winsize를 업데이트하지 않는 것으로 보인다. `pty_resize` 추가 필요 여부 확인 — 로컬/원격 공통.
2. **void-protocol 충돌.** VOID의 void-protocol이 ESC 시퀀스를 사용한다면 원격 셸이 같은 시퀀스를 내보낼 때 오탐지 위험. 원격 탭에서는 void-protocol 해석을 끄거나, 호스트별 네임스페이스를 요구할지 결정 필요.
3. **SSH escape `~.`.** OpenSSH 클라이언트의 `~` escape가 VOID 키 입력과 충돌할 수 있음 (줄 첫 머리에서만 해석되므로 현실 영향은 낮음). 문서화로 충분.
4. **재연결 UX.** 원격 세션이 끊어졌을 때 탭을 자동으로 닫을지, "[disconnected — press r to reconnect]" 상태를 보여줄지. Phase 5 초기는 자동 종료로 단순화 권장.
5. **로케일/TERM.** 원격에 `TERM=xterm-256color`로 올릴지, VOID 전용 `TERM=void`를 쓸지. 초기엔 xterm-256color로 호환성 확보.

## 8. Non-goals for this task

- SFTP / 파일 업로드 / 드래그앤드롭
- 포트 포워딩 (-L, -R, -D)
- 멀티플렉서-over-ssh attach 자동 감지
- Mosh 지원
- 자체 재연결 / keepalive 로직
- GUI 호스트 매니저 / 북마크 (별도 Phase 5/6 UI 태스크)
- 자격증명 프롬프트를 VOID 내부 UI로 가로채기

## 9. Effort estimate

**Small.** Option A 기준 실제 변경:

| 영역 | 변경 | 규모 |
|---|---|---|
| `core/sys/pty.hexa` | `pty_spawn_cmd(master, slave, argv)` 추가 (L0 확장, 승인 필요) | ~15 LOC |
| `ui/tab_mux.hexa` | `mux_spawn_remote` 추가 | ~20 LOC |
| `ui/tab_input.hexa` | Alt+s 바인딩 + 미니 프롬프트 | ~40 LOC |
| `ui/tab_session.hexa` | `kind`/`remote_host` 직렬화 | ~10 LOC |
| 합계 | 신규 공개 fn 3개 | **~85 LOC** |

전제: `pty_resize` 작업이 별도 태스크로 분리된다. 승인 포인트는 pty.hexa L0 확장 1건.

## 10. iTerm2 reference

iTerm2는 원격 세션을 기본적으로 "로컬 탭에서 `ssh host` 서브프로세스를 PTY에 붙이는" 모델로 구현한다 — 즉 Option A와 동일한 뼈대다. 그 위에 **Conductor**라는 헬퍼 레이어(`Conductor+SSHEndpoint.swift`, `Conductor+SSHCommandRunning.swift`)를 얹어, 첫 접속 시 원격에 Python-ish framer 스크립트를 업로드하고, 이후 동일한 ssh 스트림을 in-band 프레이밍으로 다중화해서 파일 목록, 디렉토리 트래커, SCP, SSHEndpoint(파일 패널) 같은 advanced 기능을 구현한다. 즉 transport는 stock OpenSSH를 쓰고, VT 스트림과 제어 스트림을 같은 PTY 위에서 프레임으로 나누는 방식이다. 이 모델의 장점은 known_hosts/agent/config를 전혀 재구현하지 않으면서 advanced 기능을 점진적으로 얹을 수 있다는 점 — VOID가 향후 Option A → A+Conductor-유사 레이어로 확장할 수 있는 정확한 근거가 된다. 참고 파일: `Conductor+SSHEndpoint.swift`, `SSHEndpoint.swift`, `ParsedSSHArguments.swift`, `SSHIdentity.swift`, `iTermSSHHelpers.h/m`.
