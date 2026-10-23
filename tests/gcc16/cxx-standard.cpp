#include <type_traits>
#include <cstdint>
static_assert(sizeof(void*) == 4, "PSP pointer width");
static_assert(std::is_same_v<std::uint32_t, unsigned int>);
constexpr unsigned int gcc16_constexpr(unsigned int x) { return x * x; }
static_assert(gcc16_constexpr(7) == 49);
int gcc16_cxx_probe() { return (int)gcc16_constexpr(9); }
