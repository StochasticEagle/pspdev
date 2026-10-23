unsigned int gcc16_reverse(unsigned int x) {
  return __builtin_allegrex_bitrev(x);
}
unsigned int gcc16_leading_ones(unsigned int x) {
  return __builtin_allegrex_clo(x);
}
