# Changelog

## [Unreleased]

### Added

- **`clipboard-rejoin-wrapped-rows` (기본 ON · box-drawing 예외) — 풀스크린 TUI 앱의
  자체 word-wrap 줄을 복사 시 한 줄로 재결합.** terminal 자동-wrap("줄내림",
  `row.wrap = true`)은 이미 정상적으로 재결합되지만(1.4.2 진단 참고), codex 등
  ratatui 기반 풀스크린 TUI 앱은 **자체 word-aware wrapping** 으로 각 시각적
  줄을 개별 행으로 그리며 wrap 플래그를 세우지 않는다(`row.wrap = false`).
  증거: 제보된 깨짐이 단어 경계("…link to" → "authenticate:")에서 끊겼는데,
  이는 셀 기반 자동-wrap 으로는 불가능하고 앱의 word-wrap 만 만들 수 있는
  형태다. 이 행들의 개행은 터미널 입장에서 "진짜"이므로 기존 소프트랩 경로로는
  재결합할 수 없다. 새 옵션을 켜면(opt-in heuristic) 선택된 행 중 **우측 마진까지
  꽉 찬 행**(마지막 셀에 텍스트가 있는 행, spacer_tail 은 wide head 로 환원)의
  개행을 억제해 다음 행과 이어 붙인다. URL 처럼 폭을 꽉 채운 줄은 한 줄로
  재결합되고, 마진 전에 끝나는(뒤에 공백이 남는) 짧은 word-wrap 산문 줄은 그대로
  개행을 유지한다. ASCII 표·박스 테두리(box-drawing/block-element U+2500..U+259F가 마지막 글자인 행)는 재결합에서 제외. 기본값은 `true`(켜짐) · `false` 로 두면 기존 복사 동작과 100% 동일하므로 회귀
  없음. 구현은 출력 문자열 후처리(행 폭 기하 정보 손실)가 아니라
  `formatter.zig` 의 unwrap 지점에 **가산(additive)** 조건으로 더해, 진짜
  소프트랩 재결합 경로는 손대지 않았다. (void/clipboard-rejoin-wrapped-rows)

## [1.4.3] — 2026-05-31

### Fixed

- **`hx install void` now installs the `xterm-void` terminfo into `~/.terminfo`
  automatically.** Previously the terminfo entry only lived inside the app
  bundle (`Void.app/Contents/Resources/terminfo/`), reachable solely via the
  `TERMINFO` env that Void.app exports to its own child shells. Any shell
  outside that env — a plain login shell, tmux, or an incoming SSH session that
  inherited `TERM=xterm-void` — hit `'xterm-void': unknown terminal type` on
  `clear`, `vim`, `less`, and every other terminfo-driven program. The install
  hook (`install.hexa`) now runs `tic -x -o ~/.terminfo` on the bundled
  terminfo source after installing the app, so `xterm-void` resolves
  system-wide. Best-effort: skipped silently if `tic` (ncurses) is unavailable.
  Mirrors the `ssh-terminfo` shell-integration feature's own `~/.terminfo`
  target. Reversible via `rm -rf ~/.terminfo`.

## [1.4.2] — 2026-05-31

### Tests

- **소프트랩 복사 동작 진단 — 코드는 이미 정상, 회귀 테스트 추가.** 소프트랩
  (terminal auto-wrap · "줄내림")된 한 줄을 복사하면 wrap 지점마다 하드 개행이
  끼어든다는 제보를 진단함. 복사 경로(`Screen.selectionString` ·
  `Surface.copySelectionToClipboards`)는 이미 `unwrap = true` 이고,
  `formatter.zig` 의 wrap 재결합 로직(`if (!row.wrap or !self.opts.unwrap)
  blank_rows += 1;`)도 정상이라 소프트랩은 이미 한 줄로 재결합되고 실제 하드
  개행(`\n`)만 보존됨. 기존/신규 테스트 전부 통과(82/82)하며 코드 결함을
  재현할 수 없음 → **동작 변경 없음**. 제보된 시나리오를 못박는 회귀 테스트
  2개 추가: 멀티-로우 소프트랩 한 줄이 개행 없이 재결합되는지(`soft wrap
  multi-row rejoin`), 소프트랩 뒤 실제 하드 개행이 보존되는지(`soft wrap then
  hard newline`). 사용자 측 텍스트에 실제 하드 개행이 들어있었거나 다른 터미널
  설정이 원인일 가능성이 높음(void 복사 경로 자체는 올바름). (void/fix-softwrap-copy)
- **런타임 자동-wrap 복사 회귀 테스트 추가.** 위 진단은 `testWriteString`(이미
  wrap 플래그가 박힌 더미) 기준이었음. 실제 렌더러 경로(`Terminal.print` →
  화면 폭 초과 시 `row.wrap` 세팅)로 폭 5칸에 15자를 입력해 3줄로 자동 wrap시킨
  뒤 `selectAll` → `selectionString` 복사가 개행 없이 한 줄(`ABCDEFGHIJKLMNO`)로
  재결합되는지 검증하는 테스트를 `Terminal.zig` 에 추가. 통과 — 화면 폭과 무관히
  코어 복사 경로가 런타임 소프트랩을 정상 재결합함을 확정.

## [1.4.1] — 2026-05-31

### Fixed

- **fix(input): HHKB word-erase 키바인드 폐기 — backspace 가 표준 0x7F 로 복귀.**
  fork 가 추가했던 physical backspace/delete 인터셉트 그룹 4개(Ctrl+Delete/
  Ctrl+Backspace → `\x01\x0b` 라인-킬 · Alt+Backspace → `\x17` 워드-킬 ·
  Alt+Delete → ESC-d) 와 macOS Swift 측 keyDown 재작성 클로저
  (`VoidCtrlEraseLine` · `VoidAltEraseWord` · `VoidConfigBool` 소비자 없어 함께
  제거) 를 전부 폐기. HHKB(Delete 키가 backspace 위치) 사용자가 SSH 환경에서
  backspace 가 공백 삽입/워드-킬로 오동작하던 문제 수정. 업스트림 Ghostty 표준
  backspace 경로(`key_encode.zig` → 0x7F) · `macos-option-as-alt` ·
  cmd+g grid 예약 · navigate_search 리맵은 그대로 유지. (#30)

## [1.4.0] — 2026-05-31

fork 가 직접 구현한 비정상 종료 세션 복구(P7 / session-restore) 레이어를 전부
폐기. 업스트림 Ghostty 표준 AppKit 윈도우 복원은 그대로 유지되므로, 기본 설정
사용자 입장에서 윈도우/탭 복원 동작은 변하지 않습니다.

### Removed

- **P7 비정상 종료 세션 복구 레이어 전체 폐기.** 미출시(Unreleased) 상태에서
  도입됐던 기능 일체 제거:
  - **신규 파일 삭제** — `macos/Sources/Defense/` 서브시스템 전체(CrashCapture ·
    SessionSnapshot · DefenseCoordinator · PressureMonitor · README; 소비자가
    세션 복구 전용) · `SessionManifest.swift` · `src/termio/PersistRing.zig` ·
    P7 테스트(SessionManifestTriage/Reclaim) · recovery CLI 툴
    (`tool/void-session-recover.sh` · `void-session-replay.sh` ·
    `test-void-session-recover.sh`) · 설계/로그 문서(`SESSION-RESTORE.md` ·
    `SESSION-RESTORE.log.md` · `docs/design/sighup-resistant-session.md`).
  - **와이어링 절제** — Termio/Exec 의 persist-ring(append · msync 타이머 ·
    replay subprocess-skip `startNoFork`) · `surface_uuid` 패스스루(Surface.zig ·
    embedded.zig · `include/void.h` · SurfaceView 브리지) · AppDelegate
    triage/silent-loss 알림/orphan auto-GC · BaseTerminalController manifest
    refresh · TerminalRestorable `didRestoreAnyWindow` 플래그.
  - **설정 키 삭제** — `session-orphan-gc-threshold` · `persist-bytes-mmap`.
  - **로드맵 잔재 삭제** — `.roadmap.session_persistence`(P7 도메인 SSOT) ·
    `.next-session`(stale 핸드오프 노트). (#27)
- **보존** — 업스트림 AppKit 윈도우 복원(`TerminalRestorable` NSWindowRestoration
  · `QuickTerminalRestorableState` · `window-save-state` 설정 키)은 그대로 유지.

## [P7 도입 배치] — 2026-05-24 (위 Removed 로 폐기됨)

세션 복원(P7 Phase B2) 후속 배치. 기본 설정 사용자는 동작 변경 없음 — 단,
이전에 stranded ring 파일이 남아 있던 경우에만 새 알림이 노출됩니다.
비파괴(non-breaking) 개선 묶음.

### Added

- **inbox/ → `INBOX` 도메인 이관** — cross-project handoff 를
  `inbox/<kind>/<slug>.md` 폴더에서 repo 루트의 `INBOX` 도메인 1쌍(`INBOX.md`
  스냅샷 + `INBOX.log.md` append-only 로그)으로 전환 (pool · sidecar 의
  inbox→INBOX 폐기와 정합 · `cd <repo> && /domain set INBOX` 로 관리). 기존 1건
  이관 — VoidTests 타깃 빌드 실패(Xcode 26.5)는 explicit-modules가 아닌
  리브랜딩 잔재였고, import/네임스페이스 정합 + 헤드리스 테스트 분리로 #19
  해소(mini 7/7 + 10/10 passed) → `INBOX.log.md` 에 `- [x]`. `inbox/` 폴더
  삭제.
- **Silent-loss session 알림** (`macos`): AppKit이 직전 세션의 surface tree를
  복원하지 못했지만 ring 파일은 디스크에 남아있을 때, 500ms triage 콜백 시점에
  NSAlert 모달로 표면화. 버튼: **Copy UUIDs** (pasteboard) · **Open Ring
  Folder** (Finder) · **Dismiss**. 정상 복원 경로에서는 무노출 — stranded
  ring이 실제로 존재할 때만 뜸.
- **`~/.void/sessions/by-uuid/` orphan ring 보수적 auto-GC**: disk에 ring
  파일이 있는데 어느 prior session manifest에서도 참조하지 않은(진짜 버려진)
  UUID만 대상. `~/.void/sessions/gc-counter.json`에 누적되어 임계값(기본 3회
  연속 launch) 도달 시 삭제. `topologyLost` ring은 절대 건드리지 않음 ·
  launch당 최대 50개 삭제 cap. 설정: `session-orphan-gc-threshold` (기본 `3`,
  `0`으로 비활성).
- **`tool/void-session-recover.sh`**: stranded ring 파일의 tail에서 마지막
  cwd를 추출해, UUID만으로 "어떤 작업이었는지" preview. POSIX-portable, ANSI
  / control sequence strip 후 last existing directory 우선. silent-loss
  alert의 **Copy UUIDs**와 짝지어 사용 의도.
- **PersistRing 헤더에 `last_msync_ns: u64`**: 이전 `_reserved [8]u8` 영역을
  monotonic ns timestamp로 전환. msync 직후 release-store, `lastMsyncNs()`
  accessor로 acquire-load. **헤더 크기 32 bytes 유지 — 기존 ring file과 호환**.
  향후 ring freshness 판정(오래된 stranded vs 직전 세션)의 기반.

### Internal

- `HACKING.md`: zig 0.15.2 + macOS 26.5 Tahoe SDK 빌드 환경 gotcha 4
  sub-section 추가 (brew zig 0.16.0 ↔ `build.zig.zon` 0.15.2 핀 충돌,
  standalone 0.15.2 tarball ↔ Tahoe SDK linker ABI 불일치, 작동 조합,
  login-shell PATH 필요성).
- `docs/issues/2026-05-23-mac-reopen-hang.md`: "예기치 않게 종료된 앱을 다시
  열까요?" 다이얼로그 클릭 후 hang 이슈 진행 추적 (mini.local 재현 실패,
  의심 후보 3-row table).
- `SESSION-RESTORE.md` / `SESSION-RESTORE.log.md`: mini.local end-to-end
  Phase B2 auto-replay 검증 기록(checkpoint A→F · ring.replay →
  processOutputLocked → PTY 바이트 재현). NSWindowRestoration이 saved-state
  디렉토리 부재에도 동일 surface UUID를 재할당하는 메커니즘은 open Q로 남김
  (NSPersistent / cfprefsd / mach 후보).

## PLAN absorption + UPPERCASE — 2026-05-22

`PLAN.md` was a single-domain design doc (session-restore gap closure for P7
Phase B2) misnamed as a generic plan. Absorbed into a proper UPPERCASE domain
pair:

- `PLAN.md` → `SESSION-RESTORE.md` (live spec — gap analysis, patch v1 design,
  what's left, open questions).
- `PLAN.log.md` → `SESSION-RESTORE.log.md` (history — verification snapshot,
  cross-host build env, decision log).

Internal cross-references updated. No standalone `PLAN.md` remains.

## docs split — 2026-05-22

Per-domain spec/history file split applied to root-level `*.md` files (sidecar
commons @D g29):

- `PLAN.md` (mixed) — kept current spec (gap analysis, patch v1 design, what's
  left, open questions, related work). Extracted history-flavored sections to
  new `PLAN.log.md`: 2026-05-21 verification snapshot, cross-host build
  environment notes (mini), and the dated decision log.
- `LIMIT_BREAKTHROUGH.md` — pure current-state audit snapshot (§1 domain ID,
  §2 limits table, §3 per-limit assessment, §4 top opportunities, §6 refs).
  Left alone.
- `TAPE-AUDIT.md` — current snapshot (verdict block). Left alone.
- All other root `*.md` files (`AI_POLICY`, `CHANGELOG`, `CLAUDE`,
  `CONTRIBUTING`, `HACKING`, `LATTICE_POLICY`, `PACKAGING`, `README`,
  `VOID_FORK`) — left alone per the rule's keep-list.

## void hard-fork — 2026-04-25

void is a **hard-fork** of [Ghostty](https://github.com/ghostty-org/ghostty)
(Mitchell Hashimoto, MIT License). The `upstream` git remote has been removed;
subsequent changes are not eligible for upstream merge.

**Fork cutoff:** upstream commit `c3c8572f7` ("update zon2nix #12337"). At fork
time, `void/main` was 92 commits ahead of `upstream/main` and shared this
single merge base.

**Identity sweep applied 2026-04-25** (this commit):

- macOS bundle identifier namespace: `com.mitchellh.*` → `com.dancinlab.*`
  (Xcode `PRODUCT_BUNDLE_IDENTIFIER`, `CFBundleIdentifier`,
  `src/build_config.zig` `bundle_id`, all Swift `Notification.Name` /
  `UserDefaults(suiteName:)` / `UTType` / `NSPasteboard` / menu identifiers)
- GTK D-Bus base application id: `com.mitchellh.void` → `com.dancinlab.void`
  (`src/apprt/gtk/build/info.zig`, all GTK class application/window/surface
  refs, `inspector-window.blp` icon, `ipc/new_window.zig` doc examples)
- Linux distribution paths: flatpak/snap/desktop/metainfo/icon install paths
  rebased to `com.dancinlab.void`
- gettext domain: `com.mitchellh.void` → `com.dancinlab.void`
  (`src/build/VoidI18n.zig`, all 53 locale `.po` headers, `.pot` rename)
- Renamed files to match new namespace:
  - `flatpak/com.mitchellh.void.yml` → `flatpak/com.dancinlab.void.yml`
  - `flatpak/com.mitchellh.void-debug.yml` → `flatpak/com.dancinlab.void-debug.yml`
  - `dist/linux/com.mitchellh.void.metainfo.xml.in` → `dist/linux/com.dancinlab.void.metainfo.xml.in`
  - `po/com.mitchellh.void.pot` → `po/com.dancinlab.void.pot`

**Not touched** (out of scope, separate cleanup):

- `com.mitchellh.ghostty` residue in `dist/linux/ghostty_nautilus.py`,
  `.github/workflows/flatpak.yml`, `.github/scripts/check-translations.sh`
  — these are pre-existing stale references from the original `Ghostty → Void`
  L3 rename (commit `964c9e32e`, 2026-04-21) that point at filenames which no
  longer exist; they will be cleaned up in a follow-up identity-cleanup commit.
- `com.mitchellh.fullscreenDidEnter` / `…DidExit` Notification names were also
  rebased in this sweep (internal namespace, no API contract).

**User-data migration on macOS:**

Existing TCC permissions (Full Disk Access, Accessibility, Automation) were
granted to `com.mitchellh.void` and do **not** transfer to
`com.dancinlab.void`. Re-grant is required after this fork. The bundled
`install.hexa` already runs `tccutil reset All` against the new bundle id;
the user must approve permission prompts on first launch of the rebuilt app.

User defaults stored under `com.mitchellh.void` (window state, custom icon,
preferences) will not be inherited by the new bundle id. This is intentional:
the new identity is a clean slate.

**Attribution preserved:**

- License: MIT (unchanged)
- Original copyright: Mitchell Hashimoto and the Ghostty contributors
- Source code ghostty references intentionally retained where they describe
  inherited behavior, vendored dependency hashes (`deps.files.ghostty.org`),
  C-ABI compatibility surface (`libghostty` → `libvoid` rename complete; old
  symbol names preserved where required for ABI stability), and benchmark
  comparison context (Δ vs ghostty perf budget per `README.md`).
- The original Ghostty git history is preserved on the `origin` remote
  (`dancinlab/void`); see `git log` for the unbroken chain back to the
  initial Ghostty commit.

## upstream Ghostty history — preserved below for attribution

Pre-fork commits inherit Ghostty's release notes; refer to
[ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) tags up to
`c3c8572f7` for the canonical pre-fork changelog. void-specific divergence
prior to this hard-fork declaration lives in `git log upstream/main..HEAD`
(92 commits, 2026-04-21 → 2026-04-25), starting from the L3 rename commit
`964c9e32e` ("Ghostty → Void rebrand").
