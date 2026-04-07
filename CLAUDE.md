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
- "todo", "할일" → `hexa-bin-actual $HOME/Dev/nexus/mk2_hexa/native/todo.hexa void` 실행 후 **결과를 마크다운 텍스트로 직접 출력** (렌더링되는 표로)
