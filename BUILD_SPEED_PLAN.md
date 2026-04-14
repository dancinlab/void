# VOID 빌드 속도 개선 로드맵

**목표:** edit→binary 반복 시간 45분 → **<30초** (전형적 편집 기준)
**블로커:** VB1 — hexa self-compile 2997 LOC 모놀리식 트랜스파일
**참조:** 기존 `$NEXUS/shared/roadmaps/void.json` 3-트랙(SYS/TERM/APP) 구조 계승

---

## 배경 — 왜 45분인가

void_main.hexa 2997 LOC + transitive `use` 임포트가 flatten되면 더 커짐. 체인:

```
hexa (네이티브 arm64) → 파싱/플래트닝/타입체킹 (CPU 병목, ~40분)
  → hexa_v2 → build/artifacts/void_term_new.c 생성
    → clang → sys_pty.c + sys_appkit.m + void_term_new.c 링크 (~5초)
```

- 전체 시간의 ~99%가 hexa 셀프호스팅 단계, ~1%가 clang
- sys_appkit.m(6207 LOC) + sys_pty.c(642 LOC)는 clang이 5초에 처리 — 병목 아님
- 즉 **C 쪽이 느린 게 아니라 hexa 쪽이 구조적으로 느림**

---

## Phase B1 — ObjC Fast Path (0.5일, 즉시)

| 작업 | 파일 | 효과 |
|------|------|------|
| `build_void.sh` mtime 게이트에 SKIP_TRANSPILE 명시 플래그 추가 | `scripts/build_void.sh` | ObjC-only 편집 5초 |
| 현재 .hexa 변경 없을 때 트랜스파일 스킵 로직 검증 + 테스트 | 같음 | 신뢰도↑ |
| "ObjC만 고치면 clang 재링크" CLAUDE.md에 명시 | `CLAUDE.md` | 개발자 혼선↓ |

**메트릭:** `touch src/sys_appkit.m && time ./scripts/build_void.sh` = **5~7초**
**리스크:** 미미 — mtime 로직 이미 존재

---

## Phase B2 — Hot-Data FFI 분리 (1~2일, **최고 ROI**)

| 작업 | 파일 | 효과 |
|------|------|------|
| `is_wide_cjk`, `wide_pages[]`, SMP 레인지를 C 테이블로 이전 | 신규 `src/widths.c` + `src/widths.h` | 폭 테이블 수정 5초 |
| hexa 쪽 `extern fn is_wide_cjk(cp: int) -> int` FFI 선언 | `src/void_main.hexa` | VP-08 류 버그 반복 고정비 제거 |
| FFI 호출 × 5M/프레임 오버헤드 벤치 | `tests/bench_width.c` | 핫패스 안전성 |
| 이모지 ZWJ / 피부톤 modifier 범위도 함께 C로 | `src/widths.c` | Claude CLI 아이콘 지원 확대 |

**메트릭:** VP-08 같은 너비 버그 수정 45분 → **5초**
**리스크:** FFI 오버헤드 — 벤치 결과 나쁘면 `static inline` 헤더만 분리해 우회

---

## Phase B3 — Transpile Hash Cache (2~3일)

| 작업 | 파일 | 효과 |
|------|------|------|
| flattened bundle SHA256 → `~/.cache/void/<hash>.c` 디렉토리 캐시 | `scripts/build_void.sh` | 공백·주석 편집 5초 |
| CI는 항상 `FORCE_TRANSPILE=1` 강제 | CI 설정 (향후) | 해시 오염 방지 |
| 캐시 hit 시 즉시 clang 단계로 점프 | 빌드 스크립트 | 실수 되돌리기 반복 시 효과 큼 |

**메트릭:** no-op 편집 → 45분 → **5초 (캐시 hit)**
**리스크:** 해시 무효화 버그 — `FORCE_TRANSPILE=1`로 우회 가능

---

## Phase B4 — 모듈 분할 (1주, hexa-lang 변경 필요)

| 작업 | 파일 | 효과 |
|------|------|------|
| void_main.hexa 2997줄 → 5~8 모듈 분할 | `src/vt_parser.hexa`, `input.hexa`, `render.hexa`, `session.hexa`, `main.hexa` | 모듈별 변경만 트랜스파일 |
| hexa-lang: separate compilation 지원 (모듈별 .c) | 업스트림 | 각 모듈 독립 .c 캐시 |
| `build_void.sh` 모듈 단위 mtime 체크 | 빌드 스크립트 | 실효 발현 |

**메트릭:** 한 서브시스템 편집 → 45분 → **5~10분**
**리스크:** cross-module global 충돌, 업스트림 작업 규모 큼

---

## Phase B5 — Hot-path C 이식 (2~3주, 기회주의)

| 작업 | 파일 | 효과 |
|------|------|------|
| VT 파서 상태머신 hexa → C 이식 | 신규 `src/vt_parser.c` | hexa LOC 감소 + 런타임 속도↑ |
| 스크린버퍼 update 로직 C 이전 | 신규 `src/screen.c` | hexa = 오케스트레이션만 |
| hexa 2997 LOC → ~1000 LOC 목표 | - | 트랜스파일 <10분 |

**메트릭:** 임의 hexa 편집 → **<10분**
**리스크:** FFI 표면적 넓어짐, 기존 `paste_util.c`가 선례

---

## Phase B6 — LLVM 백엔드 (장기, 업스트림)

hexa-lang이 `.c` 대신 LLVM IR 직접 emit → 셀프호스팅 병목 해소. 전체 빌드 **<1분**. hexa-lang 레포에서만 수행.

---

## 종합 표

| Phase | 목표 | edit→binary | 소요 | 종속성 |
|-------|------|-------------|------|--------|
| B1 | ObjC fast path | 5초 (ObjC) | 0.5일 | 없음 |
| **B2** | **Hot-data FFI** | **5초 (너비·이모지)** | **1~2일** | **없음 (최고 ROI)** |
| B3 | Hash cache | 5초 (no-op) | 2~3일 | 없음 |
| B4 | 모듈 분할 | 5~10분 (임의) | 1주 | hexa-lang |
| B5 | C 이식 | <10분 | 2~3주 | 없음 |
| B6 | LLVM backend | <1분 | ∞ | hexa-lang |

---

## 권장 실행 순서

1. **이번 주:** B1 + B2 — 2일로 VP-08 같은 이모지·너비 버그 수정 **45분→5초** 달성.
2. **다음 주:** B3 (해시 캐시) — no-op 편집 캐시 hit.
3. **그 이후:** B4/B5 우선순위는 실측 후 결정 — 2997 LOC 중 얼마가 실제 핫패스인지 프로파일링 필요.

---

## 메모

- **build_void.sh -o 경로 버그 (2026-04-15 해결 완료):** 이전에는 `-o /tmp/void_term.stage.stage1`로 인해 hexa가 `.c`를 `build/artifacts/void_term.stage.stage1.c`로 쓰고, 스크립트는 `void_term_new.c`를 읽어 매 빌드마다 전날 .c로 컴파일하던 silent 버그. `-o /tmp/void_term_new`로 고쳐 stem 일치. 이 경로 수정 없으면 아래 모든 Phase는 무의미.
- **메모리 경쟁:** `nexus_growth_daemon` + anima `readiness_bci` 컴파일이 10GB+ 점유해 hexa build가 jetsam kill로 silent 종료되는 환경 이슈. 빌드 중 `/tmp/void_build_watchdog.sh`로 5초마다 kill 유지.
- **DevLoop 현실:** 지금처럼 VP-08 같은 버그를 45분씩 기다리는 건 생산성 영살. B2 적용 후엔 이모지 범위 수정 → C 재컴파일 5초 → 즉시 테스트 가능.
