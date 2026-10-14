interface Plot { owner: string; tenure: "Owner" | "Tenant" | "Lodger" }
type Tenure = Plot["tenure"];               // indexed access names the inline union
interface Role { kind: "Owner" | "Manager" }  // a second "Owner": literal types are structural
const t: Tenure = "Lodger";
const p: Plot = { owner: "x", tenure: t };
const r: Role = { kind: "Owner" };
const bad: Plot = { owner: "x", tenure: "Manager" };
