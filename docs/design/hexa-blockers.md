# hexa-lang blockers (VOID 관점)

세션에서 발견된 hexa-lang 제약. 각 항목은 VOID 구현에 직접 영향을 준 순서.

## 1. `#{"k": v, "k2": v2}` 리터럴 파싱 실패

특정 조건(정확한 트리거 미확정)에서 multi-entry 맵 리터럴이 "expected Colon, got Comma"로 거절됨.
**우회**: `let m = #{}; m["k"] = v; m["k2"] = v2`. `theme.hexa` 전체가 이 패턴으로 재작성됨.

## 2. `cell["ch"]` 값에 `len()` 타입 미일치

`grid["cells"][r][c]["ch"]`는 print/concat 시 문자열로 보이지만 `len()`에 전달하면
"requires string/array/map/tensor" 타입 오류. 비교(`!=` `==`)는 동작.
**우회**: 길이 체크 대신 값 비교.

## 3. 최상위 `let` 상수가 `fn` 본문 스코프 밖

`pub let foo = 42` 를 파일 상단에 선언해도 같은 파일의 `fn` 안에서 `foo` 참조 불가.
**우회**: 값 인라인 또는 함수 매개변수로 주입. `ai/dashboard.hexa`에서 발견.

## 4. 없는 map 키 접근 = 런타임 에러

`m["missing"]`이 0/nil 반환이 아니라 `map key 'missing' not found` 런타임 에러.
`m["k"] != 0` 식의 존재 체크 불가.
**우회**: `has_key(m, "k")` 선행 호출. `plugin/plugin.hexa` 에서 발견.

## 5. `str_at` / `char_at` extern 실패 + string 메서드는 존재

`extern fn str_at(s: string, idx: int) -> string` 선언은 파싱되지만 호출 시 dlsym 실패.
대신 string 값에 메서드 `.contains(sub)`, `.starts_with(prefix)`, `.substring(start, end)` 동작.
**우회**: extern 제거, 메서드 사용. `ui/tab_bar.hexa` / `tab_input.hexa` / `tab_session.hexa`
에서 발견, 커밋 `dcbfc54`로 치환 완료.

## 6. 포인터 바이트 조작 빈틈 — `pty_resize` 완성 막힘

TIOCSWINSZ ioctl은 8바이트 `struct winsize`를 요구. hexa에는:
- `malloc(n)` → `*Void` 반환 ✓
- `memset(ptr, byte, n)` ✓
- `ptr_null/ptr_addr/deref` ✓ (deref는 읽기 전용)

하지만 **없음**:
- `ptr_offset(ptr, n)` — 포인터 산술
- `poke_byte/poke_u16` — 바이트 쓰기
- `chr(int) -> string` — 정수를 1바이트 문자열로

결과: 런타임 가변 값으로 임의 바이트 시퀀스를 구성할 수단이 없음.
**현 상태**: `pty_resize`는 `return 0` 스텁. 탭 스폰 시 PTY winsize 미설정 →
쉘이 초기 0x0 또는 openpty 기본값으로 실행됨. `main_tabs.hexa` 첫 실행 시
긴 줄 래핑이 잘못될 수 있음.
**영구 해결**: hexa-lang에 다음 중 하나 추가 필요
- (최소) `chr(int) -> string` + `cstring(s)`의 embedded NUL 지원
- (권장) `poke_u8(ptr, off, byte)`, `poke_u16_le(ptr, off, val)`
- (이상적) packed struct 리터럴

## 7. `*Void`가 `fn` 파라미터로 파싱 실패

`fn helper(buf: *Void, off: int)` 에서 `*` 토큰이 "expected identifier, got Star"로 거절.
extern 선언에는 허용. 6번 우회 시도 중 발견.
**우회**: 포인터 인자를 받는 내부 fn을 정의하지 않고 호출부에 인라인.

---

## 권고

VOID Phase 5 스모크(타입 검사/파싱)는 모두 통과하지만, TTY 런타임 완전 실행에는
6번(pty_resize 바이트 조작)이 유일한 실질 블로커. 우선순위 수정 제안:

1. `chr(int) -> string` — 1줄 수준, 가장 빠름
2. `ptr_offset(*Void, int) -> *Void` — 기존 ptr_addr 뒤에 간단 추가
3. `*Void` 파라미터 파싱 수용

이 3개가 풀리면 `pty_resize` 1시간 이내 완성 가능, 모든 L0 fix 포함한
`main_tabs.hexa` 실 TTY 배포 가능.
