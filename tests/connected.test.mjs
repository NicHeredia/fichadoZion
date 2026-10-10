import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import vm from "node:vm";
import { randomUUID } from "node:crypto";
const require = createRequire(import.meta.url);
const ts = require("typescript");
const jsx = require("react/jsx-runtime");
const root = fileURLToPath(new URL("../", import.meta.url));
const results = [];
const test = async (name, fn) => { await fn(); results.push(name); };
const employee = { id: "employee-a", profileId: "user-a", name: "Usuario Real", initials: "UR", user: "A-1", employeeNumber: "A-1", appRole: "admin", role: "Administrador", status: "Activo" };
const record = { id: "session-a", employeeId: employee.id, employee: employee.name, initials: "UR", isoDate: "2026-10-08", date: "08/10/2026", entry: "18:00", exit: "21:00", minutes: 180, status: "Automático", reason: "Trabajo real", institution: "Institución real" };
const base = { profile: { id: "user-a", name: employee.name, role: "admin", employeeId: employee.id, employeeNumber: "A-1", active: true }, records: [record], employees: [employee], settings: { startsAt: "08:00", endsAt: "17:00", weekdays: [1,2,3,4,5], institutions: ["Institución real"], holidays: [] }, institutions: [{ id: "place-a", name: "Institución real" }], events: [], closures: {}, audit: [], refreshing: false, syncError: "" };
function fixture({ data = base, states = [], rpc = async () => [], location = "/", auth = {} } = {}) {
  const calls = [], setters = [], cache = new Map(); let stateIndex = 0;
  const fn = tag => Object.assign(() => null, { tag });
  const ui = Object.fromEntries(["Button","Card","Input","Select","PageTitle","Badge"].map(name => [name,fn(name)]));
  const remote = { ...data, manualSession: async input => calls.push(["manualSession",input]), requestCorrection: async input => calls.push(["requestCorrection",input]), resolveCorrection: async (...args) => calls.push(["resolveCorrection",...args]), manualPunch: async input => calls.push(["manualPunch",input]), createCompensation: async input => calls.push(["compensation",input]), changeCompensation: async (...args) => calls.push(["compensationStatus",...args]), punch: async input => calls.push(["punch",input]), review: async (...args) => calls.push(["review",...args]), close: async month => calls.push(["close",month]), reopen: async (...args) => calls.push(["reopen",...args]), saveSettings: async value => calls.push(["settings",value]), saveEmployee: async value => calls.push(["employee",value]), refresh: async () => calls.push(["refresh"]), logout: async () => calls.push(["logout"]) };
  const forbid = () => { throw new Error("Se intentó usar almacenamiento de la demo en modo conectado"); };
  const icons = new Proxy({}, { get: (_target,name) => fn(String(name)) });
  const react = {
    useState(initial) { const index=stateIndex++; return [index in states ? states[index] : typeof initial === "function" ? initial() : initial, next => setters.push([index,next])]; },
    useRef: initial => ({ current: initial }), useEffect() {},
    useSyncExternalStore(subscribe,getSnapshot) { subscribe(() => {}); return getSnapshot(); },
  };
  const context = vm.createContext({ console, Date, Intl, crypto:{randomUUID}, window:{addEventListener(){},removeEventListener(){},setInterval(){},clearInterval(){}}, document:{body:{style:{}}}, setTimeout, URL, FormData: class { constructor(values) { this.values = values; } get(key) { return this.values[key] ?? null; } } });
  function load(name) {
    if (cache.has(name)) return cache.get(name);
    const source=readFileSync(root+name,"utf8");
    const code=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020,jsx:ts.JsxEmit.ReactJSX}}).outputText;
    const module={exports:{}}; cache.set(name,module.exports);
    const mockRequire = spec => {
      if (spec==="react") return react;
      if (spec==="react/jsx-runtime") return jsx;
      if (spec==="lucide-react" || spec==="recharts") return icons;
      if (spec==="react-router") return { NavLink:fn("NavLink"), Link:fn("Link"), Navigate:fn("Navigate"), Outlet:fn("Outlet"), RouterProvider:fn("Router"), useLocation:()=>({pathname:location}),useNavigate:()=>to=>calls.push(["navigate",to]),useSearchParams:()=>[new URLSearchParams(),()=>{}] };
      if (spec.endsWith("/DataContext")) return { useRemoteData:()=>remote, DataContext:{Provider:fn("Provider")} };
      if (spec.endsWith("/useAppRecords")) return { useAppRecords:()=>data.records };
      if (spec.endsWith("/records")) return { getRecords:forbid, subscribeRecords:forbid, getClosures:forbid, getStorageError:forbid, registerPunch:forbid, updateRecord:forbid, closeMonth:forbid, reopenMonth:forbid, exportRecords:()=>{}, localDate:()=>"2026-10-08",recordMonth:r=>r.isoDate.slice(0,7),TIME_ZONE:"America/Argentina/Buenos_Aires" };
      if (spec.endsWith("/settings")) return { getSettings:forbid, saveSettings:forbid, validateSettings(){},defaultSettings:base.settings };
      if (spec.endsWith("/demo")) return load("src/lib/demo.ts");
      if (spec.endsWith("/work-details")) return load("src/lib/work-details.ts");
      if (spec.endsWith("/OvertimeDetail")) return load("src/components/OvertimeDetail.tsx");
      if (spec.endsWith("/compensations")) return load("src/lib/compensations.ts");
      if (spec.endsWith("/supabase")) return { isDemoMode:false,supabase:{auth},configurationError:null };
      if (spec.endsWith("/AuthForm")) return { default: fn("AuthForm") };
      if (spec.endsWith("/zion-logo")) return load("src/assets/zion-logo.ts");
      if (spec.endsWith("/ui")) return ui;
      if (spec.endsWith("/StatusBadge")) return { StatusBadge:fn("StatusBadge") };
      if (spec==="@tanstack/react-query") return { useQuery:()=>({data,isFetching:false,isError:false,refetch:async()=>calls.push(["refresh"])}),useQueryClient:()=>({clear(){}}) };
      if (spec.endsWith("/remote")) return {callRpc:async (...args)=>{calls.push(["rpc",...args]);return rpc(...args);},loadRemoteData:async()=>data};
      if (spec==="./routes") return {router:{}};
      throw new Error("Import no simulado: "+spec);
    };
    vm.runInContext("(function(require,module,exports){"+code+"\n})",context)(mockRequire,module,module.exports);
    return module.exports;
  }
  return {load,remote,ui,calls,setters};
}
function nodes(tree) {
  if (!tree || typeof tree!=="object") return [];
  if (Array.isArray(tree)) return tree.flatMap(nodes);
  return [tree,...nodes(tree.props?.children)];
}
const byTag = (tree,tag) => nodes(tree).filter(n=>n.type?.tag===tag);
await test("El fichaje conectado llama al servidor y nunca guarda datos de demostración",async()=>{
  const f=fixture({states:[false,new Date("2026-10-08T21:00:00Z"),"Entrada",new Date(),"Institución real","","Trabajo real","","",""]});
  const tree=f.load("src/pages/Register.tsx").default();
  const form=nodes(tree).find(n=>n.type==="form");
  assert.ok(form); await form.props.onSubmit({preventDefault(){}});
  assert.equal(f.calls[0][0],"punch"); assert.equal(f.calls[0][1].institution,"Institución real");
  assert.ok(f.setters.some(([index,value])=>index===9 && String(value).includes("hora del servidor")));
});
await test("El dashboard usa el directorio real y no introduce empleados ficticios",()=>{
  const f=fixture(); const tree=f.load("src/pages/Dashboard.tsx").default();
  assert.equal(byTag(tree,"PageTitle")[0].props.title,"Hola, Usuario Real");
  assert.ok(!JSON.stringify(tree).includes("Empleado ficticio"));
  assert.ok(!JSON.stringify(tree).includes("Mariana"));
});
await test("El empleado no ve módulos administrativos y una ruta directa se redirige",()=>{
  const data={...base,profile:{...base.profile,role:"employee"}};
  const f=fixture({data,location:"/empleados"});
  const tree=f.load("src/components/AppShell.tsx").AppShell();
  assert.deepEqual(byTag(tree,"NavLink").map(n=>n.props.to),["/","/registrar","/historial","/solicitudes","/reportes","/compensaciones"]);
  assert.equal(byTag(tree,"Navigate")[0].props.to,"/");
  assert.ok(nodes(tree).some(n=>n.type==="button" && n.props.children==="Cerrar sesión"));
});
await test("El administrador conserva los módulos completos",()=>{
  const f=fixture(); const tree=f.load("src/components/AppShell.tsx").AppShell();
  for (const route of ["/empleados","/revisiones","/cierre","/configuracion","/auditoria"]) assert.ok(byTag(tree,"NavLink").some(n=>n.props.to===route));
});
await test("Los reportes distinguen empleados con el mismo nombre por su ID",()=>{
  const other={...employee,id:"employee-b",employeeNumber:"B-1"};
  const data={...base,employees:[employee,other],records:[record,{...record,id:"session-b",employeeId:other.id,minutes:600}]};
  const f=fixture({data}); const tree=f.load("src/pages/Reports.tsx").default();
  assert.equal(byTag(tree,"Select")[0].props.value,employee.id);
  const body=nodes(tree).find(n=>n.type==="tbody");
  assert.equal(nodes(body).filter(n=>n.type==="tr").length,1);
});
await test("Revisiones, configuración y cierre usan operaciones remotas",async()=>{
  const review=fixture({data:{...base,records:[{...record,status:"Pendiente"}]}});
  const tree=review.load("src/pages/Reviews.tsx").default();
  await byTag(tree,"Button").find(n=>n.props.variant==="danger").props.onClick();
  // Los handlers no bloquean React; esperamos que finalice la promesa lanzada.
  await Promise.resolve(); assert.equal(review.calls[0][0],"review");
  const settings=fixture(); await nodes(settings.load("src/pages/Settings.tsx").default()).find(n=>n.type==="form").props.onSubmit({preventDefault(){}});
  assert.equal(settings.calls[0][0],"settings");
  const closure=fixture(); nodes(closure.load("src/pages/Closure.tsx").default()).find(n=>n.type?.tag==="Button" && n.props.children?.includes?.("Confirmar cierre mensual"))?.props.onClick();
  await Promise.resolve(); assert.equal(closure.calls[0][0],"close");
});
await test("El hook conectado no lee ni se suscribe al almacenamiento local",()=>{
  const f=fixture(); assert.equal(f.load("src/app/useAppRecords.ts").useAppRecords(),base.records);
});
await test("Un reintento de fichaje conserva el identificador y un fichaje nuevo usa otro",async()=>{
  let first=true;
  const f=fixture({states:[{user:{id:"user-a"}},false,false,""],rpc:async()=>{if(first){first=false;throw new Error("Red interrumpida");}return [];}});
  const tree=f.load("src/app/ConnectedApp.tsx").default();
  const workspace=nodes(tree).find(n=>n.type?.name==="Workspace");
  const provider=workspace.type(workspace.props);
  const api=provider.props.value;
  const input={kind:"Entrada",institution:"Institución real",reason:"Trabajo",notes:""};
  await assert.rejects(()=>api.punch(input),/Red interrumpida/);
  await api.punch(input); await api.punch(input);
  const requests=f.calls.filter(c=>c[0]==="rpc").map(c=>c[2].p_request_id);
  assert.equal(requests[0],requests[1]); assert.notEqual(requests[1],requests[2]);
});
await test("El registro crea una cuenta con nombre y abre la sesión sin pasos adicionales", async () => {
  let payload, opened;
  const session = { user: { id: "new-user" } };
  const f = fixture({ states: ["signup", false, "", ""], auth: { signUp: async input => { payload = input; return { data: { session, user: session.user }, error: null }; } } });
  const tree = f.load("src/components/AuthForm.tsx").default({ onAuthenticated: next => { opened = next; } });
  const form = nodes(tree).find(n => n.type === "form");
  await form.props.onSubmit({ preventDefault() {}, currentTarget: { name: "  Ana Pérez  ", email: " ana@example.com ", password: "temporal123" } });
  assert.equal(payload.email, "ana@example.com");
  assert.equal(payload.options.data.display_name, "Ana Pérez");
  assert.deepEqual(Object.keys(payload.options.data), ["display_name"]);
  assert.equal(opened, session);
  assert.equal(nodes(tree).filter(n => n.type === "input" && n.props.type === "password").length, 1);
});
await test("El registro no anuncia ingreso inmediato si Supabase requiere correo confirmado", async () => {
  let opened = false;
  const f = fixture({ states: ["signup", false, "", ""], auth: { signUp: async () => ({ data: { session: null, user: { id: "new-user", identities: [{}] } }, error: null }) } });
  const tree = f.load("src/components/AuthForm.tsx").default({ onAuthenticated: () => { opened = true; } });
  await nodes(tree).find(n => n.type === "form").props.onSubmit({ preventDefault() {}, currentTarget: { name: "Ana", email: "ana@example.com", password: "temporal123" } });
  assert.equal(opened, false);
  assert.ok(f.setters.some(([index, value]) => index === 3 && value.includes("Revisá tu correo")));
});
await test("Un registro rechazado muestra el error y permite reintentar", async () => {
  let attempts = 0;
  const f = fixture({ states: ["signup", false, "", ""], auth: { signUp: async () => { attempts++; return { data: { session: null, user: null }, error: { code: "signup_disabled" } }; } } });
  const tree = f.load("src/components/AuthForm.tsx").default({ onAuthenticated: () => assert.fail("No debe abrir la sesión") });
  const event = { preventDefault() {}, currentTarget: { name: "Ana", email: "ana@example.com", password: "temporal123" } };
  const submit = nodes(tree).find(n => n.type === "form").props.onSubmit;
  await submit(event); await submit(event);
  assert.equal(attempts, 2);
  assert.ok(f.setters.some(([index, value]) => index === 2 && value.includes("registro está deshabilitado")));
});
await test("Enviar dos veces el registro mientras espera no crea dos solicitudes", async () => {
  let resolve, attempts = 0;
  const response = new Promise(done => { resolve = done; });
  const f = fixture({ states: ["signup", false, "", ""], auth: { signUp: () => { attempts++; return response; } } });
  const tree = f.load("src/components/AuthForm.tsx").default({ onAuthenticated() {} });
  const event = { preventDefault() {}, currentTarget: { name: "Ana", email: "ana@example.com", password: "temporal123" } };
  const submit = nodes(tree).find(n => n.type === "form").props.onSubmit;
  const first = submit(event); await submit(event);
  assert.equal(attempts, 1);
  resolve({ data: { session: { user: { id: "new-user" } } }, error: null });
  await first;
});
await test("Una cuenta ya existente recibe un mensaje para iniciar sesión", async () => {
  const f = fixture({ states: ["signup", false, "", ""], auth: { signUp: async () => ({ data: { session: null, user: { identities: [] } }, error: null }) } });
  const tree = f.load("src/components/AuthForm.tsx").default({ onAuthenticated: () => assert.fail("No debe abrir una sesión") });
  await nodes(tree).find(n => n.type === "form").props.onSubmit({ preventDefault() {}, currentTarget: { name: "Ana", email: "ana@example.com", password: "temporal123" } });
  assert.ok(f.setters.some(([index, value]) => index === 2 && value.includes("ya tiene una cuenta")));
});
await test("Cambiar el selector de rol guarda al administrador sin abrir otro formulario", async () => {
  const other = { ...employee, id: "employee-b", profileId: "user-b", name: "Ana Pérez", appRole: "employee", role: "Empleado" };
  const f = fixture({ data: { ...base, employees: [employee, other] } });
  const tree = f.load("src/pages/Employees.tsx").default();
  const selector = byTag(tree, "Select").find(n => n.props["aria-label"] === "Rol de Ana Pérez");
  assert.equal(selector.props.disabled, false);
  selector.props.onChange({ target: { value: "admin" } });
  await Promise.resolve();
  assert.equal(f.calls[0][0], "employee");
  assert.equal(f.calls[0][1].id, other.id);
  assert.equal(f.calls[0][1].appRole, "admin");
  assert.equal(byTag(tree, "Select").find(n => n.props["aria-label"] === "Rol de Usuario Real").props.disabled, true);
});

const compensationData = { balances: [{ employeeId: employee.id, earned:600,reserved:120,used:180,available:300 }],
  compensations:[{id:"rest-a",employeeId:employee.id,minutes:120,restDate:"2026-10-08",reason:"Descanso programado",status:"scheduled",cancellationReason:null,createdAt:"2026-10-08",updatedAt:"2026-10-08"}] };
await test("El administrador programa un descanso por horas y minutos",async()=>{
  const f=fixture({data:{...base,compensationData},states:[employee.id,"2:30","2026-10-08","Compensación","scheduled",null,"",false,"",""]});
  const tree=f.load("src/pages/Compensations.tsx").default();
  await nodes(tree).find(n=>n.type==="form").props.onSubmit({preventDefault(){}});
  assert.deepEqual(JSON.parse(JSON.stringify(f.calls[0])),["compensation",{employeeId:employee.id,minutes:150,restDate:"2026-10-08",reason:"Compensación",status:"scheduled"}]);
});
await test("El formulario rechaza un descuento que excede el saldo",async()=>{
  const f=fixture({data:{...base,compensationData},states:[employee.id,"5:01","2026-10-08","Exceso","scheduled",null,"",false,"",""]});
  await nodes(f.load("src/pages/Compensations.tsx").default()).find(n=>n.type==="form").props.onSubmit({preventDefault(){}});
  assert.equal(f.calls.length,0);
  assert.ok(f.setters.some(([,value])=>String(value).includes("saldo disponible")));
});
await test("El empleado consulta el saldo sin formularios ni acciones administrativas",()=>{
  const f=fixture({data:{...base,profile:{...base.profile,role:"employee"},compensationData}});
  const tree=f.load("src/pages/Compensations.tsx").default();
  assert.equal(nodes(tree).filter(n=>n.type==="form").length,0);
  assert.equal(byTag(tree,"Select")[0].props.disabled,true);
  assert.ok(!JSON.stringify(tree).includes("Confirmar realizado"));
});
await test("Una migración pendiente no habilita operaciones de compensaciones",()=>{
  const f=fixture(); const tree=f.load("src/pages/Compensations.tsx").default();
  assert.equal(nodes(tree).filter(n=>n.type==="form").length,0);
  assert.ok(JSON.stringify(tree).includes("todavía no está habilitado"));
});
await test("El reporte separa descansos y saldo de las horas trabajadas",()=>{
  const f=fixture({data:{...base,compensationData}}); const tree=f.load("src/pages/Reports.tsx").default();
  assert.ok(JSON.stringify(tree).includes("Saldo disponible acumulado"));
  const rows=nodes(tree).filter(n=>n.type==="tbody");
  assert.equal(rows.length,2);
});
await test("La solicitud de descanso conserva el ID al reintentar",async()=>{
  let first=true;
  const f=fixture({states:[{user:{id:"user-a"}},false,false,""],rpc:async()=>{if(first){first=false;throw new Error("Red interrumpida");}return [];}});
  const tree=f.load("src/app/ConnectedApp.tsx").default();
  const workspace=nodes(tree).find(n=>n.type?.name==="Workspace");
  const api=workspace.type(workspace.props).props.value;
  const input={employeeId:employee.id,minutes:120,restDate:"2026-10-08",reason:"Descanso",status:"scheduled"};
  await assert.rejects(()=>api.createCompensation(input),/Red interrumpida/);
  await api.createCompensation(input); await api.createCompensation(input);
  const requests=f.calls.filter(c=>c[0]==="rpc").map(c=>c[2].p_id);
  assert.equal(requests[0],requests[1]); assert.notEqual(requests[1],requests[2]);
});
await test("El administrador completa la jornada pendiente con fecha y hora manual",async()=>{
  const data={...base,manualPunchAvailable:true,records:[{...record,exit:undefined,status:"Pendiente",minutes:0}]};
  const f=fixture({data,states:[employee.id,"Salida","place-a","2026-10-08","20:00","Olvido verificado","","",false,"",""]});
  const tree=f.load("src/pages/ManualPunch.tsx").default();
  await nodes(tree).find(n=>n.type==="form").props.onSubmit({preventDefault(){}});
  assert.deepEqual(JSON.parse(JSON.stringify(f.calls[0])),["manualPunch",{employeeId:employee.id,kind:"Salida",institutionId:"place-a",date:"2026-10-08",time:"20:00",reason:"Olvido verificado",notes:"",targetId:record.id}]);
});
await test("El empleado no ve ni puede abrir el formulario de carga manual",()=>{
  const data={...base,manualPunchAvailable:true,profile:{...base.profile,role:"employee"}};
  const f=fixture({data,location:"/fichaje-manual"});
  assert.equal(nodes(f.load("src/pages/ManualPunch.tsx").default()).filter(n=>n.type==="form").length,0);
  const shell=f.load("src/components/AppShell.tsx").AppShell();
  assert.ok(!byTag(shell,"NavLink").some(n=>n.props.to==="/fichaje-manual"));
  assert.equal(byTag(shell,"Navigate")[0].props.to,"/");
});
await test("Dos jornadas ambiguas exigen seleccionar cuál completar",async()=>{
  const pending={...record,exit:undefined,status:"Pendiente",minutes:0};
  const data={...base,manualPunchAvailable:true,records:[pending,{...pending,id:"other-session"}]};
  const f=fixture({data,states:[employee.id,"Salida","place-a","2026-10-08","20:00","Olvido verificado","","",false,"",""]});
  await nodes(f.load("src/pages/ManualPunch.tsx").default()).find(n=>n.type==="form").props.onSubmit({preventDefault(){}});
  assert.equal(f.calls.length,0);
  assert.ok(f.setters.some(([,value])=>String(value).includes("Seleccioná la jornada")));
});
await test("Un reintento de carga manual conserva la solicitud original",async()=>{
  let first=true;
  const f=fixture({states:[{user:{id:"user-a"}},false,false,""],rpc:async()=>{if(first){first=false;throw new Error("Red interrumpida");}return [];}});
  const tree=f.load("src/app/ConnectedApp.tsx").default();
  const workspace=nodes(tree).find(n=>n.type?.name==="Workspace");
  const api=workspace.type(workspace.props).props.value;
  const input={employeeId:employee.id,kind:"Salida",institutionId:"place-a",date:"2026-10-08",time:"20:00",reason:"Olvido",notes:"",targetId:record.id};
  await assert.rejects(()=>api.manualPunch(input),/Red interrumpida/);
  await api.manualPunch(input); await api.manualPunch(input);
  const ids=f.calls.filter(c=>c[0]==="rpc").map(c=>c[2].p_request_id);
  assert.equal(ids[0],ids[1]); assert.notEqual(ids[1],ids[2]);
});
await test("Una entrada abierta precarga el lugar de la salida", () => {
  const f=fixture({data:{...base,records:[{...record,isoDate:new Intl.DateTimeFormat("en-CA",{timeZone:"America/Argentina/Buenos_Aires",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date()),entry:"07:45",exit:undefined,status:"Pendiente"}]}});
  // El reloj inicial usa la fecha actual; localDate del fixture usa 08/10.
  f.remote.records[0].isoDate="2026-10-08";
  const tree=f.load("src/pages/Register.tsx").default();
  assert.ok(JSON.stringify(tree).includes("Tenés una entrada abierta"));
  byTag(tree,"Button").find(n=>n.props.children==="Registrar salida").props.onClick();
  assert.ok(f.setters.some(([index,value])=>index===4 && value==="Institución real"));
});
await test("La carga completa guarda entrada y salida en una sola llamada",async()=>{
  const f=fixture({data:{...base,manualPunchAvailable:true,improvementsAvailable:true},states:[employee.id,"Entrada","place-a","2026-10-08","07:45","Olvido verificado","","",false,"","","complete","20:45"]});
  const tree=f.load("src/pages/ManualPunch.tsx").default();
  assert.ok(JSON.stringify(tree).includes("04:00"));
  await nodes(tree).find(n=>n.type==="form").props.onSubmit({preventDefault(){}});
  assert.equal(f.calls.length,1); assert.equal(f.calls[0][0],"manualSession");
  assert.equal(f.calls[0][1].entry,"07:45"); assert.equal(f.calls[0][1].exit,"20:45");
});
await test("El panel incluye jornadas automáticas con horarios inferidos",()=>{
  const f=fixture({data:{...base,records:[{...record,status:"Automático",inferredEntry:true}]}});
  const tree=f.load("src/pages/Reviews.tsx").default();
  assert.ok(JSON.stringify(tree).includes("Horario inferido"));
  assert.ok(byTag(tree,"Button").some(n=>JSON.stringify(n.props.children).includes("Corregir")));
});
await test("El reporte filtra por lugar y rango y excluye rechazados del crédito",()=>{
  const records=[{...record,id:"a",isoDate:"2026-10-06",institution:"A",minutes:240,status:"Corregido"},{...record,id:"b",isoDate:"2026-10-07",institution:"A",minutes:120,status:"Rechazado"},{...record,id:"c",isoDate:"2026-10-08",institution:"B",minutes:90,status:"Automático"},{...record,id:"d",isoDate:"2026-10-09",institution:"A",minutes:60,status:"Automático"}];
  const f=fixture({data:{...base,records},states:[employee.id,"","A","2026-10-06","2026-10-08"]});
  const tree=f.load("src/pages/Reports.tsx").default();
  const body=nodes(tree).find(n=>n.type==="tbody");
  assert.equal(nodes(body).filter(n=>n.type==="tr").length,2);
  assert.ok(JSON.stringify(tree).includes("04:00"));
  assert.ok(!JSON.stringify(tree).includes("01:30"));
});
await test("El detalle respeta una jornada histórica distinta a la actual",()=>{
  const f=fixture(); const component=f.load("src/components/OvertimeDetail.tsx").default;
  const tree=component({record:{...record,entry:"07:45",exit:"20:45",scheduleStart:"09:00",scheduleEnd:"18:00",workingDay:true,minutes:240}});
  const text=JSON.stringify(tree);
  assert.ok(text.includes("09:00 a 18:00")); assert.ok(text.includes("01:15")); assert.ok(text.includes("02:45"));
});
await test("El empleado envía una solicitud sin modificar directamente la jornada",async()=>{
  const f=fixture({data:{...base,improvementsAvailable:true,profile:{...base.profile,role:"employee"}},states:["","2026-10-08","place-a","08:00","20:45","Olvidé fichar","","",false]});
  const tree=f.load("src/pages/CorrectionRequests.tsx").default();
  await nodes(tree).find(n=>n.type==="form").props.onSubmit({preventDefault(){}});
  assert.equal(f.calls.length,1); assert.equal(f.calls[0][0],"requestCorrection"); assert.equal(f.calls[0][1].sessionId,null);
});
await test("Un mes con solicitudes pendientes deshabilita su cierre",()=>{
  const f=fixture({data:{...base,correctionRequests:[{status:"pending",work_date:"2026-10-08"}]}});
  const tree=f.load("src/pages/Closure.tsx").default();
  const button=byTag(tree,"Button").find(n=>JSON.stringify(n.props.children).includes("Confirmar cierre mensual"));
  assert.equal(button.props.disabled,true);
});
await test("Los reintentos de jornada completa y solicitud conservan sus identificadores",async()=>{
  for (const [method,input,key] of [["manualSession",{employeeId:employee.id,institutionId:"place-a",date:"2026-10-08",entry:"07:45",exit:"20:45",reason:"Olvido",notes:""},"p_request_id"],["requestCorrection",{sessionId:record.id,institutionId:"place-a",date:"2026-10-08",entry:"07:45",exit:"20:45",reason:"Olvido"},"p_id"]]) {
    let first=true;
    const f=fixture({states:[{user:{id:"user-a"}},false,false,""],rpc:async()=>{if(first){first=false;throw new Error("Red interrumpida");}return [];}});
    const tree=f.load("src/app/ConnectedApp.tsx").default(); const workspace=nodes(tree).find(n=>n.type?.name==="Workspace"); const api=workspace.type(workspace.props).props.value;
    await assert.rejects(()=>api[method](input),/Red interrumpida/); await api[method](input); await api[method](input);
    const ids=f.calls.filter(c=>c[0]==="rpc").map(c=>c[2][key]); assert.equal(ids[0],ids[1]); assert.notEqual(ids[1],ids[2]);
  }
});
await test("La salida conserva el lugar de la entrada aunque se manipule el selector",async()=>{
  const data={...base,specificCheckoutAvailable:true,records:[{...record,exit:undefined,status:"Pendiente",institutionId:"place-a"}]};
  const f=fixture({data,states:[false,new Date(),"Salida",new Date(),"Otro lugar","","Fin","","","",record.id,false]});
  const tree=f.load("src/pages/Register.tsx").default();
  assert.ok(JSON.stringify(tree).includes("Vas a cerrar tu entrada de las"));
  assert.equal(byTag(tree,"Select").length,0);
  await nodes(tree).find(n=>n.type==="form").props.onSubmit({preventDefault(){}});
  assert.equal(f.calls[0][1].institution,"Institución real"); assert.equal(f.calls[0][1].targetId,record.id); assert.equal(f.calls[0][1].confirmWithoutEntry,false);
});
await test("Varias entradas requieren elegir cuál cerrar por identificador",async()=>{
  const data={...base,specificCheckoutAvailable:true,records:[{...record,exit:undefined,status:"Pendiente"},{...record,id:"second",entry:"19:00",exit:undefined,status:"Pendiente"}]};
  const f=fixture({data,states:[false,new Date(),"Salida",new Date(),"Institución real","","Fin","","","","",false]});
  const tree=f.load("src/pages/Register.tsx").default();
  const select=byTag(tree,"Select").find(n=>n.props["aria-label"]==="Entrada a cerrar"); assert.ok(select);
  select.props.onChange({target:{value:"second"}}); assert.ok(f.setters.some(([index,value])=>index===10 && value==="second"));
  await nodes(tree).find(n=>n.type==="form").props.onSubmit({preventDefault(){}}); assert.equal(f.calls.length,0);
  assert.ok(f.setters.some(([,value])=>String(value).includes("Elegí la entrada")));
});
await test("Salida por urgencia sin entrada explica la inferencia y pide confirmación",async()=>{
  const data={...base,specificCheckoutAvailable:true,records:[]};
  for (const confirmed of [false,true]) {
    const f=fixture({data,states:[false,new Date(),"Salida",new Date(),"Institución real","","Urgencia","","","","",confirmed]});
    const tree=f.load("src/pages/Register.tsx").default();
    const text=JSON.stringify(tree); assert.ok(text.includes("urgencia u otro motivo")); assert.ok(text.includes("entrada habitual")); assert.ok(!text.includes("olvidé registrar"));
    await nodes(tree).find(n=>n.type==="form").props.onSubmit({preventDefault(){}});
    assert.equal(f.calls.length,confirmed ? 1 : 0); if(confirmed) {assert.equal(f.calls[0][1].targetId,null);assert.equal(f.calls[0][1].confirmWithoutEntry,true);}
  }
});
await test("Un formulario desactualizado no convierte una entrada cerrada en salida sola",async()=>{
  const f=fixture({data:{...base,specificCheckoutAvailable:true,records:[]},states:[false,new Date(),"Salida",new Date(),"Institución real","","Fin","","","",record.id,true]});
  const tree=f.load("src/pages/Register.tsx").default();
  await nodes(tree).find(n=>n.type==="form").props.onSubmit({preventDefault(){}}); assert.equal(f.calls.length,0);
  assert.ok(f.setters.some(([,value])=>String(value).includes("ya no está abierta")));
});
await test("El empleado puede pedir solo corregir el lugar de una jornada abierta",async()=>{
  const data={...base,improvementsAvailable:true,specificCheckoutAvailable:true,institutions:[...base.institutions,{id:"place-b",name:"Lugar correcto"}],records:[{...record,institutionId:"place-a",exit:undefined,status:"Pendiente"}]};
  const f=fixture({data,states:[record.id,"2026-10-08","place-b","","","Elegí mal el lugar","","",false,true]});
  const tree=f.load("src/pages/CorrectionRequests.tsx").default();
  assert.equal(byTag(tree,"Input").filter(n=>n.props.type==="time").length,0);
  assert.equal(byTag(tree,"Select")[1].props.disabled,false);
  await nodes(tree).find(n=>n.type==="form").props.onSubmit({preventDefault(){}});
  assert.equal(f.calls[0][1].institutionOnly,true); assert.equal(f.calls[0][1].institutionId,"place-b"); assert.equal(f.calls[0][1].sessionId,record.id);
});
await test("El cierre conectado envía el objetivo y conserva el ID al reintentar",async()=>{
  let first=true; const data={...base,specificCheckoutAvailable:true,records:[{...record,institutionId:"place-a",exit:undefined,status:"Pendiente"}]};
  const f=fixture({data,states:[{user:{id:"user-a"}},false,false,""],rpc:async()=>{if(first){first=false;throw new Error("Red interrumpida");}return [];}});
  const tree=f.load("src/app/ConnectedApp.tsx").default(); const workspace=nodes(tree).find(n=>n.type?.name==="Workspace"); const api=workspace.type(workspace.props).props.value;
  const input={kind:"Salida",institution:"Institución real",targetId:record.id,confirmWithoutEntry:false,reason:"Fin",notes:""};
  await assert.rejects(()=>api.punch(input),/Red interrumpida/); await api.punch(input);
  const requests=f.calls.filter(c=>c[0]==="rpc"); assert.equal(requests[0][1],"register_time_event_v2");assert.equal(requests[0][2].p_target,record.id);assert.equal(requests[0][2].p_confirm_without_entry,false);assert.equal(requests[0][2].p_request_id,requests[1][2].p_request_id);
  await assert.rejects(()=>api.punch({...input,institution:"Otro lugar"}),/coincidir/);
});
await test("La corrección solo del lugar envía horarios nulos al servidor",async()=>{
  const f=fixture({data:{...base,specificCheckoutAvailable:true},states:[{user:{id:"user-a"}},false,false,""]});
  const tree=f.load("src/app/ConnectedApp.tsx").default(); const workspace=nodes(tree).find(n=>n.type?.name==="Workspace"); const api=workspace.type(workspace.props).props.value;
  await api.requestCorrection({sessionId:record.id,institutionId:"place-b",date:"2026-10-08",entry:"",exit:"",institutionOnly:true,reason:"Lugar incorrecto"});
  const request=f.calls.find(c=>c[0]==="rpc");assert.equal(request[1],"request_session_correction_v2");assert.equal(request[2].p_institution_only,true);assert.equal(request[2].p_entry,null);assert.equal(request[2].p_exit,null);
});
await test("Sin la migración de cierre no se usa la ruta anterior para salir",async()=>{
  const f=fixture({states:[{user:{id:"user-a"}},false,false,""]}); const tree=f.load("src/app/ConnectedApp.tsx").default(); const workspace=nodes(tree).find(n=>n.type?.name==="Workspace"); const api=workspace.type(workspace.props).props.value;
  await assert.rejects(()=>api.punch({kind:"Salida",institution:"Institución real",reason:"Fin",notes:"",confirmWithoutEntry:true}),/Falta habilitar/);
  assert.equal(f.calls.length,0);
});
console.log(results.length+" pruebas de integración conectada aprobadas");
