/**
 * @file style.h
 *
 * Terminal cell style types.
 */

#ifndef VOID_VT_STYLE_H
#define VOID_VT_STYLE_H

#include <void/vt/color.h>
#include <void/vt/types.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** @defgroup style Style
 *
 * Terminal cell style attributes.
 *
 * A style describes the visual attributes of a terminal cell, including
 * foreground, background, and underline colors, as well as flags for
 * bold, italic, underline, and other text decorations.
 *
 * @{
 */

/**
 * Style identifier type.
 *
 * Used to look up the full style from a grid reference.
 * Obtain this from a cell via VOID_CELL_DATA_STYLE_ID.
 *
 * @ingroup style
 */
typedef uint16_t VoidStyleId;

/**
 * Style color tags.
 *
 * These values identify the type of color in a style color.
 * Use the tag to determine which field in the color value union to access.
 *
 * @ingroup style
 */
typedef enum VOID_ENUM_TYPED {
  VOID_STYLE_COLOR_NONE = 0,
  VOID_STYLE_COLOR_PALETTE = 1,
  VOID_STYLE_COLOR_RGB = 2,
  VOID_STYLE_COLOR_TAG_MAX_VALUE = VOID_ENUM_MAX_VALUE,
  } VoidStyleColorTag;

/**
 * Style color value union.
 *
 * Use the tag to determine which field is active.
 *
 * @ingroup style
 */
typedef union {
  VoidColorPaletteIndex palette;
  VoidColorRgb rgb;
  uint64_t _padding;
} VoidStyleColorValue;

/**
 * Style color (tagged union).
 *
 * A color used in a style attribute. Can be unset (none), a palette
 * index, or a direct RGB value.
 *
 * @ingroup style
 */
typedef struct {
  VoidStyleColorTag tag;
  VoidStyleColorValue value;
} VoidStyleColor;

/**
 * Terminal cell style.
 *
 * Describes the complete visual style for a terminal cell, including
 * foreground, background, and underline colors, as well as text
 * decoration flags. The underline field uses the same values as
 * VoidSgrUnderline.
 *
 * This is a sized struct. Use VOID_INIT_SIZED() to initialize it.
 *
 * @ingroup style
 */
typedef struct {
  size_t size;
  VoidStyleColor fg_color;
  VoidStyleColor bg_color;
  VoidStyleColor underline_color;
  bool bold;
  bool italic;
  bool faint;
  bool blink;
  bool inverse;
  bool invisible;
  bool strikethrough;
  bool overline;
  int underline; /**< One of VOID_SGR_UNDERLINE_* values */
} VoidStyle;

/**
 * Get the default style.
 *
 * Initializes the style to the default values (no colors, no flags).
 *
 * @param style Pointer to the style to initialize
 *
 * @ingroup style
 */
VOID_API void void_style_default(VoidStyle* style);

/**
 * Check if a style is the default style.
 *
 * Returns true if all colors are unset and all flags are off.
 *
 * @param style Pointer to the style to check
 * @return true if the style is the default style
 *
 * @ingroup style
 */
VOID_API bool void_style_is_default(const VoidStyle* style);

#ifdef __cplusplus
}
#endif

/** @} */

#endif /* VOID_VT_STYLE_H */
