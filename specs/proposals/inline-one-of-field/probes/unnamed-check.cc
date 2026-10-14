#include <cstdio>
struct Plot { const char* owner; enum { Owner, Tenant, Lodger } tenure; };
int main() {
  Plot p{"Ann", Plot::Tenant};
  decltype(Plot::tenure) t = p.tenure;          // the unnamed enum, named by its place
  std::printf("%d\n", t == Plot::Tenant);
}
