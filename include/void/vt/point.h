/**
 * @file point.h
 *
 * Terminal point types for referencing locations in the terminal grid.
 */

#ifndef VOID_VT_POINT_H
#define VOID_VT_POINT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** @defgroup point Point
 *
 * Types for referencing x/y positions in the terminal grid under
 * different coordinate systems (active area, viewport, full screen,
 * scrollback history).
 *
 * @{
 */

/**
 * A coordinate in the terminal grid.
 *
 * @ingroup point
 */
typedef struct {
  /** Column (0-indexed). */
  uint16_t x;

  /** Row (0-indexed). May exceed page size for screen/history tags. */
  uint32_t y;
} VoidPointCoordinate;

/**
 * Point reference tag.
 *
 * Determines which coordinate system a point uses.
 *
 * @ingroup point
 */
typedef enum VOID_ENUM_TYPED {
  /** Active area where the cursor can move. */
  VOID_POINT_TAG_ACTIVE = 0,

  /** Visible viewport (changes when scrolled). */
  VOID_POINT_TAG_VIEWPORT = 1,

  /** Full screen including scrollback. */
  VOID_POINT_TAG_SCREEN = 2,

  /** Scrollback history only (before active area). */
  VOID_POINT_TAG_HISTORY = 3,
  VOID_POINT_TAG_MAX_VALUE = VOID_ENUM_MAX_VALUE,
  } VoidPointTag;

/**
 * Point value union.
 *
 * @ingroup point
 */
typedef union {
  /** Coordinate (used for all tag variants). */
  VoidPointCoordinate coordinate;

  /** Padding for ABI compatibility. Do not use. */
  uint64_t _padding[2];
} VoidPointValue;

/**
 * Tagged union for a point in the terminal grid.
 *
 * @ingroup point
 */
typedef struct {
  VoidPointTag tag;
  VoidPointValue value;
} VoidPoint;

/** @} */

#ifdef __cplusplus
}
#endif

#endif /* VOID_VT_POINT_H */
