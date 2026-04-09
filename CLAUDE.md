## ⛔ L0 CORE 보호 파일 (AI 수정 승인 필수)

> 아래 파일은 수렴 완료된 코어 로직. 수정 시 반드시 유저에게 승인 질문.
> 상세: `nexus/shared/core-lockdown.json`

```
🔴 L0 (불변식 — 코드 수정 전 유저 명시 승인 필수):
  src/sys/pty.hexa             — PTY 시스템
  src/sys/term.hexa            — 터미널 시스템
  src/sys/signal.hexa          — 시그널 핸들링
  src/render/ansi.hexa         — 렌더 ANSI 출력
  src/terminal/vt_parser.hexa  — VT 파서 핵심 프로토콜
  src/terminal/grid.hexa       — 그리드 셀 상태

🟡 L1 (보호 — 리뷰 필요):
  src/terminal/mouse.hexa      — 마우스 입력
  src/terminal/protocol.hexa   — 프로토콜 협상
  src/ui/                      — UI 레이어
  src/platform/                — 플랫폼 브릿지
```

> 🔴 **HEXA-FIRST**: 모든 코드는 `.hexa`로 작성. 부하 유발 명령 최소화.

# void

> 참조: `shared/absolute_rules.json` → VD1 | `shared/convergence/void.json` | `shared/todo/void.json`

## 6-layer 아키텍처 (VD1)
System → Render → Terminal → UI → Plugin → AI (n=6 레이어)

## 현황
```
Phase 1 — extern FFI          ✅
Phase 2 — PTY + Window        ✅ (TUI 기반)
Phase 3 — GPU + Font          ⬜
Phase 4 — Terminal Core       ⚠️ 부분완료 (VT파서+그리드 TUI)
Phase 5 — UI/Layout           ⬜
Phase 6 — Plugin + AI         ⬜

1,823 LOC | 13 hexa files
```

## 다음 벡터
- GPU 렌더링 (Metal) — Phase 3
- 폰트 렌더링 (CoreText) — Phase 3
- UI 레이아웃 (탭, 패널 분할) — Phase 5

## 할일 (todo)
- "todo", "할일" → `$HOME/Dev/hexa-lang/target/release/hexa $HOME/Dev/nexus/mk2_hexa/native/todo.hexa void` 실행 후 **결과를 마크다운 텍스트로 그대로 출력** (재포맷 금지). "todo 대량" 시 `... void 대량` 으로 실행.
