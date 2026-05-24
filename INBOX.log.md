# INBOX — log

Append-only history sister of `INBOX.md`. Each entry starts with `## <ISO timestamp> — <header>` (newest on top); body = `- [x]` (done) / `- [ ]` (pending) checkbox tasks.

## 2026-05-24 — VoidTests 타깃 빌드 실패 (Xcode 26.5 · explicit modules)
- [x] ✅ resolved (#19, 2026-05-24) — `xcodebuild test` 가 `TemporaryConfig.swift` 의 `@testable import Void` 에서 모듈 의존성 해석 실패(explicit ON: `unable to resolve module dependency 'Void'` · OFF: `no such module 'Void'`). clean `void/main`(@9e5f0d924)에서도 재현 → 코드 무관, 프로젝트 설정 이슈로 Swift Testing 스위트 전체(triage · reclaim 등) 실행 불가 → 회귀검증 공백. 원인은 explicit-modules가 아니라 리브랜딩 잔재였음: 앱 모듈명은 `VoidApp`(`PRODUCT_MODULE_NAME`)인데 테스트 17개 파일이 `@testable import Void` 로 불일치. fix — `@testable import Void`→`VoidApp` · `Void.X`→`VD.X` 네임스페이스 정합 · `@main` 헤드리스 테스트를 auto-sync `Tests/` 밖으로 분리. mini(macOS · Xcode 26.5) 검증 7/7 + 10/10 passed. 관련 fix `#16`(topology-lost 알림 게이트) · `#17`(closed surface ring 즉시 회수)도 이 환경에서 unit test 실행 가능해짐. (from mini · 발견 2026-05-24)
