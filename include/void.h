// Void embedding API. The documentation for the embedding API is
// only within the Zig source files that define the implementations. This
// isn't meant to be a general purpose embedding API (yet) so there hasn't
// been documentation or example work beyond that.
//
// The only consumer of this API is the macOS app, but the API is built to
// be more general purpose.
#ifndef VOID_H
#define VOID_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef _MSC_VER
#include <BaseTsd.h>
typedef SSIZE_T ssize_t;
#else
#include <sys/types.h>
#endif

//-------------------------------------------------------------------
// Macros

#define VOID_SUCCESS 0

// Symbol visibility for shared library builds. On Windows, functions
// are exported from the DLL when building and imported when consuming.
// On other platforms with GCC/Clang, functions are marked with default
// visibility so they remain accessible when the library is built with
// -fvisibility=hidden. For static library builds, define VOID_STATIC
// before including this header to make this a no-op.
#ifndef VOID_API
#if defined(VOID_STATIC)
  #define VOID_API
#elif defined(_WIN32) || defined(_WIN64)
  #ifdef VOID_BUILD_SHARED
    #define VOID_API __declspec(dllexport)
  #else
    #define VOID_API __declspec(dllimport)
  #endif
#elif defined(__GNUC__) && __GNUC__ >= 4
  #define VOID_API __attribute__((visibility("default")))
#else
  #define VOID_API
#endif
#endif

//-------------------------------------------------------------------
// Types

// Opaque types
typedef void* void_app_t;
typedef void* void_config_t;
typedef void* void_surface_t;
typedef void* void_inspector_t;

// All the types below are fully defined and must be kept in sync with
// their Zig counterparts. Any changes to these types MUST have an associated
// Zig change.
typedef enum {
  VOID_PLATFORM_INVALID,
  VOID_PLATFORM_MACOS,
  VOID_PLATFORM_IOS,
} void_platform_e;

typedef enum {
  VOID_CLIPBOARD_STANDARD,
  VOID_CLIPBOARD_SELECTION,
} void_clipboard_e;

typedef struct {
  const char *mime;
  const char *data;
} void_clipboard_content_s;

typedef enum {
  VOID_CLIPBOARD_REQUEST_PASTE,
  VOID_CLIPBOARD_REQUEST_OSC_52_READ,
  VOID_CLIPBOARD_REQUEST_OSC_52_WRITE,
} void_clipboard_request_e;

typedef enum {
  VOID_MOUSE_RELEASE,
  VOID_MOUSE_PRESS,
} void_input_mouse_state_e;

typedef enum {
  VOID_MOUSE_UNKNOWN,
  VOID_MOUSE_LEFT,
  VOID_MOUSE_RIGHT,
  VOID_MOUSE_MIDDLE,
  VOID_MOUSE_FOUR,
  VOID_MOUSE_FIVE,
  VOID_MOUSE_SIX,
  VOID_MOUSE_SEVEN,
  VOID_MOUSE_EIGHT,
  VOID_MOUSE_NINE,
  VOID_MOUSE_TEN,
  VOID_MOUSE_ELEVEN,
} void_input_mouse_button_e;

typedef enum {
  VOID_MOUSE_MOMENTUM_NONE,
  VOID_MOUSE_MOMENTUM_BEGAN,
  VOID_MOUSE_MOMENTUM_STATIONARY,
  VOID_MOUSE_MOMENTUM_CHANGED,
  VOID_MOUSE_MOMENTUM_ENDED,
  VOID_MOUSE_MOMENTUM_CANCELLED,
  VOID_MOUSE_MOMENTUM_MAY_BEGIN,
} void_input_mouse_momentum_e;

typedef enum {
  VOID_COLOR_SCHEME_LIGHT = 0,
  VOID_COLOR_SCHEME_DARK = 1,
} void_color_scheme_e;

// This is a packed struct (see src/input/mouse.zig) but the C standard
// afaik doesn't let us reliably define packed structs so we build it up
// from scratch.
typedef int void_input_scroll_mods_t;

typedef enum {
  VOID_MODS_NONE = 0,
  VOID_MODS_SHIFT = 1 << 0,
  VOID_MODS_CTRL = 1 << 1,
  VOID_MODS_ALT = 1 << 2,
  VOID_MODS_SUPER = 1 << 3,
  VOID_MODS_CAPS = 1 << 4,
  VOID_MODS_NUM = 1 << 5,
  VOID_MODS_SHIFT_RIGHT = 1 << 6,
  VOID_MODS_CTRL_RIGHT = 1 << 7,
  VOID_MODS_ALT_RIGHT = 1 << 8,
  VOID_MODS_SUPER_RIGHT = 1 << 9,
} void_input_mods_e;

typedef enum {
  VOID_BINDING_FLAGS_CONSUMED = 1 << 0,
  VOID_BINDING_FLAGS_ALL = 1 << 1,
  VOID_BINDING_FLAGS_GLOBAL = 1 << 2,
  VOID_BINDING_FLAGS_PERFORMABLE = 1 << 3,
} void_binding_flags_e;

typedef enum {
  VOID_ACTION_RELEASE,
  VOID_ACTION_PRESS,
  VOID_ACTION_REPEAT,
} void_input_action_e;

// Based on: https://www.w3.org/TR/uievents-code/
typedef enum {
  VOID_KEY_UNIDENTIFIED,

  // "Writing System Keys" § 3.1.1
  VOID_KEY_BACKQUOTE,
  VOID_KEY_BACKSLASH,
  VOID_KEY_BRACKET_LEFT,
  VOID_KEY_BRACKET_RIGHT,
  VOID_KEY_COMMA,
  VOID_KEY_DIGIT_0,
  VOID_KEY_DIGIT_1,
  VOID_KEY_DIGIT_2,
  VOID_KEY_DIGIT_3,
  VOID_KEY_DIGIT_4,
  VOID_KEY_DIGIT_5,
  VOID_KEY_DIGIT_6,
  VOID_KEY_DIGIT_7,
  VOID_KEY_DIGIT_8,
  VOID_KEY_DIGIT_9,
  VOID_KEY_EQUAL,
  VOID_KEY_INTL_BACKSLASH,
  VOID_KEY_INTL_RO,
  VOID_KEY_INTL_YEN,
  VOID_KEY_A,
  VOID_KEY_B,
  VOID_KEY_C,
  VOID_KEY_D,
  VOID_KEY_E,
  VOID_KEY_F,
  VOID_KEY_G,
  VOID_KEY_H,
  VOID_KEY_I,
  VOID_KEY_J,
  VOID_KEY_K,
  VOID_KEY_L,
  VOID_KEY_M,
  VOID_KEY_N,
  VOID_KEY_O,
  VOID_KEY_P,
  VOID_KEY_Q,
  VOID_KEY_R,
  VOID_KEY_S,
  VOID_KEY_T,
  VOID_KEY_U,
  VOID_KEY_V,
  VOID_KEY_W,
  VOID_KEY_X,
  VOID_KEY_Y,
  VOID_KEY_Z,
  VOID_KEY_MINUS,
  VOID_KEY_PERIOD,
  VOID_KEY_QUOTE,
  VOID_KEY_SEMICOLON,
  VOID_KEY_SLASH,

  // "Functional Keys" § 3.1.2
  VOID_KEY_ALT_LEFT,
  VOID_KEY_ALT_RIGHT,
  VOID_KEY_BACKSPACE,
  VOID_KEY_CAPS_LOCK,
  VOID_KEY_CONTEXT_MENU,
  VOID_KEY_CONTROL_LEFT,
  VOID_KEY_CONTROL_RIGHT,
  VOID_KEY_ENTER,
  VOID_KEY_META_LEFT,
  VOID_KEY_META_RIGHT,
  VOID_KEY_SHIFT_LEFT,
  VOID_KEY_SHIFT_RIGHT,
  VOID_KEY_SPACE,
  VOID_KEY_TAB,
  VOID_KEY_CONVERT,
  VOID_KEY_KANA_MODE,
  VOID_KEY_NON_CONVERT,

  // "Control Pad Section" § 3.2
  VOID_KEY_DELETE,
  VOID_KEY_END,
  VOID_KEY_HELP,
  VOID_KEY_HOME,
  VOID_KEY_INSERT,
  VOID_KEY_PAGE_DOWN,
  VOID_KEY_PAGE_UP,

  // "Arrow Pad Section" § 3.3
  VOID_KEY_ARROW_DOWN,
  VOID_KEY_ARROW_LEFT,
  VOID_KEY_ARROW_RIGHT,
  VOID_KEY_ARROW_UP,

  // "Numpad Section" § 3.4
  VOID_KEY_NUM_LOCK,
  VOID_KEY_NUMPAD_0,
  VOID_KEY_NUMPAD_1,
  VOID_KEY_NUMPAD_2,
  VOID_KEY_NUMPAD_3,
  VOID_KEY_NUMPAD_4,
  VOID_KEY_NUMPAD_5,
  VOID_KEY_NUMPAD_6,
  VOID_KEY_NUMPAD_7,
  VOID_KEY_NUMPAD_8,
  VOID_KEY_NUMPAD_9,
  VOID_KEY_NUMPAD_ADD,
  VOID_KEY_NUMPAD_BACKSPACE,
  VOID_KEY_NUMPAD_CLEAR,
  VOID_KEY_NUMPAD_CLEAR_ENTRY,
  VOID_KEY_NUMPAD_COMMA,
  VOID_KEY_NUMPAD_DECIMAL,
  VOID_KEY_NUMPAD_DIVIDE,
  VOID_KEY_NUMPAD_ENTER,
  VOID_KEY_NUMPAD_EQUAL,
  VOID_KEY_NUMPAD_MEMORY_ADD,
  VOID_KEY_NUMPAD_MEMORY_CLEAR,
  VOID_KEY_NUMPAD_MEMORY_RECALL,
  VOID_KEY_NUMPAD_MEMORY_STORE,
  VOID_KEY_NUMPAD_MEMORY_SUBTRACT,
  VOID_KEY_NUMPAD_MULTIPLY,
  VOID_KEY_NUMPAD_PAREN_LEFT,
  VOID_KEY_NUMPAD_PAREN_RIGHT,
  VOID_KEY_NUMPAD_SUBTRACT,
  VOID_KEY_NUMPAD_SEPARATOR,
  VOID_KEY_NUMPAD_UP,
  VOID_KEY_NUMPAD_DOWN,
  VOID_KEY_NUMPAD_RIGHT,
  VOID_KEY_NUMPAD_LEFT,
  VOID_KEY_NUMPAD_BEGIN,
  VOID_KEY_NUMPAD_HOME,
  VOID_KEY_NUMPAD_END,
  VOID_KEY_NUMPAD_INSERT,
  VOID_KEY_NUMPAD_DELETE,
  VOID_KEY_NUMPAD_PAGE_UP,
  VOID_KEY_NUMPAD_PAGE_DOWN,

  // "Function Section" § 3.5
  VOID_KEY_ESCAPE,
  VOID_KEY_F1,
  VOID_KEY_F2,
  VOID_KEY_F3,
  VOID_KEY_F4,
  VOID_KEY_F5,
  VOID_KEY_F6,
  VOID_KEY_F7,
  VOID_KEY_F8,
  VOID_KEY_F9,
  VOID_KEY_F10,
  VOID_KEY_F11,
  VOID_KEY_F12,
  VOID_KEY_F13,
  VOID_KEY_F14,
  VOID_KEY_F15,
  VOID_KEY_F16,
  VOID_KEY_F17,
  VOID_KEY_F18,
  VOID_KEY_F19,
  VOID_KEY_F20,
  VOID_KEY_F21,
  VOID_KEY_F22,
  VOID_KEY_F23,
  VOID_KEY_F24,
  VOID_KEY_F25,
  VOID_KEY_FN,
  VOID_KEY_FN_LOCK,
  VOID_KEY_PRINT_SCREEN,
  VOID_KEY_SCROLL_LOCK,
  VOID_KEY_PAUSE,

  // "Media Keys" § 3.6
  VOID_KEY_BROWSER_BACK,
  VOID_KEY_BROWSER_FAVORITES,
  VOID_KEY_BROWSER_FORWARD,
  VOID_KEY_BROWSER_HOME,
  VOID_KEY_BROWSER_REFRESH,
  VOID_KEY_BROWSER_SEARCH,
  VOID_KEY_BROWSER_STOP,
  VOID_KEY_EJECT,
  VOID_KEY_LAUNCH_APP_1,
  VOID_KEY_LAUNCH_APP_2,
  VOID_KEY_LAUNCH_MAIL,
  VOID_KEY_MEDIA_PLAY_PAUSE,
  VOID_KEY_MEDIA_SELECT,
  VOID_KEY_MEDIA_STOP,
  VOID_KEY_MEDIA_TRACK_NEXT,
  VOID_KEY_MEDIA_TRACK_PREVIOUS,
  VOID_KEY_POWER,
  VOID_KEY_SLEEP,
  VOID_KEY_AUDIO_VOLUME_DOWN,
  VOID_KEY_AUDIO_VOLUME_MUTE,
  VOID_KEY_AUDIO_VOLUME_UP,
  VOID_KEY_WAKE_UP,

  // "Legacy, Non-standard, and Special Keys" § 3.7
  VOID_KEY_COPY,
  VOID_KEY_CUT,
  VOID_KEY_PASTE,
} void_input_key_e;

typedef struct {
  void_input_action_e action;
  void_input_mods_e mods;
  void_input_mods_e consumed_mods;
  uint32_t keycode;
  const char* text;
  uint32_t unshifted_codepoint;
  bool composing;
} void_input_key_s;

typedef enum {
  VOID_TRIGGER_PHYSICAL,
  VOID_TRIGGER_UNICODE,
  VOID_TRIGGER_CATCH_ALL,
} void_input_trigger_tag_e;

typedef union {
  void_input_key_e translated;
  void_input_key_e physical;
  uint32_t unicode;
  // catch_all has no payload
} void_input_trigger_key_u;

typedef struct {
  void_input_trigger_tag_e tag;
  void_input_trigger_key_u key;
  void_input_mods_e mods;
} void_input_trigger_s;

typedef struct {
  const char* action_key;
  const char* action;
  const char* title;
  const char* description;
} void_command_s;

typedef enum {
  VOID_BUILD_MODE_DEBUG,
  VOID_BUILD_MODE_RELEASE_SAFE,
  VOID_BUILD_MODE_RELEASE_FAST,
  VOID_BUILD_MODE_RELEASE_SMALL,
} void_build_mode_e;

typedef struct {
  void_build_mode_e build_mode;
  const char* version;
  uintptr_t version_len;
} void_info_s;

typedef struct {
  const char* message;
} void_diagnostic_s;

typedef struct {
  const char* ptr;
  uintptr_t len;
  bool sentinel;
} void_string_s;

typedef struct {
  double tl_px_x;
  double tl_px_y;
  uint32_t offset_start;
  uint32_t offset_len;
  const char* text;
  uintptr_t text_len;
} void_text_s;

typedef enum {
  VOID_POINT_ACTIVE,
  VOID_POINT_VIEWPORT,
  VOID_POINT_SCREEN,
  VOID_POINT_SURFACE,
} void_point_tag_e;

typedef enum {
  VOID_POINT_COORD_EXACT,
  VOID_POINT_COORD_TOP_LEFT,
  VOID_POINT_COORD_BOTTOM_RIGHT,
} void_point_coord_e;

typedef struct {
  void_point_tag_e tag;
  void_point_coord_e coord;
  uint32_t x;
  uint32_t y;
} void_point_s;

typedef struct {
  void_point_s top_left;
  void_point_s bottom_right;
  bool rectangle;
} void_selection_s;

typedef struct {
  const char* key;
  const char* value;
} void_env_var_s;

typedef struct {
  void* nsview;
} void_platform_macos_s;

typedef struct {
  void* uiview;
} void_platform_ios_s;

typedef union {
  void_platform_macos_s macos;
  void_platform_ios_s ios;
} void_platform_u;

typedef enum {
  VOID_SURFACE_CONTEXT_WINDOW = 0,
  VOID_SURFACE_CONTEXT_TAB = 1,
  VOID_SURFACE_CONTEXT_SPLIT = 2,
} void_surface_context_e;

typedef struct {
  void_platform_e platform_tag;
  void_platform_u platform;
  void* userdata;
  double scale_factor;
  float font_size;
  const char* working_directory;
  const char* command;
  void_env_var_s* env_vars;
  size_t env_var_count;
  const char* initial_input;
  bool wait_after_command;
  void_surface_context_e context;
  // P7 Phase B2: stable UUID for `~/.void/sessions/by-uuid/<uuid>.ring`
  // replay. Survives across abnormal-termination via TerminalRestorable
  // SplitTree Codable. NULL = ephemeral surface (no persist/replay).
  const char* surface_uuid;
} void_surface_config_s;

typedef struct {
  uint16_t columns;
  uint16_t rows;
  uint32_t width_px;
  uint32_t height_px;
  uint32_t cell_width_px;
  uint32_t cell_height_px;
} void_surface_size_s;

// Config types

// config.Path
typedef struct {
  const char* path;
  bool optional;
} void_config_path_s;

// config.Color
typedef struct {
  uint8_t r;
  uint8_t g;
  uint8_t b;
} void_config_color_s;

// config.ColorList
typedef struct {
  const void_config_color_s* colors;
  size_t len;
} void_config_color_list_s;

// config.RepeatableCommand
typedef struct {
  const void_command_s* commands;
  size_t len;
} void_config_command_list_s;

// config.Palette
typedef struct {
  void_config_color_s colors[256];
} void_config_palette_s;

// config.QuickTerminalSize
typedef enum {
  VOID_QUICK_TERMINAL_SIZE_NONE,
  VOID_QUICK_TERMINAL_SIZE_PERCENTAGE,
  VOID_QUICK_TERMINAL_SIZE_PIXELS,
} void_quick_terminal_size_tag_e;

typedef union {
  float percentage;
  uint32_t pixels;
} void_quick_terminal_size_value_u;

typedef struct {
  void_quick_terminal_size_tag_e tag;
  void_quick_terminal_size_value_u value;
} void_quick_terminal_size_s;

typedef struct {
  void_quick_terminal_size_s primary;
  void_quick_terminal_size_s secondary;
} void_config_quick_terminal_size_s;

// config.Fullscreen
typedef enum {
  VOID_CONFIG_FULLSCREEN_FALSE,
  VOID_CONFIG_FULLSCREEN_TRUE,
  VOID_CONFIG_FULLSCREEN_NON_NATIVE,
  VOID_CONFIG_FULLSCREEN_NON_NATIVE_VISIBLE_MENU,
  VOID_CONFIG_FULLSCREEN_NON_NATIVE_PADDED_NOTCH,
} void_config_fullscreen_e;

// apprt.Target.Key
typedef enum {
  VOID_TARGET_APP,
  VOID_TARGET_SURFACE,
} void_target_tag_e;

typedef union {
  void_surface_t surface;
} void_target_u;

typedef struct {
  void_target_tag_e tag;
  void_target_u target;
} void_target_s;

// apprt.action.SplitDirection
typedef enum {
  VOID_SPLIT_DIRECTION_RIGHT,
  VOID_SPLIT_DIRECTION_DOWN,
  VOID_SPLIT_DIRECTION_LEFT,
  VOID_SPLIT_DIRECTION_UP,
} void_action_split_direction_e;

// apprt.action.GotoSplit
typedef enum {
  VOID_GOTO_SPLIT_PREVIOUS,
  VOID_GOTO_SPLIT_NEXT,
  VOID_GOTO_SPLIT_UP,
  VOID_GOTO_SPLIT_LEFT,
  VOID_GOTO_SPLIT_DOWN,
  VOID_GOTO_SPLIT_RIGHT,
} void_action_goto_split_e;

// apprt.action.GotoWindow
typedef enum {
  VOID_GOTO_WINDOW_PREVIOUS,
  VOID_GOTO_WINDOW_NEXT,
} void_action_goto_window_e;

// apprt.action.ResizeSplit.Direction
typedef enum {
  VOID_RESIZE_SPLIT_UP,
  VOID_RESIZE_SPLIT_DOWN,
  VOID_RESIZE_SPLIT_LEFT,
  VOID_RESIZE_SPLIT_RIGHT,
} void_action_resize_split_direction_e;

// apprt.action.ResizeSplit
typedef struct {
  uint16_t amount;
  void_action_resize_split_direction_e direction;
} void_action_resize_split_s;

// apprt.action.MoveTab
typedef struct {
  ssize_t amount;
} void_action_move_tab_s;

// apprt.action.GotoTab
typedef enum {
  VOID_GOTO_TAB_PREVIOUS = -1,
  VOID_GOTO_TAB_NEXT = -2,
  VOID_GOTO_TAB_LAST = -3,
} void_action_goto_tab_e;

// apprt.action.Fullscreen
typedef enum {
  VOID_FULLSCREEN_NATIVE,
  VOID_FULLSCREEN_MACOS_NON_NATIVE,
  VOID_FULLSCREEN_MACOS_NON_NATIVE_VISIBLE_MENU,
  VOID_FULLSCREEN_MACOS_NON_NATIVE_PADDED_NOTCH,
} void_action_fullscreen_e;

// apprt.action.FloatWindow
typedef enum {
  VOID_FLOAT_WINDOW_ON,
  VOID_FLOAT_WINDOW_OFF,
  VOID_FLOAT_WINDOW_TOGGLE,
} void_action_float_window_e;

// apprt.action.SecureInput
typedef enum {
  VOID_SECURE_INPUT_ON,
  VOID_SECURE_INPUT_OFF,
  VOID_SECURE_INPUT_TOGGLE,
} void_action_secure_input_e;

// apprt.action.Inspector
typedef enum {
  VOID_INSPECTOR_TOGGLE,
  VOID_INSPECTOR_SHOW,
  VOID_INSPECTOR_HIDE,
} void_action_inspector_e;

// apprt.action.QuitTimer
typedef enum {
  VOID_QUIT_TIMER_START,
  VOID_QUIT_TIMER_STOP,
} void_action_quit_timer_e;

// apprt.action.Readonly
typedef enum {
  VOID_READONLY_OFF,
  VOID_READONLY_ON,
} void_action_readonly_e;

// apprt.action.DesktopNotification.C
typedef struct {
  const char* title;
  const char* body;
} void_action_desktop_notification_s;

// apprt.action.SetTitle.C
typedef struct {
  const char* title;
} void_action_set_title_s;

// apprt.action.PromptTitle
typedef enum {
  VOID_PROMPT_TITLE_SURFACE,
  VOID_PROMPT_TITLE_TAB,
} void_action_prompt_title_e;

// apprt.action.Pwd.C
typedef struct {
  const char* pwd;
} void_action_pwd_s;

// terminal.MouseShape
typedef enum {
  VOID_MOUSE_SHAPE_DEFAULT,
  VOID_MOUSE_SHAPE_CONTEXT_MENU,
  VOID_MOUSE_SHAPE_HELP,
  VOID_MOUSE_SHAPE_POINTER,
  VOID_MOUSE_SHAPE_PROGRESS,
  VOID_MOUSE_SHAPE_WAIT,
  VOID_MOUSE_SHAPE_CELL,
  VOID_MOUSE_SHAPE_CROSSHAIR,
  VOID_MOUSE_SHAPE_TEXT,
  VOID_MOUSE_SHAPE_VERTICAL_TEXT,
  VOID_MOUSE_SHAPE_ALIAS,
  VOID_MOUSE_SHAPE_COPY,
  VOID_MOUSE_SHAPE_MOVE,
  VOID_MOUSE_SHAPE_NO_DROP,
  VOID_MOUSE_SHAPE_NOT_ALLOWED,
  VOID_MOUSE_SHAPE_GRAB,
  VOID_MOUSE_SHAPE_GRABBING,
  VOID_MOUSE_SHAPE_ALL_SCROLL,
  VOID_MOUSE_SHAPE_COL_RESIZE,
  VOID_MOUSE_SHAPE_ROW_RESIZE,
  VOID_MOUSE_SHAPE_N_RESIZE,
  VOID_MOUSE_SHAPE_E_RESIZE,
  VOID_MOUSE_SHAPE_S_RESIZE,
  VOID_MOUSE_SHAPE_W_RESIZE,
  VOID_MOUSE_SHAPE_NE_RESIZE,
  VOID_MOUSE_SHAPE_NW_RESIZE,
  VOID_MOUSE_SHAPE_SE_RESIZE,
  VOID_MOUSE_SHAPE_SW_RESIZE,
  VOID_MOUSE_SHAPE_EW_RESIZE,
  VOID_MOUSE_SHAPE_NS_RESIZE,
  VOID_MOUSE_SHAPE_NESW_RESIZE,
  VOID_MOUSE_SHAPE_NWSE_RESIZE,
  VOID_MOUSE_SHAPE_ZOOM_IN,
  VOID_MOUSE_SHAPE_ZOOM_OUT,
} void_action_mouse_shape_e;

// apprt.action.MouseVisibility
typedef enum {
  VOID_MOUSE_VISIBLE,
  VOID_MOUSE_HIDDEN,
} void_action_mouse_visibility_e;

// apprt.action.MouseOverLink
typedef struct {
  const char* url;
  size_t len;
} void_action_mouse_over_link_s;

// apprt.action.SizeLimit
typedef struct {
  uint32_t min_width;
  uint32_t min_height;
  uint32_t max_width;
  uint32_t max_height;
} void_action_size_limit_s;

// apprt.action.InitialSize
typedef struct {
  uint32_t width;
  uint32_t height;
} void_action_initial_size_s;

// apprt.action.CellSize
typedef struct {
  uint32_t width;
  uint32_t height;
} void_action_cell_size_s;

// renderer.Health
typedef enum {
  VOID_RENDERER_HEALTH_HEALTHY,
  VOID_RENDERER_HEALTH_UNHEALTHY,
} void_action_renderer_health_e;

// apprt.action.KeySequence
typedef struct {
  bool active;
  void_input_trigger_s trigger;
} void_action_key_sequence_s;

// apprt.action.KeyTable.Tag
typedef enum {
  VOID_KEY_TABLE_ACTIVATE,
  VOID_KEY_TABLE_DEACTIVATE,
  VOID_KEY_TABLE_DEACTIVATE_ALL,
} void_action_key_table_tag_e;

// apprt.action.KeyTable.CValue
typedef union {
  struct {
    const char *name;
    size_t len;
  } activate;
} void_action_key_table_u;

// apprt.action.KeyTable.C
typedef struct {
  void_action_key_table_tag_e tag;
  void_action_key_table_u value;
} void_action_key_table_s;

// apprt.action.ColorKind
typedef enum {
  VOID_ACTION_COLOR_KIND_FOREGROUND = -1,
  VOID_ACTION_COLOR_KIND_BACKGROUND = -2,
  VOID_ACTION_COLOR_KIND_CURSOR = -3,
} void_action_color_kind_e;

// apprt.action.ColorChange
typedef struct {
  void_action_color_kind_e kind;
  uint8_t r;
  uint8_t g;
  uint8_t b;
} void_action_color_change_s;

// apprt.action.ConfigChange
typedef struct {
  void_config_t config;
} void_action_config_change_s;

// apprt.action.ReloadConfig
typedef struct {
  bool soft;
} void_action_reload_config_s;

// apprt.action.OpenUrlKind
typedef enum {
  VOID_ACTION_OPEN_URL_KIND_UNKNOWN,
  VOID_ACTION_OPEN_URL_KIND_TEXT,
  VOID_ACTION_OPEN_URL_KIND_HTML,
} void_action_open_url_kind_e;

// apprt.action.OpenUrl.C
typedef struct {
  void_action_open_url_kind_e kind;
  const char* url;
  uintptr_t len;
} void_action_open_url_s;

// apprt.action.CloseTabMode
typedef enum {
  VOID_ACTION_CLOSE_TAB_MODE_THIS,
  VOID_ACTION_CLOSE_TAB_MODE_OTHER,
  VOID_ACTION_CLOSE_TAB_MODE_RIGHT,
} void_action_close_tab_mode_e;

// apprt.surface.Message.ChildExited
typedef struct {
  uint32_t exit_code;
  uint64_t timetime_ms;
} void_surface_message_childexited_s;

// terminal.osc.Command.ProgressReport.State
typedef enum {
  VOID_PROGRESS_STATE_REMOVE,
  VOID_PROGRESS_STATE_SET,
  VOID_PROGRESS_STATE_ERROR,
  VOID_PROGRESS_STATE_INDETERMINATE,
  VOID_PROGRESS_STATE_PAUSE,
} void_action_progress_report_state_e;

// terminal.osc.Command.ProgressReport.C
typedef struct {
  void_action_progress_report_state_e state;
  // -1 if no progress was reported, otherwise 0-100 indicating percent
  // completeness.
  int8_t progress;
} void_action_progress_report_s;

// apprt.action.CommandFinished.C
typedef struct {
  // -1 if no exit code was reported, otherwise 0-255
  int16_t exit_code;
  // number of nanoseconds that command was running for
  uint64_t duration;
} void_action_command_finished_s;

// apprt.action.StartSearch.C
typedef struct {
  const char* needle;
} void_action_start_search_s;

// apprt.action.SearchTotal
typedef struct {
  ssize_t total;
} void_action_search_total_s;

// apprt.action.SearchSelected
typedef struct {
  ssize_t selected;
} void_action_search_selected_s;

// terminal.Scrollbar
typedef struct {
  uint64_t total;
  uint64_t offset;
  uint64_t len;
} void_action_scrollbar_s;

// apprt.Action.Key
typedef enum {
  VOID_ACTION_QUIT,
  VOID_ACTION_NEW_WINDOW,
  VOID_ACTION_NEW_TAB,
  VOID_ACTION_CLOSE_TAB,
  VOID_ACTION_NEW_SPLIT,
  VOID_ACTION_CLOSE_ALL_WINDOWS,
  VOID_ACTION_TOGGLE_MAXIMIZE,
  VOID_ACTION_TOGGLE_FULLSCREEN,
  VOID_ACTION_TOGGLE_TAB_OVERVIEW,
  VOID_ACTION_TOGGLE_WINDOW_DECORATIONS,
  VOID_ACTION_TOGGLE_QUICK_TERMINAL,
  VOID_ACTION_TOGGLE_COMMAND_PALETTE,
  VOID_ACTION_TOGGLE_VISIBILITY,
  VOID_ACTION_TOGGLE_BACKGROUND_OPACITY,
  VOID_ACTION_MOVE_TAB,
  VOID_ACTION_GOTO_TAB,
  VOID_ACTION_GOTO_SPLIT,
  VOID_ACTION_GOTO_WINDOW,
  VOID_ACTION_RESIZE_SPLIT,
  VOID_ACTION_EQUALIZE_SPLITS,
  VOID_ACTION_TOGGLE_GRID_MODE,
  VOID_ACTION_TOGGLE_SPLIT_ZOOM,
  VOID_ACTION_PRESENT_TERMINAL,
  VOID_ACTION_SIZE_LIMIT,
  VOID_ACTION_RESET_WINDOW_SIZE,
  VOID_ACTION_INITIAL_SIZE,
  VOID_ACTION_CELL_SIZE,
  VOID_ACTION_SCROLLBAR,
  VOID_ACTION_RENDER,
  VOID_ACTION_INSPECTOR,
  VOID_ACTION_SHOW_GTK_INSPECTOR,
  VOID_ACTION_RENDER_INSPECTOR,
  VOID_ACTION_DESKTOP_NOTIFICATION,
  VOID_ACTION_SET_TITLE,
  VOID_ACTION_SET_TAB_TITLE,
  VOID_ACTION_PROMPT_TITLE,
  VOID_ACTION_PWD,
  VOID_ACTION_MOUSE_SHAPE,
  VOID_ACTION_MOUSE_VISIBILITY,
  VOID_ACTION_MOUSE_OVER_LINK,
  VOID_ACTION_RENDERER_HEALTH,
  VOID_ACTION_OPEN_CONFIG,
  VOID_ACTION_QUIT_TIMER,
  VOID_ACTION_FLOAT_WINDOW,
  VOID_ACTION_SECURE_INPUT,
  VOID_ACTION_KEY_SEQUENCE,
  VOID_ACTION_KEY_TABLE,
  VOID_ACTION_COLOR_CHANGE,
  VOID_ACTION_RELOAD_CONFIG,
  VOID_ACTION_CONFIG_CHANGE,
  VOID_ACTION_CLOSE_WINDOW,
  VOID_ACTION_RING_BELL,
  VOID_ACTION_UNDO,
  VOID_ACTION_REDO,
  VOID_ACTION_CHECK_FOR_UPDATES,
  VOID_ACTION_OPEN_URL,
  VOID_ACTION_SHOW_CHILD_EXITED,
  VOID_ACTION_PROGRESS_REPORT,
  VOID_ACTION_SHOW_ON_SCREEN_KEYBOARD,
  VOID_ACTION_COMMAND_FINISHED,
  VOID_ACTION_START_SEARCH,
  VOID_ACTION_END_SEARCH,
  VOID_ACTION_SEARCH_TOTAL,
  VOID_ACTION_SEARCH_SELECTED,
  VOID_ACTION_READONLY,
  VOID_ACTION_COPY_TITLE_TO_CLIPBOARD,
} void_action_tag_e;

typedef union {
  void_action_split_direction_e new_split;
  void_action_fullscreen_e toggle_fullscreen;
  void_action_move_tab_s move_tab;
  void_action_goto_tab_e goto_tab;
  void_action_goto_split_e goto_split;
  void_action_goto_window_e goto_window;
  void_action_resize_split_s resize_split;
  void_action_size_limit_s size_limit;
  void_action_initial_size_s initial_size;
  void_action_cell_size_s cell_size;
  void_action_scrollbar_s scrollbar;
  void_action_inspector_e inspector;
  void_action_desktop_notification_s desktop_notification;
  void_action_set_title_s set_title;
  void_action_set_title_s set_tab_title;
  void_action_prompt_title_e prompt_title;
  void_action_pwd_s pwd;
  void_action_mouse_shape_e mouse_shape;
  void_action_mouse_visibility_e mouse_visibility;
  void_action_mouse_over_link_s mouse_over_link;
  void_action_renderer_health_e renderer_health;
  void_action_quit_timer_e quit_timer;
  void_action_float_window_e float_window;
  void_action_secure_input_e secure_input;
  void_action_key_sequence_s key_sequence;
  void_action_key_table_s key_table;
  void_action_color_change_s color_change;
  void_action_reload_config_s reload_config;
  void_action_config_change_s config_change;
  void_action_open_url_s open_url;
  void_action_close_tab_mode_e close_tab_mode;
  void_surface_message_childexited_s child_exited;
  void_action_progress_report_s progress_report;
  void_action_command_finished_s command_finished;
  void_action_start_search_s start_search;
  void_action_search_total_s search_total;
  void_action_search_selected_s search_selected;
  void_action_readonly_e readonly;
} void_action_u;

typedef struct {
  void_action_tag_e tag;
  void_action_u action;
} void_action_s;

typedef void (*void_runtime_wakeup_cb)(void*);
typedef bool (*void_runtime_read_clipboard_cb)(void*,
                                                  void_clipboard_e,
                                                  void*);
typedef void (*void_runtime_confirm_read_clipboard_cb)(
    void*,
    const char*,
    void*,
    void_clipboard_request_e);
typedef void (*void_runtime_write_clipboard_cb)(void*,
                                                   void_clipboard_e,
                                                   const void_clipboard_content_s*,
                                                   size_t,
                                                   bool);
typedef void (*void_runtime_close_surface_cb)(void*, bool);
typedef bool (*void_runtime_action_cb)(void_app_t,
                                          void_target_s,
                                          void_action_s);

typedef struct {
  void* userdata;
  bool supports_selection_clipboard;
  void_runtime_wakeup_cb wakeup_cb;
  void_runtime_action_cb action_cb;
  void_runtime_read_clipboard_cb read_clipboard_cb;
  void_runtime_confirm_read_clipboard_cb confirm_read_clipboard_cb;
  void_runtime_write_clipboard_cb write_clipboard_cb;
  void_runtime_close_surface_cb close_surface_cb;
} void_runtime_config_s;

// apprt.ipc.Target.Key
typedef enum {
  VOID_IPC_TARGET_CLASS,
  VOID_IPC_TARGET_DETECT,
} void_ipc_target_tag_e;

typedef union {
  char *klass;
} void_ipc_target_u;

typedef struct {
  void_ipc_target_tag_e tag;
  void_ipc_target_u target;
} chostty_ipc_target_s;

// apprt.ipc.Action.NewWindow
typedef struct {
  // This should be a null terminated list of strings.
  const char **arguments;
} void_ipc_action_new_window_s;

typedef union {
  void_ipc_action_new_window_s new_window;
} void_ipc_action_u;

// apprt.ipc.Action.Key
typedef enum {
  VOID_IPC_ACTION_NEW_WINDOW,
} void_ipc_action_tag_e;

//-------------------------------------------------------------------
// Published API

VOID_API int void_init(uintptr_t, char**);
VOID_API void void_cli_try_action(void);
VOID_API void_info_s void_info(void);
VOID_API const char* void_translate(const char*);
VOID_API void void_string_free(void_string_s);

VOID_API void_config_t void_config_new();
VOID_API void void_config_free(void_config_t);
VOID_API void_config_t void_config_clone(void_config_t);
VOID_API void void_config_load_cli_args(void_config_t);
VOID_API void void_config_load_file(void_config_t, const char*);
VOID_API void void_config_load_default_files(void_config_t);
VOID_API void void_config_load_recursive_files(void_config_t);
VOID_API void void_config_finalize(void_config_t);
VOID_API bool void_config_get(void_config_t, void*, const char*, uintptr_t);
VOID_API void_input_trigger_s void_config_trigger(void_config_t,
                                                              const char*,
                                                              uintptr_t);
VOID_API uint32_t void_config_diagnostics_count(void_config_t);
VOID_API void_diagnostic_s void_config_get_diagnostic(void_config_t, uint32_t);
VOID_API void_string_s void_config_open_path(void);

VOID_API void_app_t void_app_new(const void_runtime_config_s*,
                                             void_config_t);
VOID_API void void_app_free(void_app_t);
VOID_API void void_app_tick(void_app_t);
VOID_API void* void_app_userdata(void_app_t);
VOID_API void void_app_set_focus(void_app_t, bool);
VOID_API bool void_app_key(void_app_t, void_input_key_s);
VOID_API bool void_app_key_is_binding(void_app_t, void_input_key_s);
VOID_API void void_app_keyboard_changed(void_app_t);
VOID_API void void_app_open_config(void_app_t);
VOID_API void void_app_update_config(void_app_t, void_config_t);
VOID_API bool void_app_needs_confirm_quit(void_app_t);
VOID_API bool void_app_has_global_keybinds(void_app_t);
VOID_API void void_app_set_color_scheme(void_app_t, void_color_scheme_e);

VOID_API void_surface_config_s void_surface_config_new();

VOID_API void_surface_t void_surface_new(void_app_t,
                                                     const void_surface_config_s*);
VOID_API void void_surface_free(void_surface_t);
VOID_API void* void_surface_userdata(void_surface_t);
VOID_API void_app_t void_surface_app(void_surface_t);
VOID_API void_surface_config_s void_surface_inherited_config(void_surface_t, void_surface_context_e);
VOID_API void void_surface_update_config(void_surface_t, void_config_t);
VOID_API bool void_surface_needs_confirm_quit(void_surface_t);
VOID_API bool void_surface_process_exited(void_surface_t);
VOID_API void void_surface_refresh(void_surface_t);
VOID_API void void_surface_draw(void_surface_t);
VOID_API void void_surface_set_content_scale(void_surface_t, double, double);
VOID_API void void_surface_set_focus(void_surface_t, bool);
VOID_API void void_surface_set_occlusion(void_surface_t, bool);
VOID_API void void_surface_set_size(void_surface_t, uint32_t, uint32_t);
VOID_API void_surface_size_s void_surface_size(void_surface_t);
VOID_API uint64_t void_surface_foreground_pid(void_surface_t);
VOID_API void_string_s void_surface_tty_name(void_surface_t);
VOID_API void void_surface_set_color_scheme(void_surface_t,
                                                     void_color_scheme_e);
VOID_API void_input_mods_e void_surface_key_translation_mods(void_surface_t,
                                                                         void_input_mods_e);
VOID_API bool void_surface_key(void_surface_t, void_input_key_s);
VOID_API bool void_surface_key_is_binding(void_surface_t,
                                                   void_input_key_s,
                                                   void_binding_flags_e*);
VOID_API void void_surface_text(void_surface_t, const char*, uintptr_t);
VOID_API void void_surface_preedit(void_surface_t, const char*, uintptr_t);
VOID_API bool void_surface_mouse_captured(void_surface_t);
VOID_API bool void_surface_mouse_button(void_surface_t,
                                                 void_input_mouse_state_e,
                                                 void_input_mouse_button_e,
                                                 void_input_mods_e);
VOID_API void void_surface_mouse_pos(void_surface_t,
                                              double,
                                              double,
                                              void_input_mods_e);
VOID_API void void_surface_mouse_scroll(void_surface_t,
                                                 double,
                                                 double,
                                                 void_input_scroll_mods_t);
VOID_API void void_surface_mouse_pressure(void_surface_t, uint32_t, double);
VOID_API void void_surface_ime_point(void_surface_t, double*, double*, double*, double*);
VOID_API void void_surface_request_close(void_surface_t);
VOID_API void void_surface_split(void_surface_t, void_action_split_direction_e);
VOID_API void void_surface_split_focus(void_surface_t,
                                                void_action_goto_split_e);
VOID_API void void_surface_split_resize(void_surface_t,
                                                 void_action_resize_split_direction_e,
                                                 uint16_t);
VOID_API void void_surface_split_equalize(void_surface_t);
VOID_API bool void_surface_binding_action(void_surface_t, const char*, uintptr_t);
VOID_API void void_surface_complete_clipboard_request(void_surface_t,
                                                               const char*,
                                                               void*,
                                                               bool);
VOID_API bool void_surface_has_selection(void_surface_t);
VOID_API bool void_surface_read_selection(void_surface_t, void_text_s*);
VOID_API bool void_surface_read_text(void_surface_t,
                                              void_selection_s,
                                              void_text_s*);
VOID_API void void_surface_free_text(void_surface_t, void_text_s*);

#ifdef __APPLE__
VOID_API void void_surface_set_display_id(void_surface_t, uint32_t);
VOID_API void* void_surface_quicklook_font(void_surface_t);
VOID_API bool void_surface_quicklook_word(void_surface_t, void_text_s*);
#endif

VOID_API void_inspector_t void_surface_inspector(void_surface_t);
VOID_API void void_inspector_free(void_surface_t);
VOID_API void void_inspector_set_focus(void_inspector_t, bool);
VOID_API void void_inspector_set_content_scale(void_inspector_t, double, double);
VOID_API void void_inspector_set_size(void_inspector_t, uint32_t, uint32_t);
VOID_API void void_inspector_mouse_button(void_inspector_t,
                                                   void_input_mouse_state_e,
                                                   void_input_mouse_button_e,
                                                   void_input_mods_e);
VOID_API void void_inspector_mouse_pos(void_inspector_t, double, double);
VOID_API void void_inspector_mouse_scroll(void_inspector_t,
                                                   double,
                                                   double,
                                                   void_input_scroll_mods_t);
VOID_API void void_inspector_key(void_inspector_t,
                                          void_input_action_e,
                                          void_input_key_e,
                                          void_input_mods_e);
VOID_API void void_inspector_text(void_inspector_t, const char*);

#ifdef __APPLE__
VOID_API bool void_inspector_metal_init(void_inspector_t, void*);
VOID_API void void_inspector_metal_render(void_inspector_t, void*, void*);
VOID_API bool void_inspector_metal_shutdown(void_inspector_t);
#endif

// APIs I'd like to get rid of eventually but are still needed for now.
// Don't use these unless you know what you're doing.
VOID_API void void_set_window_background_blur(void_app_t, void*);

// Benchmark API, if available.
VOID_API bool void_benchmark_cli(const char*, const char*);

#ifdef __cplusplus
}
#endif

#endif /* VOID_H */
