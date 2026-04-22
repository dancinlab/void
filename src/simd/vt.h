#if defined(VOID_SIMD_VT_H_) == defined(HWY_TARGET_TOGGLE)
#ifdef VOID_SIMD_VT_H_
#undef VOID_SIMD_VT_H_
#else
#define VOID_SIMD_VT_H_
#endif

#include <hwy/highway.h>

HWY_BEFORE_NAMESPACE();
namespace vd {
namespace HWY_NAMESPACE {

namespace hn = hwy::HWY_NAMESPACE;

}  // namespace HWY_NAMESPACE
}  // namespace vd
HWY_AFTER_NAMESPACE();

#if HWY_ONCE

namespace vd {

typedef void (*PrintFunc)(const char32_t* chars, size_t count);

}  // namespace vd

#endif  // HWY_ONCE

#endif  // VOID_SIMD_VT_H_
