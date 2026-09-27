#ifndef MGREAD_OHOS_CXX_COMPAT
#define MGREAD_OHOS_CXX_COMPAT

#include <atomic>
#include <algorithm>
#include <iterator>
#include <memory>
#include <type_traits>
#include <__support/musl/xlocale.h>

// The OHOS libc++ xlocale compatibility header is supplied separately under
// __support/musl. Do not macro-alias these names: the alias changes the
// declaration itself and collides with the C library's abi-tagged symbols.

// The OHOS libc++ headers advertise atomic_ref but this SDK revision does not
// provide the class template. V8 uses only these integral operations.
#if !defined(__cpp_lib_atomic_ref)
namespace std {
template <typename T>
class atomic_ref {
 public:
  explicit atomic_ref(T& value) noexcept : value_(&value) {}

  bool compare_exchange_strong(
      T& expected, T desired, memory_order success, memory_order failure) const noexcept {
    return __atomic_compare_exchange_n(value_, &expected, desired, false,
                                       static_cast<int>(success), static_cast<int>(failure));
  }

  bool compare_exchange_strong(T& expected, T desired,
                               memory_order order) const noexcept {
    return compare_exchange_strong(expected, desired, order, order);
  }

  T load(memory_order order) const noexcept {
    return __atomic_load_n(value_, static_cast<int>(order));
  }

  T exchange(T desired, memory_order order) const noexcept {
    return __atomic_exchange_n(value_, desired, static_cast<int>(order));
  }

  T fetch_or(T bits, memory_order order) const noexcept {
    return __atomic_fetch_or(value_, bits, static_cast<int>(order));
  }

  T fetch_add(T increment, memory_order order) const noexcept {
    return __atomic_fetch_add(value_, increment, static_cast<int>(order));
  }

  void store(T value, memory_order order) const noexcept {
    __atomic_store_n(value_, value, static_cast<int>(order));
  }

 private:
  T* value_;
};
}  // namespace std
#endif

// This SDK exposes std::ranges but omits several C++20 range algorithms used
// by Node's bundled ada dependency. Keep the compatibility surface narrow and
// delegate to the iterator algorithms provided by the same libc++.
#if defined(MGREAD_OHOS_USE_LEGACY_LIBCXX)
namespace std::ranges {
template <typename Range, typename Predicate>
auto find_if(Range&& range, Predicate predicate) {
  return std::find_if(std::begin(range), std::end(range), predicate);
}

template <typename Range, typename Predicate>
auto find_if_not(Range&& range, Predicate predicate) {
  return std::find_if_not(std::begin(range), std::end(range), predicate);
}

template <typename Range, typename Predicate>
bool any_of(Range&& range, Predicate predicate) {
  return std::any_of(std::begin(range), std::end(range), predicate);
}

template <typename Range, typename Predicate>
bool all_of(Range&& range, Predicate predicate) {
  return std::all_of(std::begin(range), std::end(range), predicate);
}

template <typename Range, typename Value>
void replace(Range&& range, const Value& old_value, const Value& new_value) {
  std::replace(std::begin(range), std::end(range), old_value, new_value);
}

template <typename Range, typename Comparator>
void stable_sort(Range&& range, Comparator comparator) {
  std::stable_sort(std::begin(range), std::end(range), comparator);
}

template <typename Range, typename Value, typename Comparator = std::less<>>
auto lower_bound(Range&& range, const Value& value, Comparator comparator = {}) {
  return std::lower_bound(std::begin(range), std::end(range), value, comparator);
}

template <typename Range, typename Value, typename Comparator, typename Projection>
auto lower_bound(Range&& range, const Value& value, Comparator comparator, Projection projection) {
  return std::lower_bound(std::begin(range), std::end(range), value,
                          [&](const auto& element, const auto& projected_value) {
                            return comparator(projection(element), projected_value);
                          });
}

template <typename Range, typename Value, typename Projection>
auto lower_bound(Range&& range, const Value& value, std::less<> comparator, Projection projection) {
  return std::lower_bound(std::begin(range), std::end(range), value,
                          [&](const auto& element, const auto& projected_value) {
                            return comparator(projection(element), projected_value);
                          });
}

template <typename Range, typename Value, typename Comparator = std::less<>>
bool binary_search(Range&& range, const Value& value, Comparator comparator = {}) {
  return std::binary_search(std::begin(range), std::end(range), value, comparator);
}

template <typename Range, typename Value, typename Comparator, typename Projection>
bool binary_search(Range&& range, const Value& value, Comparator comparator, Projection projection) {
  return std::binary_search(std::begin(range), std::end(range), value,
                            [&](const auto& element, const auto& projected_value) {
                            return comparator(projection(element), projected_value);
                          });
}

template <typename Range, typename Value, typename Projection>
bool binary_search(Range&& range, const Value& value, std::less<> comparator, Projection projection) {
  return std::binary_search(std::begin(range), std::end(range), value,
                            [&](const auto& element, const auto& projected_value) {
                              return comparator(projection(element), projected_value);
                            });
}
}  // namespace std::ranges
#endif

#if defined(MGREAD_OHOS_USE_LEGACY_LIBCXX) && !defined(__cpp_lib_make_unique_for_overwrite)
namespace std {
template <typename T>
unique_ptr<T> make_unique_for_overwrite() {
  return unique_ptr<T>(new T);
}

template <typename T>
unique_ptr<T> make_unique_for_overwrite(size_t size) {
  using Element = remove_extent_t<T>;
  return unique_ptr<T>(new Element[size]);
}
}  // namespace std
#endif

#endif
