#ifndef MGREAD_OHOS_CXX_COMPAT
#define MGREAD_OHOS_CXX_COMPAT

#include <stdlib.h>

// The OHOS C library has no locale-specific variants, while libc++ uses
// these names when parsing numbers through its locale helpers.
#if !defined(strtoll_l)
#define strtoll_l(value, end, base, locale) strtoll(value, end, base)
#endif
#if !defined(strtoull_l)
#define strtoull_l(value, end, base, locale) strtoull(value, end, base)
#endif

#endif
