struct Plot {
    enum Tenure { case owner, tenant, lodger }
    var tenure: Tenure
}
struct Role { enum Kind { case owner, manager }; var kind: Kind }
let t: Plot.Tenure = .tenant
let p = Plot(tenure: .owner)
print(p.tenure, t, Role(kind: .owner).kind)
