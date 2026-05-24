# VOID — current state

@goal: Grid-first terminal — Ghostty hard fork, N×M tiling as a core rendering surface (beta: grid mode only)

N×M 그리드 타일링이 핵심 렌더링 표면인 베타 터미널 (그리드 모드 전용). 세션 지속성은
mmap 퍼시스트 링 기반으로, 정상 재시작 시 오경보 없이 동작하고 닫힌 셀의 링은 즉시 회수된다.

## milestones

- [x] session-restore: 정상 재시작 topology-lost 오경보 제거 + closed-surface ring 누수 차단 (#16·#17·#18)
- [x] VoidTests 타깃 Xcode 26.5 빌드 복구 (작성한 unit test 7개 실행) (#19)
