#include <type_traits>
#include <cstdint>
static_assert(sizeof(void*) == 4, "PSP pointer width");
static_assert(sizeof(std::uint32_t) == 4 && std::is_unsigned_v<std::uint32_t>, "PSP unsigned 32-bit ABI");
constexpr unsigned int gcc16_constexpr(unsigned int x) { return x * x; }
static_assert(gcc16_constexpr(7) == 49);
int gcc16_cxx_probe() { return (int)gcc16_constexpr(9); }
