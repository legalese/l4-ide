struct Plot { enum Tenure { Owner, Tenant } tenure; };
Tenure bad = Owner;   // expected error: not in scope outside the class
