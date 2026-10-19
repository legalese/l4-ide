struct plot { enum tenure { OWNER, TENANT, LODGER } tenure; int area; };
enum tenure t = TENANT;               /* the tag and the enumerators escape into file scope in C */
struct plot2 { enum { A2, B2 } kind; }; /* an unnamed enum member is legal too */
int main(void) { struct plot p = { LODGER, 3 }; return p.tenure == t; }
