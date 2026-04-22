#if defined(VOID_SIMD_VT_H_) == defined(HWY_TARGET_TOGGLE)
#ifdef VOID_SIMD_VT_H_
#undef VOID_SIMD_VT_H_
#else
#define VOID_SIMD_VT_H_
#endif

#include <hwy/highway.h>

HWY_BEFORE_NAMESPACE();
namespace void {
namespace HWY_NAMESPACE {

namespace hn = hwy::HWY_NAMESPACE;

}  // namespace HWY_NAMESPACE
}  // namespace void
HWY_AFTER_NAMESPACE();

#if HWY_ONCE

namespace void {

typedef void (*PrintFunc)(const char32_t* chars, size_t count);

}  // namespace void

#endif  // HWY_ONCE

#endif  // VOID_SIMD_VT_H_
