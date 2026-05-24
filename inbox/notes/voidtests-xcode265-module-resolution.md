# VoidTests 타깃 빌드 실패 — Xcode 26.5 · explicit modules

> ✅ **RESOLVED (#19, 2026-05-24)** — 원인은 explicit-modules가 아니라 리브랜딩 잔재였음:
> `@testable import Void`→`VoidApp`(모듈명) · `Void.X`→`VD.X`(네임스페이스) · `@main` 헤드리스
> 테스트를 auto-sync `Tests/` 밖으로 분리. mini 검증 7/7 + 10/10 passed.

| 항목 | 값 |
|---|---|
| 종류 | note (후속 이슈) |
| 발견 | 2026-05-24, mini (macOS · Xcode 26.5) |
| 범위 | clean `void/main`(@9e5f0d924)에서도 재현 — 코드 변경과 무관, 환경/프로젝트 설정 이슈 |
| 영향 | Swift Testing 스위트 전체(triage · reclaim 등) 이 환경에서 **실행 불가** → 회귀검증 공백 |

## 증상

```
xcodebuild test -project macos/Void.xcodeproj -scheme Void \
  -destination "platform=macOS" -only-testing:VoidTests/...

# explicit modules ON (기본):
macos/Tests/Helpers/TemporaryConfig.swift:2: error: unable to resolve module dependency: 'Void'
# explicit modules OFF (SWIFT_ENABLE_EXPLICIT_MODULES=NO):
macos/Tests/Helpers/TemporaryConfig.swift:2: error: no such module 'Void'
```

- 에러는 변경 파일이 아니라 기존 헬퍼 `TemporaryConfig.swift`(그리고 모든 `@testable import Void`)에서 발생.
- fresh derived data · `clean test`에서도 동일.

## 원인 가설

- 앱 타깃 모듈명이 `VoidApp` (`PRODUCT_MODULE_NAME = VoidApp`, 빌드 로그 `-module-name VoidApp`) 인데 테스트는 `@testable import Void` (17개 파일).
- Xcode 26.5 explicit-modules 해석에서 이 불일치 + TEST_HOST 모듈 매핑이 안 풀리는 것으로 추정.

## 후속 액션 (점검 순서)

1. `PRODUCT_MODULE_NAME` 정합 — 테스트 import를 `VoidApp`로 맞추거나, 앱 모듈명을 `Void`로 통일.
2. VoidTests 타깃 `TEST_HOST` / `BUNDLE_LOADER` 와 explicit-modules 상호작용 확인.
3. 조정 후 `xcodebuild test -only-testing:VoidTests/SessionManifestReclaimTests` 로 재확인 (이 PR에서 추가한 7케이스가 실제로 통과하는지).

## 참고

- 관련 fix: `#16`(topology-lost 알림 게이트), `#17`(closed surface ring 즉시 회수) — 둘 다 런타임으로 검증했고 unit test도 작성했으나, 위 이슈로 CI 실행은 불가.
