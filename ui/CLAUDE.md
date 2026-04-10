# ui/ — L4 UI (L1 🟡 Protected)

탭, 레이아웃, 테마, 세션. 변경 시 커밋 사유 + 테스트 필수.

tab_model.hexa    탭 상태 구조체 (pid,cwd,history)
tab_bar.hexa      탭 바 렌더링
tab_input.hexa    키보드 바인딩 (Alt+n, Ctrl+t)
tab_mux.hexa      멀티탭 세션 관리
tab_session.hexa  세션 직렬화/복원
layout.hexa       Hive/Cell/Panel 레이아웃 엔진
theme.hexa        6 컬러 팔레트 (dark/light 변형)

흐름: tab_input(키) → tab_mux(라우팅) → tab_model(상태) → tab_bar(렌더)
의존: core/terminal(셀), core/render(출력). 참조: plugin/, ai/, app/
