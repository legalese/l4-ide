-- Unions are structural: two spellings of the same alternatives are one type.
let T1 = < Owner | Tenant | Lodger >
let T2 = < Lodger | Owner | Tenant >
let f = \(x : T1) -> merge { Owner = 1, Tenant = 2, Lodger = 3 } x
in  f T2.Lodger
