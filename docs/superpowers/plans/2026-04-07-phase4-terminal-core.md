# Phase 4: Terminal Core 완성 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** VOID 터미널 에뮬레이터의 Terminal Core(Phase 4)를 완성하여, vim/htop 등 실제 TUI 앱을 무리 없이 구동할 수 있는 수준으로 만든다.

**Architecture:** VT 파서에 TrueColor·마우스·DEC 문자셋을 추가하고, 그리드에 alt screen·RGB 컬러·리사이즈를 구현하며, 메인 루프에 마우스 입력·스크롤백 탐색·리사이즈 폴링을 통합한다. 차등 렌더링으로 성능을 개선한다.

**Tech Stack:** hexa-lang (인터프리터), POSIX extern FFI (ioctl, read, write, signal)

**Color encoding convention:** 색상값 0–255는 기존 팔레트. 256 이상은 RGB 인코딩: `256 + R*65536 + G*256 + B`. 렌더러에서 `38;2;R;G;B` 시퀀스로 출력.

---

### Task 1: TrueColor (24-bit RGB) 지원

**Files:**
- Modify: `core/terminal/vt_parser.hexa:61-137` (apply_sgr)
- Modify: `core/render/ansi.hexa:36-62` (ansi_fg, ansi_bg)

**RGB encoding:** `color = 256 + R*65536 + G*256 + B` (fits in i64)

- [ ] **Step 1: Parser — SGR 38;2;R;G;B (TrueColor FG)**

In `core/terminal/vt_parser.hexa`, inside `apply_sgr()`, modify the `p == 38` branch (line ~106):

```hexa
    } else if p == 38 {
      // Extended FG
      if i + 2 < len(params) && params[i + 1] == 5 {
        // 256-color: 38;5;N
        grid["current_fg"] = params[i + 2]
        i = i + 2
      } else if i + 4 < len(params) && params[i + 1] == 2 {
        // TrueColor: 38;2;R;G;B
        let r = params[i + 2]
        let g = params[i + 3]
        let b = params[i + 4]
        grid["current_fg"] = 256 + r * 65536 + g * 256 + b
        i = i + 4
      }
```

- [ ] **Step 2: Parser — SGR 48;2;R;G;B (TrueColor BG)**

Same file, modify the `p == 48` branch (line ~118):

```hexa
    } else if p == 48 {
      // Extended BG
      if i + 2 < len(params) && params[i + 1] == 5 {
        // 256-color: 48;5;N
        grid["current_bg"] = params[i + 2]
        i = i + 2
      } else if i + 4 < len(params) && params[i + 1] == 2 {
        // TrueColor: 48;2;R;G;B
        let r = params[i + 2]
        let g = params[i + 3]
        let b = params[i + 4]
        grid["current_bg"] = 256 + r * 65536 + g * 256 + b
        i = i + 4
      }
```

- [ ] **Step 3: Renderer — TrueColor FG output**

In `core/render/ansi.hexa`, modify `ansi_fg()` (line ~36):

```hexa
pub fn ansi_fg(color_index: int) -> string {
  if color_index < 0 {
    return ""
  }
  if color_index >= 256 {
    // TrueColor: decode RGB from 256 + R*65536 + G*256 + B
    let rgb = color_index - 256
    let r = rgb / 65536
    let remainder = rgb - r * 65536
    let g = remainder / 256
    let b = remainder - g * 256
    return "\x1b[38;2;" + str(r) + ";" + str(g) + ";" + str(b) + "m"
  }
  if color_index < 8 {
    return "\x1b[" + str(30 + color_index) + "m"
  }
  if color_index < 16 {
    return "\x1b[" + str(90 + color_index - 8) + "m"
  }
  return "\x1b[38;5;" + str(color_index) + "m"
}
```

- [ ] **Step 4: Renderer — TrueColor BG output**

Same file, modify `ansi_bg()` (line ~51):

```hexa
pub fn ansi_bg(color_index: int) -> string {
  if color_index < 0 {
    return ""
  }
  if color_index >= 256 {
    let rgb = color_index - 256
    let r = rgb / 65536
    let remainder = rgb - r * 65536
    let g = remainder / 256
    let b = remainder - g * 256
    return "\x1b[48;2;" + str(r) + ";" + str(g) + ";" + str(b) + "m"
  }
  if color_index < 8 {
    return "\x1b[" + str(40 + color_index) + "m"
  }
  if color_index < 16 {
    return "\x1b[" + str(100 + color_index - 8) + "m"
  }
  return "\x1b[48;5;" + str(color_index) + "m"
}
```

- [ ] **Step 5: 검증 — TrueColor 출력 확인**

Run: `hexa run app/main.hexa` 후 셸에서:
```bash
printf '\e[38;2;255;100;0mTrueColor FG\e[0m\n'
printf '\e[48;2;0;100;255mTrueColor BG\e[0m\n'
```
Expected: 주황색 전경, 파란색 배경으로 텍스트 표시

- [ ] **Step 6: Commit**

```bash
git add core/terminal/vt_parser.hexa core/render/ansi.hexa
git commit -m "feat: TrueColor (24-bit RGB) 지원 — SGR 38;2 / 48;2 파싱+렌더링"
```

---

### Task 2: 윈도우 리사이즈 처리

**Files:**
- Modify: `core/sys/term.hexa` (ioctl 기반 사이즈 감지 추가)
- Modify: `core/terminal/grid.hexa` (그리드 리사이즈 함수)
- Modify: `app/main.hexa` (리사이즈 폴링 루프)

- [ ] **Step 1: term.hexa — ioctl 기반 터미널 사이즈 (빠른 버전)**

`core/sys/term.hexa`에 ioctl 기반 사이즈 함수 추가 (기존 term_size는 유지, 새 함수 추가):

```hexa
// TIOCGWINSZ on macOS = 0x40087468
pub let tiocgwinsz = 1074295912

extern fn ioctl(fd: int, request: int, argp: *Void) -> int

pub fn term_size_fast() -> map {
  // ioctl TIOCGWINSZ returns struct winsize {u16 row, u16 col, u16 xpixel, u16 ypixel}
  let buf = malloc(8)
  let ret = ioctl(fd_stdin, tiocgwinsz, buf)
  if ret != 0 {
    free(buf)
    return term_size()
  }
  // deref reads i64 (8 bytes). Little-endian: low 16 bits = rows, next 16 = cols
  let packed = deref(buf)
  free(buf)
  // Extract unsigned shorts via arithmetic (no bitwise in hexa)
  let rows = packed - (packed / 65536) * 65536
  let cols = (packed / 65536) - (packed / 65536 / 65536) * 65536
  if rows <= 0 { rows = 24 }
  if cols <= 0 { cols = 80 }
  return #{"rows": rows, "cols": cols}
}
```

- [ ] **Step 2: grid.hexa — 그리드 리사이즈 함수**

`core/terminal/grid.hexa` 끝에 추가:

```hexa
pub fn grid_resize(grid: map, new_rows: int, new_cols: int) -> map {
  let old_rows = grid["rows"]
  let old_cols = grid["cols"]
  let old_cells = grid["cells"]

  // Build new cell array
  let cells = []
  let r = 0
  while r < new_rows {
    let row = []
    let c = 0
    while c < new_cols {
      if r < old_rows && c < old_cols {
        row = row + [old_cells[r][c]]
      } else {
        row = row + [new_cell()]
      }
      c = c + 1
    }
    cells = cells + [row]
    r = r + 1
  }

  grid["cells"] = cells
  grid["rows"] = new_rows
  grid["cols"] = new_cols
  grid["scroll_top"] = 0
  grid["scroll_bottom"] = new_rows - 1

  // Clamp cursor
  if grid["cursor_row"] >= new_rows {
    grid["cursor_row"] = new_rows - 1
  }
  if grid["cursor_col"] >= new_cols {
    grid["cursor_col"] = new_cols - 1
  }

  return grid
}
```

- [ ] **Step 3: main.hexa — 리사이즈 폴링**

`app/main.hexa`에서 메인 루프 수정. `let frame_count = 0` 아래에 추가:

```hexa
let resize_counter = 0
```

메인 루프 안, `usleep(10000)` 직전에 리사이즈 체크 삽입:

```hexa
  // 5. Check for resize every 50 frames (~500ms)
  resize_counter = resize_counter + 1
  if resize_counter >= 50 {
    resize_counter = 0
    let new_size = term_size_fast()
    if new_size["rows"] != term_rows || new_size["cols"] != term_cols {
      term_rows = new_size["rows"]
      term_cols = new_size["cols"]
      grid_rows = term_rows - 1
      grid_cols = term_cols
      grid = grid_resize(grid, grid_rows, grid_cols)
      dirty = true
      frame_count = 2
    }
  }
```

- [ ] **Step 4: 검증 — 리사이즈 동작**

Run: `hexa run app/main.hexa` 후 터미널 창 크기를 마우스로 조절
Expected: 그리드가 새 크기에 맞춰 재렌더링, 기존 내용 유지, statusbar에 새 크기 표시

- [ ] **Step 5: Commit**

```bash
git add core/sys/term.hexa core/terminal/grid.hexa app/main.hexa
git commit -m "feat: 윈도우 리사이즈 처리 — ioctl 폴링 + 그리드 리사이즈"
```

---

### Task 3: Alt Screen Buffer 구현

**Files:**
- Modify: `core/terminal/grid.hexa` (alt grid 저장/복원)
- Modify: `core/terminal/vt_parser.hexa:221-241` (CSI ?1049h/l 디스패치)

- [ ] **Step 1: grid.hexa — alt screen 저장/복원 함수**

`core/terminal/grid.hexa` 끝에 추가:

```hexa
pub fn grid_save_for_alt(grid: map) -> map {
  // Deep copy current cells for alt screen restore
  let saved_cells = []
  let r = 0
  while r < grid["rows"] {
    let row = []
    let c = 0
    while c < grid["cols"] {
      let cell = grid["cells"][r][c]
      row = row + [#{"ch": cell["ch"], "fg": cell["fg"], "bg": cell["bg"], "flags": cell["flags"]}]
      c = c + 1
    }
    saved_cells = saved_cells + [row]
    r = r + 1
  }
  return #{
    "cells": saved_cells,
    "rows": grid["rows"],
    "cols": grid["cols"],
    "cursor_row": grid["cursor_row"],
    "cursor_col": grid["cursor_col"],
    "current_fg": grid["current_fg"],
    "current_bg": grid["current_bg"],
    "current_flags": grid["current_flags"],
    "scrollback": grid["scrollback"]
  }
}

pub fn grid_restore_from_alt(grid: map, saved: map) -> map {
  // Restore saved main screen
  if saved == null {
    return grid
  }
  let r = 0
  while r < grid["rows"] && r < saved["rows"] {
    let c = 0
    while c < grid["cols"] && c < saved["cols"] {
      grid["cells"][r][c] = saved["cells"][r][c]
      c = c + 1
    }
    r = r + 1
  }
  grid["cursor_row"] = saved["cursor_row"]
  grid["cursor_col"] = saved["cursor_col"]
  grid["current_fg"] = saved["current_fg"]
  grid["current_bg"] = saved["current_bg"]
  grid["current_flags"] = saved["current_flags"]
  grid["scrollback"] = saved["scrollback"]
  grid["alt_screen"] = false
  return grid
}
```

- [ ] **Step 2: vt_parser.hexa — ?1049h/l에서 alt screen 전환**

`dispatch_csi()`에서 `n == 1049` 분기를 수정 (line ~228-239):

```hexa
      if n == 25 {
        grid["cursor_visible"] = true
      } else if n == 1049 {
        // Enter alt screen — save main grid
        grid["saved_main"] = grid_save_for_alt(grid)
        grid["alt_screen"] = true
        grid = grid_erase_all(grid)
        grid = grid_cursor_set(grid, 0, 0)
      }
```

그리고 reset mode (l) 분기:

```hexa
      if n == 25 {
        grid["cursor_visible"] = false
      } else if n == 1049 {
        // Leave alt screen — restore main grid
        if grid["saved_main"] != null {
          grid = grid_restore_from_alt(grid, grid["saved_main"])
          grid["saved_main"] = null
        }
        grid["alt_screen"] = false
      }
```

- [ ] **Step 3: grid 초기화에 saved_main 필드 추가**

`new_grid()` 함수 (line ~18)의 반환 map에 추가:

```hexa
    "saved_main": null
```

(기존 `"current_flags": 0` 다음 줄)

- [ ] **Step 4: 검증 — vim 실행/종료**

Run: `hexa run app/main.hexa` 후:
```bash
echo "before vim"
vim     # 열었다가 :q 로 종료
```
Expected: vim 종료 후 "before vim" 텍스트가 화면에 복원됨

- [ ] **Step 5: Commit**

```bash
git add core/terminal/grid.hexa core/terminal/vt_parser.hexa
git commit -m "feat: alt screen buffer 구현 — ?1049h/l 저장/복원"
```

---

### Task 4: 마우스 지원 (xterm 프로토콜)

**Files:**
- Modify: `core/terminal/vt_parser.hexa` (마우스 모드 CSI 추가)
- Modify: `app/main.hexa` (마우스 입력 파싱 + PTY 전달)

- [ ] **Step 1: vt_parser.hexa — 마우스 모드 플래그**

`new_vt_parser()` (line ~13)에 마우스 모드 필드 추가:

```hexa
pub fn new_vt_parser() -> map {
  return #{
    "state": st_ground,
    "params": "",
    "intermediate": "",
    "osc_string": "",
    "private_mode": false,
    "mouse_mode": 0,
    "mouse_sgr": false
  }
}
```

- [ ] **Step 2: vt_parser.hexa — CSI 마우스 모드 토글**

`dispatch_csi()`에서 set mode (h) 분기에 마우스 모드 추가. 현재 grid만 수정하지만 parser도 필요하므로 반환값을 확장해야 한다.

**중요:** `dispatch_csi`는 `#{"grid": grid, "title": title}`을 반환한다. parser 수정이 필요하므로 반환값에 parser를 추가한다.

`dispatch_csi` 시그니처와 반환값 수정:

```hexa
pub fn dispatch_csi(parser: map, grid: map, params_str: string, final_ch: string) -> map {
```

반환값을 `#{"grid": grid, "title": title, "parser": parser}`로 변경.

set mode (h) 분기에 추가:

```hexa
      if n == 25 {
        grid["cursor_visible"] = true
      } else if n == 1049 {
        grid["saved_main"] = grid_save_for_alt(grid)
        grid["alt_screen"] = true
        grid = grid_erase_all(grid)
        grid = grid_cursor_set(grid, 0, 0)
      } else if n == 1000 {
        parser["mouse_mode"] = 1000
      } else if n == 1002 {
        parser["mouse_mode"] = 1002
      } else if n == 1003 {
        parser["mouse_mode"] = 1003
      } else if n == 1006 {
        parser["mouse_sgr"] = true
      }
```

reset mode (l) 분기:

```hexa
      if n == 25 {
        grid["cursor_visible"] = false
      } else if n == 1049 {
        if grid["saved_main"] != null {
          grid = grid_restore_from_alt(grid, grid["saved_main"])
          grid["saved_main"] = null
        }
        grid["alt_screen"] = false
      } else if n == 1000 || n == 1002 || n == 1003 {
        parser["mouse_mode"] = 0
      } else if n == 1006 {
        parser["mouse_sgr"] = false
      }
```

- [ ] **Step 3: vt_process에서 parser 반환값 반영**

`vt_process()`에서 `dispatch_csi` 호출부 (line ~342) 수정:

```hexa
        let result = dispatch_csi(parser, grid, parser["params"], ch)
        grid = result["grid"]
        if result["parser"] != null {
          parser = result["parser"]
        }
        if len(result["title"]) > 0 {
          title = result["title"]
        }
```

`dispatch_csi` 끝 반환문 수정:

```hexa
  return #{"grid": grid, "title": title, "parser": parser}
```

- [ ] **Step 4: main.hexa — 마우스 입력 파싱**

`app/main.hexa`에 마우스 입력 인코딩 함수 추가 (메인 루프 전):

```hexa
fn encode_mouse_sgr(button: int, col: int, row: int, pressed: bool) -> string {
  let suffix = "M"
  if pressed == false {
    suffix = "m"
  }
  return "\x1b[<" + str(button) + ";" + str(col) + ";" + str(row) + suffix
}
```

stdin 읽기 부분에서 마우스 입력 감지 추가. 현재 `if stdin_n > 0` 블록 수정:

```hexa
  if stdin_n > 0 {
    // Forward all input to PTY (mouse events from host terminal are already encoded)
    write(master_fd, stdin_buf, stdin_n)
  }
```

호스트 터미널이 마우스 이벤트를 보내려면 VOID가 호스트에 마우스 모드를 켜야 한다. 메인 루프 안에서 마우스 모드가 변경되면 호스트에도 전달:

메인 루프 전에 추가:
```hexa
let current_mouse_mode = 0
let current_mouse_sgr = false
```

메인 루프 안, dirty 체크 블록 뒤에:
```hexa
  // 6. Sync mouse mode to host terminal
  if parser["mouse_mode"] != current_mouse_mode {
    if current_mouse_mode > 0 {
      // Disable old mode on host
      flush_to_stdout("\x1b[?" + str(current_mouse_mode) + "l")
    }
    current_mouse_mode = parser["mouse_mode"]
    if current_mouse_mode > 0 {
      // Enable new mode on host
      flush_to_stdout("\x1b[?" + str(current_mouse_mode) + "h")
    }
  }
  if parser["mouse_sgr"] != current_mouse_sgr {
    current_mouse_sgr = parser["mouse_sgr"]
    if current_mouse_sgr {
      flush_to_stdout("\x1b[?1006h")
    } else {
      flush_to_stdout("\x1b[?1006l")
    }
  }
```

- [ ] **Step 5: main.hexa — cleanup에서 마우스 모드 해제**

cleanup 섹션 (`pty_close` 전)에 추가:

```hexa
// Disable mouse modes on host
if current_mouse_mode > 0 {
  flush_to_stdout("\x1b[?" + str(current_mouse_mode) + "l")
}
if current_mouse_sgr {
  flush_to_stdout("\x1b[?1006l")
}
```

- [ ] **Step 6: 검증 — htop/vim 마우스**

Run: `hexa run app/main.hexa` 후:
```bash
# htop이나 vim에서 마우스 클릭이 동작하는지 확인
vim    # 마우스로 커서 이동 시도
```
Expected: 호스트 터미널이 마우스 이벤트를 캡처하여 PTY로 전달

- [ ] **Step 7: Commit**

```bash
git add core/terminal/vt_parser.hexa app/main.hexa
git commit -m "feat: xterm 마우스 프로토콜 지원 — mode 1000/1002/1003 + SGR 1006"
```

---

### Task 5: 스크롤백 탐색

**Files:**
- Modify: `app/main.hexa` (키 입력 가로채기 + 스크롤 오프셋)
- Modify: `core/render/ansi.hexa` (스크롤 오프셋 반영 렌더링)

- [ ] **Step 1: main.hexa — 스크롤 오프셋 상태 추가**

메인 루프 전 변수 추가:

```hexa
let scroll_offset = 0
```

- [ ] **Step 2: main.hexa — Shift+PageUp/Down 감지**

stdin 읽기 부분을 수정하여 특수 키를 가로챈다. xterm에서 Shift+PageUp = `ESC[5;2~`, Shift+PageDown = `ESC[6;2~`.

stdin 읽기 부분 수정:

```hexa
  if stdin_n > 0 {
    let input = from_cstring_n(stdin_buf, stdin_n)
    let handled = false

    // Shift+PageUp: ESC[5;2~
    if stdin_n >= 6 && input == "\x1b[5;2~" {
      let max_scroll = len(grid["scrollback"])
      scroll_offset = scroll_offset + grid_rows
      if scroll_offset > max_scroll {
        scroll_offset = max_scroll
      }
      dirty = true
      frame_count = 2
      handled = true
    }
    // Shift+PageDown: ESC[6;2~
    if stdin_n >= 6 && input == "\x1b[6;2~" {
      scroll_offset = scroll_offset - grid_rows
      if scroll_offset < 0 {
        scroll_offset = 0
      }
      dirty = true
      frame_count = 2
      handled = true
    }

    if handled == false {
      // Reset scroll on user input
      if scroll_offset > 0 {
        scroll_offset = 0
        dirty = true
        frame_count = 2
      }
      write(master_fd, stdin_buf, stdin_n)
    }
  }
```

- [ ] **Step 3: ansi.hexa — 스크롤 오프셋 반영 렌더링**

`core/render/ansi.hexa`에 스크롤 오프셋 렌더 함수 추가:

```hexa
pub fn render_grid_with_scroll(grid: map, scroll_offset: int) -> string {
  if scroll_offset == 0 {
    return render_grid_full(grid)
  }

  let rows = grid["rows"]
  let cols = grid["cols"]
  let cells = grid["cells"]
  let scrollback = grid["scrollback"]
  let sb_len = len(scrollback)

  let out = ansi_cursor_hide() + ansi_move(1, 1)
  let prev_fg = -1
  let prev_bg = -1
  let prev_flags = -1

  let r = 0
  while r < rows {
    out = out + ansi_move(r + 1, 1)
    // Which line to display: scrollback or live grid?
    let sb_index = sb_len - scroll_offset + r
    let c = 0
    while c < cols {
      let cell = new_cell()
      if sb_index < 0 {
        // Before scrollback — blank
        cell = new_cell()
      } else if sb_index < sb_len {
        // From scrollback
        if c < len(scrollback[sb_index]) {
          cell = scrollback[sb_index][c]
        }
      } else {
        // From live grid
        let grid_row = sb_index - sb_len
        if grid_row < rows {
          cell = cells[grid_row][c]
        }
      }

      let fg = cell["fg"]
      let bg = cell["bg"]
      let flags = cell["flags"]
      if fg != prev_fg || bg != prev_bg || flags != prev_flags {
        out = out + cell_attrs(fg, bg, flags)
        prev_fg = fg
        prev_bg = bg
        prev_flags = flags
      }
      out = out + cell["ch"]
      c = c + 1
    }
    r = r + 1
  }

  out = out + ansi_reset()
  out = out + ansi_move(rows, 1)
  out = out + ansi_cursor_show()
  return out
}
```

- [ ] **Step 4: main.hexa — 렌더링에 스크롤 오프셋 적용**

메인 루프의 렌더링 부분 수정:

```hexa
      let rendered = render_grid_with_scroll(grid, scroll_offset)
      let scroll_indicator = ""
      if scroll_offset > 0 {
        scroll_indicator = " [scroll:" + str(scroll_offset) + "]"
      }
      let status_text = " VOID | " + window_title + " | " + str(grid_cols) + "x" + str(grid_rows) + scroll_indicator
```

- [ ] **Step 5: main.hexa — PTY 출력 시 스크롤 리셋**

PTY 읽기 부분 (`if pty_n > 0`)에 추가:

```hexa
    if scroll_offset > 0 {
      scroll_offset = 0
    }
```

- [ ] **Step 6: 검증 — 스크롤백 동작**

Run: `hexa run app/main.hexa` 후:
```bash
seq 1 200    # 많은 라인 출력
# Shift+PageUp으로 위로 스크롤
# Shift+PageDown으로 아래로 스크롤
# 아무 키 입력 시 스크롤 리셋
```
Expected: 스크롤백 버퍼의 이전 출력을 탐색할 수 있음

- [ ] **Step 7: Commit**

```bash
git add app/main.hexa core/render/ansi.hexa
git commit -m "feat: 스크롤백 탐색 — Shift+PageUp/Down으로 히스토리 탐색"
```

---

### Task 6: 차등 렌더링 활성화

**Files:**
- Modify: `app/main.hexa` (prev_grid 추적 + render_grid 사용)

- [ ] **Step 1: main.hexa — prev_grid 상태 추가**

메인 루프 전에 추가:

```hexa
let prev_grid = null
```

- [ ] **Step 2: 렌더링 로직을 차등 렌더로 전환**

메인 루프의 렌더링 부분 수정:

```hexa
    if frame_count >= 2 {
      let rendered = ""
      if scroll_offset > 0 {
        rendered = render_grid_with_scroll(grid, scroll_offset)
        prev_grid = null
      } else {
        rendered = render_grid(grid, prev_grid)
        // Save current grid state for next diff
        prev_grid = grid_save_for_alt(grid)
      }
      let scroll_indicator = ""
      if scroll_offset > 0 {
        scroll_indicator = " [scroll:" + str(scroll_offset) + "]"
      }
      let status_text = " VOID | " + window_title + " | " + str(grid_cols) + "x" + str(grid_rows) + scroll_indicator
      let statusbar = ansi_move(term_rows, 1) + render_statusbar(status_text, grid_cols)
      flush_to_stdout(rendered + statusbar)
      dirty = false
      frame_count = 0
    }
```

- [ ] **Step 3: 리사이즈 시 prev_grid 리셋**

리사이즈 체크 블록에 추가:

```hexa
      prev_grid = null
```

- [ ] **Step 4: 검증 — 성능 개선 확인**

Run: `hexa run app/main.hexa` 후:
```bash
ls -la /     # 일반 출력 — 차등 렌더 동작
vim           # 전체 화면 앱 — 정상 표시 확인
```
Expected: 시각적 차이 없이 동작, 체감 렌더링 속도 개선

- [ ] **Step 5: Commit**

```bash
git add app/main.hexa
git commit -m "feat: 차등 렌더링 활성화 — 변경된 셀만 갱신"
```

---

### Task 7: 누락 SGR + DEC Line Drawing

**Files:**
- Modify: `core/terminal/grid.hexa` (새 플래그 상수)
- Modify: `core/terminal/vt_parser.hexa` (SGR 확장 + charset 전환)
- Modify: `core/render/ansi.hexa` (새 속성 출력)

- [ ] **Step 1: grid.hexa — 새 속성 플래그 추가**

기존 플래그 상수 뒤에 (line ~12):

```hexa
pub let cell_strikethrough = 32
pub let cell_blink = 64
```

- [ ] **Step 2: vt_parser.hexa — SGR 확장**

`apply_sgr()`에 새 SGR 코드 추가. `p == 7` 분기 뒤에:

```hexa
    } else if p == 5 {
      // Blink
      let has_blink = (grid["current_flags"] / 64) - (grid["current_flags"] / 128) * 1
      if has_blink == 0 {
        grid["current_flags"] = grid["current_flags"] + 64
      }
    } else if p == 9 {
      // Strikethrough
      let has_strike = (grid["current_flags"] / 32) - (grid["current_flags"] / 64) * 1
      if has_strike == 0 {
        grid["current_flags"] = grid["current_flags"] + 32
      }
    } else if p == 22 {
      // Reset bold and dim
      let f = grid["current_flags"]
      let has_bold = f - (f / 2) * 2
      let has_dim = (f / 16) - (f / 32) * 1
      if has_bold > 0 { grid["current_flags"] = grid["current_flags"] - 1 }
      if has_dim > 0 { grid["current_flags"] = grid["current_flags"] - 16 }
    } else if p == 23 {
      // Reset italic
      let has_italic = (grid["current_flags"] / 2) - (grid["current_flags"] / 4) * 1
      if has_italic > 0 { grid["current_flags"] = grid["current_flags"] - 2 }
    } else if p == 24 {
      // Reset underline
      let has_underline = (grid["current_flags"] / 4) - (grid["current_flags"] / 8) * 1
      if has_underline > 0 { grid["current_flags"] = grid["current_flags"] - 4 }
    } else if p == 25 {
      // Reset blink
      let has_blink = (grid["current_flags"] / 64) - (grid["current_flags"] / 128) * 1
      if has_blink > 0 { grid["current_flags"] = grid["current_flags"] - 64 }
    } else if p == 27 {
      // Reset inverse
      let has_inverse = (grid["current_flags"] / 8) - (grid["current_flags"] / 16) * 1
      if has_inverse > 0 { grid["current_flags"] = grid["current_flags"] - 8 }
    } else if p == 29 {
      // Reset strikethrough
      let has_strike = (grid["current_flags"] / 32) - (grid["current_flags"] / 64) * 1
      if has_strike > 0 { grid["current_flags"] = grid["current_flags"] - 32 }
```

- [ ] **Step 3: ansi.hexa — 새 속성 출력**

`cell_attrs()` 함수 수정. 기존 플래그 체크 뒤에 (`if f >= 1` 블록 뒤):

flags 디코딩 로직을 전면 재작성 (기존 고정된 순서 대신 모든 비트 처리):

```hexa
pub fn cell_attrs(fg: int, bg: int, flags: int) -> string {
  let out = ansi_reset()
  if flags > 0 {
    let f = flags
    if f >= 64 {
      out = out + "\x1b[5m"
      f = f - 64
    }
    if f >= 32 {
      out = out + "\x1b[9m"
      f = f - 32
    }
    if f >= 16 {
      out = out + ansi_dim()
      f = f - 16
    }
    if f >= 8 {
      out = out + ansi_inverse()
      f = f - 8
    }
    if f >= 4 {
      out = out + ansi_underline()
      f = f - 4
    }
    if f >= 2 {
      out = out + ansi_italic()
      f = f - 2
    }
    if f >= 1 {
      out = out + ansi_bold()
    }
  }
  out = out + ansi_fg(fg) + ansi_bg(bg)
  return out
}
```

- [ ] **Step 4: vt_parser.hexa — DEC Special Graphics charset**

`new_vt_parser()`에 charset 필드 추가:

```hexa
    "charset": 0
```

(0 = ASCII, 1 = DEC Special Graphics)

`vt_process()`의 escape 상태 (line ~282)에 charset 전환 추가. `byte == 80` (P→DCS) 분기 뒤에:

```hexa
      } else if byte == 40 {
        // ( — charset designator, next byte selects charset
        // Consume next byte
        if i + 1 < len(data) {
          let next = data[i + 1]
          if next == "0" {
            parser["charset"] = 1
          } else {
            parser["charset"] = 0
          }
          i = i + 1
        }
        parser["state"] = st_ground
```

ground 상태에서 printable character 출력 시 charset 매핑 적용. `byte >= 32` 분기 (line ~277) 수정:

```hexa
      } else if byte >= 32 {
        let out_ch = ch
        if parser["charset"] == 1 {
          // DEC Special Graphics mapping
          if ch == "j" { out_ch = "\u2518" }
          else if ch == "k" { out_ch = "\u2510" }
          else if ch == "l" { out_ch = "\u250c" }
          else if ch == "m" { out_ch = "\u2514" }
          else if ch == "n" { out_ch = "\u253c" }
          else if ch == "q" { out_ch = "\u2500" }
          else if ch == "t" { out_ch = "\u251c" }
          else if ch == "u" { out_ch = "\u2524" }
          else if ch == "v" { out_ch = "\u2534" }
          else if ch == "w" { out_ch = "\u252c" }
          else if ch == "x" { out_ch = "\u2502" }
          else if ch == "a" { out_ch = "\u2592" }
        }
        grid = grid_put_char(grid, out_ch, grid["current_fg"], grid["current_bg"], grid["current_flags"])
      }
```

- [ ] **Step 5: 검증**

Run: `hexa run app/main.hexa` 후:
```bash
printf '\e[9mstrikethrough\e[0m\n'
printf '\e[5mblink\e[0m\n'
printf '\e(0lqqqqk\e(B\n'  # DEC line drawing: ┌────┐
# 위 출력이 박스 모양 (┌────┐)으로 표시되는지 확인
```

- [ ] **Step 6: Commit**

```bash
git add core/terminal/grid.hexa core/terminal/vt_parser.hexa core/render/ansi.hexa
git commit -m "feat: SGR blink/strikethrough + DEC Special Graphics 문자셋"
```

---

### Task 8: CSI 누락 시퀀스 보강

**Files:**
- Modify: `core/terminal/vt_parser.hexa` (dispatch_csi 확장)
- Modify: `core/terminal/grid.hexa` (필요한 그리드 연산)

- [ ] **Step 1: CSI P — Delete Characters (DCH)**

`core/terminal/grid.hexa`에 추가:

```hexa
pub fn grid_delete_chars(grid: map, n: int) -> map {
  let row = grid["cursor_row"]
  let col = grid["cursor_col"]
  let cols = grid["cols"]
  // Shift characters left
  let c = col
  while c < cols - n {
    grid["cells"][row][c] = grid["cells"][row][c + n]
    c = c + 1
  }
  // Clear vacated characters at end
  c = cols - n
  while c < cols {
    grid["cells"][row][c] = new_cell()
    c = c + 1
  }
  return grid
}
```

`core/terminal/vt_parser.hexa`의 `dispatch_csi()`에 추가 (line ~206 부근, `M` 분기 뒤):

```hexa
  } else if final_ch == "P" {
    // Delete Characters (DCH)
    grid = grid_delete_chars(grid, n)
```

- [ ] **Step 2: CSI @ — Insert Characters (ICH)**

`core/terminal/grid.hexa`에 추가:

```hexa
pub fn grid_insert_chars(grid: map, n: int) -> map {
  let row = grid["cursor_row"]
  let col = grid["cursor_col"]
  let cols = grid["cols"]
  // Shift characters right
  let c = cols - 1
  while c >= col + n {
    grid["cells"][row][c] = grid["cells"][row][c - n]
    c = c - 1
  }
  // Clear inserted positions
  c = col
  while c < col + n && c < cols {
    grid["cells"][row][c] = new_cell()
    c = c + 1
  }
  return grid
}
```

`dispatch_csi()`에 추가:

```hexa
  } else if final_ch == "@" {
    // Insert Characters (ICH)
    grid = grid_insert_chars(grid, n)
```

- [ ] **Step 3: CSI d — Line Position Absolute (VPA)**

`dispatch_csi()`에 추가:

```hexa
  } else if final_ch == "d" {
    // Line Position Absolute — move to row n, keep col
    let row = n - 1
    if row < 0 { row = 0 }
    if row >= grid["rows"] { row = grid["rows"] - 1 }
    grid["cursor_row"] = row
```

- [ ] **Step 4: CSI G — Cursor Character Absolute (CHA)**

```hexa
  } else if final_ch == "G" {
    // Cursor Character Absolute — move to col n
    let col = n - 1
    if col < 0 { col = 0 }
    if col >= grid["cols"] { col = grid["cols"] - 1 }
    grid["cursor_col"] = col
```

- [ ] **Step 5: CSI X — Erase Characters (ECH)**

```hexa
  } else if final_ch == "X" {
    // Erase Characters — fill n chars from cursor with blanks
    let col = grid["cursor_col"]
    let end = col + n
    if end > grid["cols"] { end = grid["cols"] }
    while col < end {
      grid["cells"][grid["cursor_row"]][col] = new_cell()
      col = col + 1
    }
```

- [ ] **Step 6: CSI S/T — Scroll Up/Down**

```hexa
  } else if final_ch == "S" {
    // Scroll Up n lines
    let i = 0
    while i < n {
      grid = grid_scroll_up(grid)
      i = i + 1
    }
  } else if final_ch == "T" {
    // Scroll Down n lines
    let i = 0
    while i < n {
      grid = grid_scroll_down(grid)
      i = i + 1
    }
```

- [ ] **Step 7: CSI n — Device Status Report (DSR)**

이 시퀀스는 앱이 커서 위치를 요청할 때 사용. 응답을 PTY로 보내야 하므로 dispatch_csi 반환값에 "reply" 필드를 추가:

반환값 수정: `#{"grid": grid, "title": title, "parser": parser, "reply": ""}`

```hexa
  } else if final_ch == "n" {
    // Device Status Report
    if params[0] == 6 {
      // Report cursor position: ESC [ row ; col R
      title = ""
      // Use "reply" field to send response
      let reply = "\x1b[" + str(grid["cursor_row"] + 1) + ";" + str(grid["cursor_col"] + 1) + "R"
      return #{"grid": grid, "title": title, "parser": parser, "reply": reply}
    }
```

기본 반환문도 수정:
```hexa
  return #{"grid": grid, "title": title, "parser": parser, "reply": ""}
```

`vt_process()`에서 reply 처리를 위해 main.hexa로 reply를 전달해야 한다. vt_process 반환값에 "reply" 추가:

```hexa
  return #{"parser": parser, "grid": grid, "title": title, "reply": reply}
```

vt_process 시작에 `let reply = ""` 추가, dispatch_csi 호출 후:
```hexa
        if len(result["reply"]) > 0 {
          reply = result["reply"]
        }
```

`app/main.hexa`에서 vt_process 결과 처리 부분에 reply 전달:

```hexa
    if len(result["reply"]) > 0 {
      pty_write(master_fd, result["reply"])
    }
```

- [ ] **Step 8: 검증**

Run: `hexa run app/main.hexa` 후:
```bash
# nano, less 등 실행하여 화면 렌더링 정상 확인
nano /tmp/test.txt
less /etc/hosts
```

- [ ] **Step 9: Commit**

```bash
git add core/terminal/vt_parser.hexa core/terminal/grid.hexa app/main.hexa
git commit -m "feat: CSI P/@/d/G/X/S/T/n 시퀀스 — DCH, ICH, VPA, CHA, ECH, scroll, DSR"
```

---

### Task 9: VOID 프로토콜 연결

**Files:**
- Modify: `core/terminal/vt_parser.hexa` (OSC 777 디스패치)
- Modify: `core/terminal/protocol.hexa` (프로토콜 핸들러)
- Modify: `app/main.hexa` (use protocol, 프로토콜 결과 처리)

- [ ] **Step 1: protocol.hexa — 프로토콜 파싱 함수**

`core/terminal/protocol.hexa` 재작성:

```hexa
// protocol.hexa — VOID terminal protocol handler
// VOID Layer 3: Terminal Core

// VOID Protocol: ESC ] 777 ; type ; payload ST
// Types:
//   notify;title;body     — desktop notification
//   cwd;path              — current working directory
//   theme;name            — switch theme

pub fn void_parse(payload: string) -> map {
  // Parse "type;arg1;arg2..." format
  let parts = []
  let current = ""
  let i = 0
  while i < len(payload) {
    if payload[i] == ";" {
      parts = parts + [current]
      current = ""
    } else {
      current = current + payload[i]
    }
    i = i + 1
  }
  parts = parts + [current]

  if len(parts) == 0 {
    return #{"type": "unknown", "payload": ""}
  }

  let msg_type = parts[0]
  let msg_payload = ""
  if len(parts) > 1 {
    msg_payload = parts[1]
  }

  return #{"type": msg_type, "payload": msg_payload, "parts": parts}
}

fn void_protocol_prefix() -> string {
  return "\x1b]777;"
}

fn void_protocol_suffix() -> string {
  return "\x07"
}

pub fn void_send(fd: int, msg_type: string, payload: string) {
  let msg = void_protocol_prefix() + msg_type + ";" + payload + void_protocol_suffix()
  extern fn write(fd: int, buf: *Byte, count: int) -> int
  write(fd, cstring(msg), len(msg))
}
```

- [ ] **Step 2: vt_parser.hexa — OSC 777 디스패치**

`handle_osc()` 수정:

```hexa
pub fn handle_osc(osc_str: string, current_title: string) -> map {
  if len(osc_str) < 2 {
    return #{"title": current_title, "void_msg": null}
  }

  // Check for "777;" prefix — VOID protocol
  if len(osc_str) > 4 && osc_str[0] == "7" && osc_str[1] == "7" && osc_str[2] == "7" && osc_str[3] == ";" {
    let payload = ""
    let i = 4
    while i < len(osc_str) {
      payload = payload + osc_str[i]
      i = i + 1
    }
    return #{"title": current_title, "void_msg": payload}
  }

  let osc_num = osc_str[0]
  if len(osc_str) > 1 && osc_str[1] == ";" {
    if osc_num == "0" || osc_num == "2" {
      let title = ""
      let i = 2
      while i < len(osc_str) {
        title = title + osc_str[i]
        i = i + 1
      }
      return #{"title": title, "void_msg": null}
    }
  }
  return #{"title": current_title, "void_msg": null}
}
```

**중요:** `handle_osc`의 반환값이 string에서 map으로 변경되므로, 호출부도 수정 필요.

`vt_process()`에서 `handle_osc` 호출부 수정 (OSC 종료 시, line ~354, ~358):

```hexa
        let osc_result = handle_osc(parser["osc_string"], title)
        title = osc_result["title"]
        // void_msg는 vt_process 반환값으로 전달
```

vt_process 반환값에 `"void_msg"` 추가. 초기값 `let void_msg = null`, OSC 결과에서:
```hexa
        if osc_result["void_msg"] != null {
          void_msg = osc_result["void_msg"]
        }
```

반환:
```hexa
  return #{"parser": parser, "grid": grid, "title": title, "reply": reply, "void_msg": void_msg}
```

- [ ] **Step 3: main.hexa — 프로토콜 import + 처리**

`use terminal::protocol` 추가.

PTY 읽기 결과 처리에서:
```hexa
    if result["void_msg"] != null {
      let msg = void_parse(result["void_msg"])
      if msg["type"] == "cwd" {
        window_title = msg["payload"]
      }
    }
```

- [ ] **Step 4: 검증**

Run: `hexa run app/main.hexa` 후:
```bash
printf '\e]777;cwd;/tmp\x07'
# statusbar에 /tmp가 title로 표시되는지 확인
```

- [ ] **Step 5: Commit**

```bash
git add core/terminal/protocol.hexa core/terminal/vt_parser.hexa app/main.hexa
git commit -m "feat: VOID 프로토콜 연결 — OSC 777 파싱 + cwd 핸들링"
```

---

## Dependency Graph

```
Task 1 (TrueColor) ─── independent
Task 2 (Resize)    ─── independent
Task 3 (Alt Screen) ── independent
Task 4 (Mouse)     ─── depends on Task 3 (dispatch_csi parser 반환값 변경)
Task 5 (Scrollback) ── independent
Task 6 (Diff Render) ─ depends on Task 3 (grid_save_for_alt 사용)
Task 7 (SGR+DEC)   ─── independent
Task 8 (CSI 보강)   ── depends on Task 4 (dispatch_csi 반환값 reply 필드)
Task 9 (Protocol)  ─── depends on Task 8 (vt_process 반환값 확장)
```

**권장 실행 순서:** 1 → 2 → 3 → 7 → 4 → 5 → 6 → 8 → 9
