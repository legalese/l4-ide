-- A record whose field's type is a union written inline: no separately named type.
let Plot = { owner : Text, tenure : < Owner | Tenant | Lodger >, role : < Owner | Manager > }

let p
    : Plot
    = { owner = "Ann"
      , tenure = < Owner | Tenant | Lodger >.Tenant
      , role = < Owner | Manager >.Owner
      }

in  { tenure = merge { Owner = "owner", Tenant = "tenant", Lodger = "lodger" } p.tenure
    , role = merge { Owner = "role owner", Manager = "manager" } p.role
    }
