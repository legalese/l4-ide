struct Plot { enum Tenure { Owner, Tenant, Lodger } tenure; int area; };
struct Role { enum Kind { Owner, Manager } kind; };      // a second `Owner`, legal: class scope
struct Anon { enum { X, Y } kind; };                      // unnamed member enum
Plot::Tenure t = Plot::Tenant;                            // named from outside by qualification
int main() { Plot p { Plot::Owner, 3 }; Role r { Role::Owner }; return p.tenure == t && r.kind == Role::Owner; }
