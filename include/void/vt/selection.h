/**
 * @file selection.h
 *
 * Selection range type for specifying a region of terminal content.
 */

#ifndef VOID_VT_SELECTION_H
#define VOID_VT_SELECTION_H

#include <stdbool.h>
#include <stddef.h>
#include <void/vt/grid_ref.h>

#ifdef __cplusplus
extern "C" {
#endif

/** @defgroup selection Selection
 *
 * A selection range defined by two grid references that identifies a
 * contiguous or rectangular region of terminal content.
 *
 * @{
 */

/**
 * A selection range defined by two grid references.
 *
 * This is a sized struct. Use VOID_INIT_SIZED() to initialize it.
 *
 * @ingroup selection
 */
typedef struct {
  /** Size of this struct in bytes. Must be set to sizeof(VoidSelection). */
  size_t size;

  /** Start of the selection range (inclusive). */
  VoidGridRef start;

  /** End of the selection range (inclusive). */
  VoidGridRef end;

  /** Whether the selection is rectangular (block) rather than linear. */
  bool rectangle;
} VoidSelection;

/** @} */

#ifdef __cplusplus
}
#endif

#endif /* VOID_VT_SELECTION_H */
