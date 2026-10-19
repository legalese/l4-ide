struct Plot { enum { Owner, Tenant, Lodger } tenure; };
struct Role { enum { Owner, Manager } kind; };
decltype(Plot::tenure) t = Plot::Lodger;     // named by its place
int main() { Plot p { Plot::Owner }; p.tenure = t; return p.tenure == Plot::Lodger ? 0 : 1; }
