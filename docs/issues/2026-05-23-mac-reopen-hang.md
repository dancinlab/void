# mac "Reopen" 다이얼로그 클릭 후 Void 무한 행 (regression)

## 증상
- 사용자 mac에서 Void 비정상 종료(macOS 커널 패닉) 발생
- 재실행 시 macOS 시스템 다이얼로그 "Reopen" 표시
- "Reopen" 클릭 → void 프로세스가 무한 hang (UI 응답 없음)

## 재현 시도 결과 (mini.local — 재현 실패)
- `kill -9` + 즉시 relaunch → macOS reopen 다이얼로그 미표시 (SSH SIGKILL은 graceful로 간주됨, abnormal-termination 플래그 미설정)
- `~/Library/Saved Application State/com.dancinlab.void.savedState/` 디렉터리 mac·mini 양쪽 모두 부재 확인
- Phase B2 auto-replay 경로는 mini에서 정상 동작 (1282→2555 bytes replay + 그리드 렌더 검증 완료)
- 결론: mac hang은 mini가 트리거할 수 없는 별도 코드경로의 regression

## 의심 후보
| # | 후보 | 위치 | 근거 |
|---|------|------|------|
| 1 | macOS post-crash reopen 다이얼로그 abnormal-termination state | macOS SDK 26.5 launchd flag | mini는 SIGKILL을 graceful 처리, mac만 abnormal flag 세팅됨 |
| 2 | applicationWillFinishLaunching / DidFinishLaunching · SessionManifest triage 상호작용 | macOS app delegate + SessionManifest 경로 | kernel panic 후 launchd 플래그와의 conditional 분기 의심 |
| 3 | Phase B2 auto-replay가 restore-on-launch 분기에서 blocking I/O | 세션 복원 진입점 | mini의 cold-start 경로와 다른 reopen 진입점만 hang |

## 알려진 안전 데이터
| 항목 | 상태 |
|------|------|
| mac ring files (130개) | 모두 PTY bytes 보존 확인 (`tool/void-session-replay.sh`) |
| 사용자 세션 데이터 | 손실 없음 |
| in-app restore 경로 | 유일한 hang 지점 |

## 진단 차단 사유
- 사용자 명시 제약: "mini에서만 진행 (절대 우회금지)"
- mac-side `sample <pid>` 등 직접 채취 금지
- mac 재접근 권한 부여 전까지 mini-only 경로로만 진단 가능

## 다음 가능 액션
- `~/Library/Saved Application State/com.dancinlab.void.savedState/` 디렉터리 mini에서 인위적으로 합성 후 launch path 검증
- macOS panic-mimic 도구로 abnormal-termination 플래그 mini에서 강제 세팅 시도 (launchctl / NSApplication 플래그)
- `applicationWillFinishLaunching` ↔ SessionManifest 분기 정적 분석 (mini에서 코드만으로 hang 후보 좁히기)
- mac 재접근 허용 시 사용할 진단 스크립트 사전 준비 (sample + spindump 캡처 절차 문서화)
