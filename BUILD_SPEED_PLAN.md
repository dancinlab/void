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
- **2026-04-15 추가 발견:** "45분"도 상한 아님. 실제로는 hexa 런타임 `hexa_exec()` O(N²) 버그로 무한 hang 가까움 → B0 참조.

---

## Phase B0 — hexa runtime `hexa_exec()` O(N²) 수정 (**최우선**, 0.5일, hexa-lang 레포)

**위치:** `/Users/ghost/Dev/hexa-lang/self/runtime.c:2109-2124`

**버그:**
```c
HexaVal hexa_exec(HexaVal cmd) {
    ...
    char* result = malloc(4096); result[0] = '\0';
    while (fgets(buf, sizeof(buf), fp)) {
        size_t len = strlen(buf);
        if (total + len >= cap) { cap *= 2; result = realloc(result, cap); }
        strcat(result, buf);     // ← 매번 result 전체 재스캔 → O(N²)
        total += len;
    }
    return hexa_str_own(result);
}
```

**증상 (2026-04-15 sample 분석):**
- 부모 `hexa` 프로세스: 100% CPU, 스택 top = `_platform_strlen` → `strcat` → `hexa_exec` → `cmd_build`
- 자식 `hexa_v2` 프로세스: 0.1% CPU, RSS 5.5GB, 스택 top = `__write_nocancel` (stdout 파이프 포화 대기)
- 파이프 버퍼 64KB → parent가 O(N²) strcat 중이라 소비 속도 파멸적 → 자식 write 블록 → 5.5GB 예약 메모리 대기
- 29+분 경과 후 산출 `.c` 0 byte, 결국 watchdog/수동 kill

**본질적 수정 (3줄):**
```c
while (fgets(buf, sizeof(buf), fp)) {
    size_t len = strlen(buf);
    while (total + len + 1 > cap) { cap *= 2; result = realloc(result, cap); }
    memcpy(result + total, buf, len);
    total += len;
    result[total] = '\0';
}
```

| 변경 | 이유 |
|------|------|
| `strcat` → `memcpy(result+total, …)` | 매 호출 O(len), 전체 O(N) |
| `if` → `while` realloc | 한 줄이 잔여 cap 이상일 때 안전 (fgets 4096 + 이전 근접 여분) |
| 매 라인 `result[total]='\0'` | memcpy는 NUL 복사 안 하므로 명시 |

**파급:**
- `runtime.c`는 모든 hexa 프로그램에 `#include` → hexa-lang 자체 재빌드 필요 (native/*.c clang, 수 초)
- 모든 `exec()` 호출자 이익 (hexa build, lsp, 테스트 하네스 등)
- **B1~B6 측정 지표가 B0 없이는 전부 왜곡** — 먼저 착수해야 의미 있는 벤치 가능

**메트릭:** void 빌드 29+분 hang → hexa_v2 실제 산출 시간 (미측정, B0 적용 후 처음 드러남)
**리스크:** 매우 낮음 — strcat/memcpy 치환은 의미적 등가, null-term 명시로 회귀 없음

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

## ~~Phase B6 — LLVM 백엔드~~ (드롭 2026-04-15)

**드롭 사유:** clang 단계는 전체 빌드의 1%(≈5초)뿐. LLVM backend로 절약할 수 있는 이득이 그 5초 한정. codegen 전면 재작성은 월 단위 작업인데 ROI 최악. hexa-lang 레포에서 내부 개선(separate compilation / AST 캐시 / bc_vm / 증분 flatten)을 우선.

---

## 종합 표

| Phase | 목표 | edit→binary | 소요 | 종속성 | 상태 (2026-04-15) |
|-------|------|-------------|------|--------|--------------------|
| **B0** | **hexa_exec O(N²) fix** | **hang 해소 (전제)** | **0.5일** | **hexa-lang** | ✅ `hexa-lang 536462e` |
| B1 | ObjC fast path (SKIP_TRANSPILE) | 5초 (ObjC) | 0.5일 | 없음 | ✅ `void 90d2b04` |
| **B2** | **Hot-data FFI — widths.c 추출** | **5초 (너비·이모지)** | **1~2일** | **hexa-lang hexa_v2** | 🟡 코드 랜딩 · 검증 차단¹ |
| B3 | Hash cache | 5초 (no-op) | 2~3일 | 없음 | ✅ `void d511505` |
| B4 | 모듈 분할 | 5~10분 (임의) | 1주 | hexa-lang (A: separate compilation) | ⏳ 업스트림 대기 |
| B5 | C 이식 | <10분 | 2~3주 | 없음 | ⏳ 미착수 |
| ~~B6~~ | ~~LLVM backend~~ | ~~<1분~~ | ∞ | - | ❌ **드롭** (clang이 전체 1%, ROI 없음) |

¹ B2 wire-in 코드는 워킹트리에 랜딩: `extern fn hx_is_wide_cjk(cp: int) -> int` 선언 + inline 위드 블록 삭제 + `build_void.sh`에 `src/widths.c` 링크 추가 + `widths.{h,c}` long-ABI 정합. bench 통과 (18/18 self-check + 307M/s random / 833M/s clustered @ -O2). **검증 차단:** `hexa_v2` 2026-04-15 13:09 빌드(916KB)가 void bundle(170KB, 4569 LOC) transpile 중 재현성 있게 SIGKILL (2026-04-15 19:00~19:30 실측 3회: 97s / 95s / 177s — 모두 jetsam kill). pre-B2 원본 소스로도 재현되므로 wire-in과 무관. `hexa_v2_baseline` 453KB 바이너리는 void 신규 문법 parse 실패(line 4453). 업스트림 `hexa_v2` 메모리 regression 수정 대기.
  재시도 조건: hexa-lang 레포에서 hexa_v2 메모리 bloat 수정 + rebuild + void bundle 170KB transpile 1회 성공 확인 후 `./scripts/build_void.sh` 재실행.

---

## 권장 실행 순서

1. **즉시:** B0 — hexa-lang runtime.c 3줄 수정 + 재빌드. 이 전에는 다른 Phase 측정 불가.
2. **이번 주:** B1 + B2 — 2일로 VP-08 같은 이모지·너비 버그 수정 **45분→5초** 달성.
3. **다음 주:** B3 (해시 캐시) — no-op 편집 캐시 hit.
4. **그 이후:** B4/B5 우선순위는 실측 후 결정 — 2997 LOC 중 얼마가 실제 핫패스인지 프로파일링 필요.

---

## 메모

- **build_void.sh -o 경로 버그 (2026-04-15 해결 완료):** 이전에는 `-o /tmp/void_term.stage.stage1`로 인해 hexa가 `.c`를 `build/artifacts/void_term.stage.stage1.c`로 쓰고, 스크립트는 `void_term_new.c`를 읽어 매 빌드마다 전날 .c로 컴파일하던 silent 버그. `-o /tmp/void_term_new`로 고쳐 stem 일치. 이 경로 수정 없으면 아래 모든 Phase는 무의미.
- **메모리 경쟁:** `nexus_growth_daemon` + anima `readiness_bci` 컴파일이 10GB+ 점유해 hexa build가 jetsam kill로 silent 종료되는 환경 이슈. 빌드 중 `/tmp/void_build_watchdog.sh`로 5초마다 kill 유지.
- **DevLoop 현실:** 지금처럼 VP-08 같은 버그를 45분씩 기다리는 건 생산성 영살. B2 적용 후엔 이모지 범위 수정 → C 재컴파일 5초 → 즉시 테스트 가능.
