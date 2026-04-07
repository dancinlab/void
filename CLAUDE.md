> 🔴 **HEXA-FIRST**: 모든 코드는 `.hexa`로 작성. sh/py/rs 신규 작성 금지. 부하 유발 명령 최소화.

> 🔴 **하드코딩 절대 금지**: 상수/도메인/키워드를 코드에 배열로 나열 금지 → `nexus6/shared/*.jsonl`에서 동적 로드. 경로는 환경변수+상대경로. 새 항목 추가 = 설정 파일 한 줄, 코드 수정 0.

# void

## hexa-lang void 타입 구현 현황

### 현재 상태 (hexa-lang 기준)
| 레이어 | 파일 | 상태 | 비고 |
|--------|------|------|------|
| 타입 정의 | `src/types.rs` | ✅ | `PrimitiveType::Void` — 8 프리미티브 중 하나 |
| 타입 체커 | `src/type_checker.rs` | ✅ | `CheckType::Void` — 함수 리턴 없을 때 기본값 |
| 인터프리터 | `src/interpreter.rs` | ✅ | `Value::Void` 광범위 사용, Display="void" |
| 컴파일러 | `src/compiler.rs` | ✅ | `OpCode::Void` — 스택에 Void push |
| VM | `src/vm.rs` | ✅ | `OpCode::Void` 처리, 비교/출력 지원 |
| JIT | `src/jit.rs` | ⚠️ | void 미지원 — 모든 값이 i64, void=0 혼동 |
| 렉서 | `src/lexer.rs` | ⚠️ | `void` 키워드 미등록 (타입 어노테이션에서만 인식) |

### 핵심 버그
1. **`println(void_fn())` → `0` 출력** — JIT가 가로채서 i64(0) 반환, "void" 대신 "0" 출력
2. **`println(void)` → `undefined variable`** — void 리터럴이 Ident로 인식 안 됨
3. **JIT void sentinel 없음** — JIT는 i64만 다루므로 void 구분 불가

### 수정 필요 지점 (4곳)
```
src/interpreter.rs:1217  Expr::Ident("void") → Value::Void 반환 추가
src/compiler.rs:628      Expr::Ident("void") → OpCode::Void emit 추가
src/jit.rs:24            hexa_println_i64 — VOID_SENTINEL(i64::MIN) 감지 시 "void" 출력
src/jit.rs:598           빈 함수 반환값 iconst(0) → iconst(VOID_SENTINEL)
src/main.rs:609          JIT 결과 출력 시 VOID_SENTINEL 제외
```

### 실행 경로 (Tiered Execution)
```
hexa -e "code" → JIT(Tier1) → VM(Tier2) → Interpreter(Tier3)
- JIT 성공 시: main.rs:609에서 결과 출력 후 return
- VM 성공 시: main.rs:621에서 return
- 최종 폴백: Interpreter
- println은 JIT 내부에서 hexa_println_i64() 외부 함수로 호출
```

### 주의사항
- release 빌드 시 `codesign -s - ./hexa` 필요 (Apple Silicon)
- debug 빌드는 JIT(cranelift) 때문에 매우 느림 (~8초+)
- `attrs: vec![]` 누락 에러가 release/test에 있었음 (FnDecl, StructDecl에 attrs 필드 추가됨)
