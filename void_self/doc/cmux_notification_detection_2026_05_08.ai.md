---
schema: void/research/cmux_notification/1
last_updated: 2026-05-08
ssot: void_self/doc/cmux_notification_detection_2026_05_08.ai.md
upstream_repo: https://github.com/manaflow-ai/cmux
upstream_clone: /tmp/cmux (depth=1, 2026-05-08)
related_doc:
  - .roadmap.ai_native_io
status: research
session_type: investigation
budget: $0 mac-local
destructive_ops: 0
---

# cmux notification detection — research note (2026-05-08)

## TL;DR

cmux 가 "Claude Code TUI 응답 종료" 를 감지하는 방식은 **TUI 파싱이 아니라 명시적 시그널** 이다. 세 경로:

1. 에이전트 native hook 시스템에 `cmux notify` 주입 (주력)
2. CLI → Unix socket → Swift 앱 (`v2NotificationCreateForCaller`)
3. libghostty 가 OSC 9/99/777 escape sequence 직접 캐치 (보조)

per-surface 라우팅은 자식 셸에 주입한 `CMUX_SOCKET_PATH` / `CMUX_TAB_ID` / `CMUX_PANEL_ID` env 로 처리.

Void 에 이식하려면 동등한 4-스택 필요: `void notify` CLI + 소켓, 환경변수 주입, 에이전트별 `void hooks setup`, macOS UNUserNotificationCenter + tab/pane indicator UI.

## §1 감지 경로

### (1) Agent native hook → `cmux notify` 주입 (주력)

cmux 는 에이전트별로 **두 가지 다른 주입 방식**을 사용한다. Claude Code 는 wrapper 만, 나머지 10종은 native config 파일 직접 write.

#### (1a) Claude Code — wrapper 스크립트로 inline 주입 (파일 안 건드림)

**파일**: `Resources/bin/claude` (cmux 앱 번들 내부) — PATH 에 prepend 되어 사용자의 `claude` 명령을 가로챔.

**핵심 동작** (`Resources/bin/claude:320`):

```bash
HOOKS_JSON='{"preferredNotifChannel":"notifications_disabled","hooks":{"SessionStart":[...],"Stop":[...],"Notification":[...],"PreToolUse":[...],"PermissionRequest":[...],"UserPromptSubmit":[...],"SessionEnd":[...]}}'

if [[ "$SKIP_SESSION_ID" == true ]]; then
    exec "$REAL_CLAUDE" --settings "$HOOKS_JSON" "$@"
else
    SESSION_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
    exec "$REAL_CLAUDE" --session-id "$SESSION_ID" --settings "$HOOKS_JSON" "$@"
fi
```

각 hook command 패턴: `"${CMUX_CLAUDE_HOOK_CMUX_BIN:-cmux}" hooks claude <event>` (event = `session-start` / `stop` / `notification` / `prompt-submit` / `pre-tool-use` / `session-end`). cmux CLI 가 stdin 으로 Claude 의 hook payload 받아 소켓으로 forwarding.

**왜 wrapper 만으로 충분한가**: Claude Code 가 `--settings <inline JSON>` 플래그를 native 지원하고, 사용자의 `~/.claude/settings.json` 과 **additively merge** 해줌. 따라서 file write 없이 inline 주입 가능 → 사용자 settings 파일 무손상.

**Pass-through 가드** (`:142-151`):
- `CMUX_SURFACE_ID` 없음 (non-cmux 셸) → 즉시 `exec REAL_CLAUDE "$@"`
- `CMUX_CLAUDE_HOOKS_DISABLED=1` → pass-through
- cmux 소켓 unreachable (stale env / 앱 종료) → pass-through

**부가 동작**:
- `preferredNotifChannel: "notifications_disabled"` 로 Claude 의 OSC 알림 끔 → hook 만이 단일 소스
- session id 도 wrapper 가 uuidgen 으로 생성해서 `--session-id` 주입 (재시작 시 resume 용)
- `unset CLAUDECODE` 로 nested-session detection 방지
- `NODE_OPTIONS` 에 `--require=<restore-module>` + `--max-old-space-size=4096` 주입 (Claude 가 Node 자식 띄울 때 메모리 4G 보장)
- `CMUX_CLAUDE_PID` / `CMUX_AGENT_LAUNCH_*` env 로 PID/argv 보존 (stale-session detection + restore)

#### (1b) 다른 10종 에이전트 — native config 파일에 직접 write

`cmux hooks setup` 이 각 에이전트의 native hook 파일에 entry 를 추가/제거. 정의는 `CLI/cmux.swift:15724` `agentDefs` 배열.

| Agent | Binary | 쓰는 파일 | format | events |
|---|---|---|---|---|
| Codex | `codex` | `~/.codex/hooks.json` + `~/.codex/config.toml` | nested(5000ms) | SessionStart / UserPromptSubmit / Stop |
| OpenCode | `opencode` | `~/.config/opencode/plugins/cmux-session.js` + `cmux-feed.js` | flat | (plugin event bus) |
| Pi | `pi` | `~/.pi/agent/extensions/cmux-session.ts` | flat | (extension) |
| Cursor CLI | `cursor-agent` | `~/.cursor/hooks.json` | flat | beforeSubmitPrompt / stop / afterAgentResponse / before/afterShellExecution |
| Gemini | `gemini` | `~/.gemini/settings.json` | nested(10000ms) | SessionStart / BeforeAgent / AfterAgent / SessionEnd |
| Rovo Dev | `acli` | `~/.rovodev/config.yml` | rovoDevYAML | on_complete / on_error / on_tool_permission |
| Hermes Agent | `hermes` | `~/.hermes/config.yaml` | hermesAgentYAML | on_session_start / pre_llm_call / post_llm_call / on_session_end / on_session_finalize / on_session_reset |
| Copilot | `copilot` | `~/.copilot/config.json` | nested(5000ms) | SessionStart / Stop / Notification / SessionEnd |
| CodeBuddy | `codebuddy` | `~/.codebuddy/settings.json` | nested(5000ms) | SessionStart / Stop / Notification / SessionEnd |
| Factory | `droid` | `~/.factory/settings.json` | nested(5000ms) | SessionStart / Stop / Notification / SessionEnd |
| Qoder | `qodercli` | `~/.qoder/settings.json` | nested(5000ms) | SessionStart / Stop / SessionEnd |

**3가지 포맷** (`buildHooksDict` at `CLI/cmux.swift:15896`):

**`.flat`** — 이벤트별 array 에 `{"command": "..."}` 단순 추가:

```json
{
  "stop": [{"command": "[ -n \"$CMUX_SURFACE_ID\" ] && [ \"$CMUX_CURSOR_HOOKS_DISABLED\" != \"1\" ] && command -v cmux >/dev/null 2>&1 && cmux hooks cursor stop || echo '{}'"}]
}
```

**`.nested(timeoutMs:)`** — Claude Code 와 동일한 nested hook 스키마 (Codex/Gemini/Copilot/CodeBuddy/Factory/Qoder):

```json
{
  "Stop": [{"hooks": [{"type":"command","command":"... cmux hooks codex stop ...","timeout":5000}]}]
}
```

**`.rovoDevYAML` / `.hermesAgentYAML`** — YAML 및 전용 포맷별 writer.

**공통 hook command 패턴** (`hookCommand` at `:15874`):

```bash
[ -n "$CMUX_SURFACE_ID" ] && [ "$<DISABLE_ENV>" != "1" ] && command -v cmux >/dev/null 2>&1 && cmux hooks <agent> <event> || echo '{}'
```

3-단계 가드: surface env 존재 + per-agent disable env + cmux CLI 존재. 실패 시 `{}` 출력 → 에이전트가 hook 실패로 인지 안 함.

**Feed bridge** (`feedHookCommand` at `:15882`): blocking permission/approval 이벤트는 별도 명령어 + 120s timeout (`cmux hooks feed --source <agent> --event <evt>`). Claude 의 `PermissionRequest`, Codex 의 `PreToolUse` 등.

**Codex 후처리** — `.postInstallAction = .codexConfigToml` (`:15736`) 이 `~/.codex/config.toml` 의 `notify = [...]` 도 별도 추가 (TOML 이라 hooks.json 과 분리되어야 함):

```toml
notify = ["bash", "-c", "command -v cmux &>/dev/null && cmux notify --title Codex --body \"$(echo $1 | jq -r '.\"last-assistant-message\" // \"Turn complete\"' 2>/dev/null | head -c 100)\" || osascript -e 'display notification \"Turn complete\" with title \"Codex\"'", "--"]
```

**Marker 기반 idempotent install/uninstall**: 각 def 의 `hookMarker` (예: `"cmux hooks codex"`) 로 자기가 쓴 entry 만 식별/제거 → 사용자가 같은 파일에 추가한 다른 hook 보존.

### (2) CLI → Unix socket → 앱 (디스패치)

훅이 `cmux notify --title ... --body ...` 호출 → CLI 가 자식 셸 env 에서 좌표 읽음:

| Env var | 용도 |
|---|---|
| `CMUX_SOCKET_PATH` | 컨트롤 소켓 경로 |
| `CMUX_TAB_ID` | 현재 워크스페이스 UUID |
| `CMUX_PANEL_ID` | 현재 surface UUID |

CLI 가 v2 RPC 로 `notification.create_for_caller` 호출 → Swift 앱의 `Sources/TerminalNotificationCallerResolver.swift:11` `v2NotificationCreateForCaller` 진입점이 받음:

```swift
let preferredWorkspaceId = v2UUID(params, "preferred_workspace_id")
let preferredSurfaceId = v2UUID(params, "preferred_surface_id")
let callerTTY = Self.normalizedTTYName(stringParam(params, "caller_tty"))
let preferTTY = boolParam(params, "prefer_tty") ?? false
```

라우팅 우선순위 (`callerNotificationTarget` at `:53-`): TTY 매칭 → preferredWorkspace+preferredSurface → preferredWorkspace alone → ttyTarget → preferredSurface 단독. 이후 `deliverNotificationSynchronously` 가 macOS UNUserNotificationCenter 에 발사 + pane blue ring + sidebar tab 점등.

### (3) OSC escape sequence (libghostty 직접 캐치)

README 에서 언급: "The notification system picks up terminal sequences (OSC 9/99/777)". 이건 에이전트가 직접 escape sequence 를 emit 하는 케이스 (iTerm-style `OSC 9`, urxvt-style `OSC 777`). cmux 는 fork 한 libghostty 의 OSC 콜백을 후킹해서 동일한 알림 스택으로 흘려보낸다. (Void/ghostty 본가도 동일 콜백 인터페이스 보유.)

## §2 이식 시 4-스택 요구사항 (Void 관점)

| 컴포넌트 | cmux 구현 | Void 에 필요한 것 |
|---|---|---|
| CLI | `cmux notify --title ... --tab ... --panel ...` (`CLI/cmux.swift:3209` 의 `notify_target` v1 cmd + v2 method) | `void notify` 신규 (현재 surface helper 만 존재) |
| 컨트롤 소켓 | `CMUX_SOCKET_PATH` Unix socket, v2 JSON-RPC | Void 에는 socket 인프라 부재 → 신규 필요 |
| 셸 환경 주입 | `TerminalStartupEnvironment.swift` 에서 `CMUX_TAB_ID` / `CMUX_PANEL_ID` / `CMUX_SOCKET_PATH` export | 현재 Void 는 surface UUID 셸에 노출 안 함 |
| 라우팅 resolver | `TerminalNotificationCallerResolver.swift` (TTY/UUID 매칭) | 동등 로직 신규 |
| Hook installer | `cmux hooks setup` 서브커맨드 + 11종 에이전트별 어댑터 | 우선 Claude Code wrapper 만이라도 |
| UI (pane indicator) | blue ring overlay + sidebar tab badge (`Sources/Sidebar/`) | Void grid 의 dim-overlay 인프라(`SurfaceView_AppKit.swift`) 위에 붙일 수 있음 |
| macOS 알림 | `TerminalNotificationStore.swift` UNUserNotificationCenter wrapper + off-main 제거 | 현재 Void 는 OSC desktop notification 1줄 (커밋 0123ec04c) — sound/badge 다듬기 필요 |

## §3 Void 의 현재 상태와 갭

Void 는 직전 커밋 `0123ec04c fix(surface): publish pwd on main, mirror desktop notifications to bell` 에서 OSC 데스크톱 알림을 bell 로 미러링하는 데 그쳤다. 즉:

- **있음**: ghostty 본가 surface message(OSC 9 등) → macOS notification 발사
- **없음**: `void notify` CLI / 소켓 / 셸 env 주입 / per-surface 라우팅 / agent hook installer / sidebar pane-level indicator

cmux 의 강점은 "에이전트가 OSC 안 쏴도 hook 으로 덮는다" 는 점이다. Claude Code 가 OSC 발사하는 모드는 별도 환경변수가 필요하고, 항상 켜져있지 않으므로 hook 경로가 더 신뢰성 있음.

## §4 권장 도입 순서

1. **CLI + 소켓** 인프라 부재가 가장 큰 블로커. `void notify` 만 우선 (+ `CMUX_*` 대응 `VOID_*` env triple).
2. Claude Code wrapper 가 가장 ROI 높음 (가장 많이 쓰는 에이전트 + cmux 가 wrapper 방식 검증).
3. UI: 기존 Grid dim-overlay 인프라를 재활용해 pane-level "attention ring" 구현.
4. (장기) Codex / OpenCode / Gemini 어댑터 — 각각 native hook 포맷이 달라 어댑터 1개당 ~50-200줄.

## §5 참고 파일 (cmux 클론 기준)

### Hook injection
- `Resources/bin/claude` — Claude Code wrapper (PATH-prepend, `--settings` inline JSON 주입). 라인 320 의 `HOOKS_JSON` 이 7개 라이프사이클 이벤트 정의.
- `CLI/cmux.swift:15724-15858` — 11종 에이전트의 `agentDefs` (configDir, configFile, format, events, feedHookEvents).
- `CLI/cmux.swift:15874` — `hookCommand()` 공통 shell pattern (3-단계 가드 + cmux CLI dispatch).
- `CLI/cmux.swift:15882` — `feedHookCommand()` blocking permission용 (120s timeout).
- `CLI/cmux.swift:15896` — `buildHooksDict()` flat / nested / yaml 포맷별 분기.
- `Resources/bin/cmux` (CLI binary) — `cmux hooks <agent> <event>` 디스패처. 각 hook 의 stdin payload 받아 v2 RPC 로 변환.

### Notification dispatch
- `Sources/TerminalNotificationCallerResolver.swift` — 라우팅 로직 (`v2NotificationCreateForCaller`, TTY/UUID 매칭).
- `Sources/TerminalNotificationStore.swift` — UNUserNotificationCenter wrapper, 사운드 처리.
- `Sources/TerminalNotificationQueue.swift` — 알림 큐.
- `CLI/cmux.swift:3209` — `notify_target` v1 cmd.
- `Sources/CmuxSocketEventMapper.swift` — 소켓 이벤트 매핑.

### Docs
- `docs/notifications.md` — CLI 사용법, 에이전트별 hook 설정 예시 (사용자 시각).
- `docs/agent-hooks.md` — `cmux hooks setup` 서브커맨드, env override.
