// OpenHarmony libc++ xlocale compatibility for Node's cross build.
#ifndef _LIBCPP_SUPPORT_MUSL_XLOCALE_H
#define _LIBCPP_SUPPORT_MUSL_XLOCALE_H

#include <cstdlib>
#include <cwchar>

#ifdef __cplusplus
extern "C" {
#endif

inline long long strtoll_l(const char* value, char** end, int base, locale_t) {
  return ::strtoll(value, end, base);
}

inline unsigned long long strtoull_l(const char* value, char** end, int base, locale_t) {
  return ::strtoull(value, end, base);
}

inline long long wcstoll_l(const wchar_t* value, wchar_t** end, int base, locale_t) {
  return ::wcstoll(value, end, base);
}

inline unsigned long long wcstoull_l(const wchar_t* value, wchar_t** end, int base, locale_t) {
  return ::wcstoull(value, end, base);
}

inline long double wcstold_l(const wchar_t* value, wchar_t** end, locale_t) {
  return ::wcstold(value, end);
}

#ifdef __cplusplus
}
#endif

#endif
