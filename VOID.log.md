# VOID — log

Append-only history sister of `VOID.md`. Each entry starts with `## <ISO timestamp> — <header>` (newest on top); body = `- [x]` (done) / `- [ ]` (pending) checkbox tasks.

## 2026-05-24 — VoidTests 타깃 빌드 복구 (#19)

- [x] 원인: 리브랜딩(Void→VoidApp 모듈명 · Void→VD 네임스페이스) 후 VoidTests 미컴파일 — `@testable import Void`/`Void.X` stale + `@main` 헤드리스 테스트가 auto-sync Tests/ 번들에 혼입
- [x] #19: import 17파일 → VoidApp · 네임스페이스 22곳 → VD · standalone 헤드리스 테스트를 Tests/ 밖으로 분리
- [x] mini 검증: SessionManifestReclaimTests 7/7 · SessionManifestTriageTests 10/10 passed · `** TEST SUCCEEDED **`

## 2026-05-24 — session-restore: topology-lost 오경보 + orphan ring 누수 해결

- [x] 진단: macOS 재시작 후 뜬 topologyLost 알림 = 크래시 아님. "macOS가 복원 미실행" 신호일 뿐 (mini에서 reboot 없이 결정적 재현)
- [x] #16 topology-lost 알림을 "복원 실제 실행" 플래그(`didRestoreAnyWindow`)로 게이트 — 정상 무복원 오경보 제거 (mini before/after 검증)
- [x] #17 닫힌 surface ring 즉시 회수 (`ringsToReclaim`) — orphan 누수 차단 · 세션한정 · quit/재시작 보존 (mini 런타임 안전검증: prior ring 3/3 생존)
- [x] #18 inbox: VoidTests 타깃 Xcode 26.5 빌드실패 후속 노트
- [ ] VoidTests 빌드 복구 → 작성한 unit test 7개 CI 실행 (후속 · inbox/notes 참조)

