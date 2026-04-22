/**
 * @file build_info.h
 *
 * Build info - query compile-time build configuration of libvoid-vt.
 */

#ifndef VOID_VT_BUILD_INFO_H
#define VOID_VT_BUILD_INFO_H

/** @defgroup build_info Build Info
 *
 * Query compile-time build configuration of libvoid-vt.
 *
 * These values reflect the options the library was built with and are
 * constant for the lifetime of the process.
 *
 * ## Basic Usage
 *
 * Use void_build_info() to query individual build options:
 *
 * @snippet c-vt-build-info/src/main.c build-info-query
 *
 * @{
 */

#include <stddef.h>
#include <stdbool.h>

#include <void/vt/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Build optimization mode.
 */
typedef enum VOID_ENUM_TYPED {
  VOID_OPTIMIZE_DEBUG = 0,
  VOID_OPTIMIZE_RELEASE_SAFE = 1,
  VOID_OPTIMIZE_RELEASE_SMALL = 2,
  VOID_OPTIMIZE_RELEASE_FAST = 3,
  VOID_OPTIMIZE_MODE_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidOptimizeMode;

/**
 * Build info data types that can be queried.
 *
 * Each variant documents the expected output pointer type.
 */
typedef enum VOID_ENUM_TYPED {
  /** Invalid data type. Never results in any data extraction. */
  VOID_BUILD_INFO_INVALID = 0,

  /**
   * Whether SIMD-accelerated code paths are enabled.
   *
   * Output type: bool *
   */
  VOID_BUILD_INFO_SIMD = 1,

  /**
   * Whether Kitty graphics protocol support is available.
   *
   * Output type: bool *
   */
  VOID_BUILD_INFO_KITTY_GRAPHICS = 2,

  /**
   * Whether tmux control mode support is available.
   *
   * Output type: bool *
   */
  VOID_BUILD_INFO_TMUX_CONTROL_MODE = 3,

  /**
   * The optimization mode the library was built with.
   *
   * Output type: VoidOptimizeMode *
   */
  VOID_BUILD_INFO_OPTIMIZE = 4,

  /**
   * The full version string (e.g. "1.2.3" or "1.2.3-dev+abcdef").
   *
   * Output type: VoidString *
   */
  VOID_BUILD_INFO_VERSION_STRING = 5,

  /**
   * The major version number.
   *
   * Output type: size_t *
   */
  VOID_BUILD_INFO_VERSION_MAJOR = 6,

  /**
   * The minor version number.
   *
   * Output type: size_t *
   */
  VOID_BUILD_INFO_VERSION_MINOR = 7,

  /**
   * The patch version number.
   *
   * Output type: size_t *
   */
  VOID_BUILD_INFO_VERSION_PATCH = 8,

  /**
   * The pre metadata string (e.g. "alpha", "beta", "dev"). Has zero length if
   * no pre metadata is present.
   *
   * Output type: VoidString *
   */
  VOID_BUILD_INFO_VERSION_PRE = 9,

  /**
   * The build metadata string (e.g. commit hash). Has zero length if
   * no build metadata is present.
   *
   * Output type: VoidString *
   */
  VOID_BUILD_INFO_VERSION_BUILD = 10,
  VOID_BUILD_INFO_MAX_VALUE = VOID_ENUM_MAX_VALUE,
} VoidBuildInfo;

/**
 * Query a compile-time build configuration value.
 *
 * The caller must pass a pointer to the correct output type for the
 * requested data (see VoidBuildInfo variants for types).
 *
 * @param data The build info field to query
 * @param out Pointer to store the result (type depends on data parameter)
 * @return VOID_SUCCESS on success, VOID_INVALID_VALUE if the
 *         data type is invalid
 *
 * @ingroup build_info
 */
VOID_API VoidResult void_build_info(VoidBuildInfo data, void *out);

#ifdef __cplusplus
}
#endif

/** @} */

#endif /* VOID_VT_BUILD_INFO_H */
