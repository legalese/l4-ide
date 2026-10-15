struct Plot { enum { Owner, Tenant, Lodger } tenure; };
struct Role { enum { Owner, Manager } kind; };
decltype(Plot::tenure) t = Role::Owner;      // a different unnamed enum: must be rejected
