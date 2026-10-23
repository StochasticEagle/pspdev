#include <pspkernel.h>
#include <cstdlib>
#include <exception>
#include <typeinfo>
#include <vector>
#include <string>
PSP_MODULE_INFO("gcc16-cxx", PSP_MODULE_USER, 1, 0);
PSP_MAIN_THREAD_ATTR(THREAD_ATTR_USER);
struct Base { virtual ~Base() = default; virtual int value() const { return 1; } };
struct Derived final : Base { int value() const override { return 7; } };
struct Startup { Startup() : value(17) {} int value; };
static Startup startup;
int gcc16_lto_probe(int);
int main() {
  Derived d;
  Base *b = &d;
  std::vector<int> v = {1, 2, 3};
  std::string label = "psp";
  int value = startup.value + b->value() + v[0] + (int)label.size();
  try { throw 4; } catch (int x) { value += x; }
  if (typeid(*b) == typeid(Derived)) ++value;
  return value < 0 ? 1 : 0;
}
