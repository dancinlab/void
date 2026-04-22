#include <void/vt.h>
#include <stdio.h>
int main(void) {
    bool simd = false;
    VoidResult r = void_build_info(VOID_BUILD_INFO_SIMD, &simd);
    if (r != VOID_SUCCESS) return 1;
    printf("SIMD: %s\n", simd ? "yes" : "no");
    return 0;
}
