import { useRef, useState } from "react";
import { Download, Search, Pencil } from "lucide-react";
import { Badge, Button, Card, Input, PageTitle, Select } from "../components/ui";
import { employees, formatMinutes } from "../lib/demo";
import { exportRecords } from "../lib/records";
import { useAppRecords } from "../app/useAppRecords";
import { useRemoteData, type AppEmployee } from "../app/DataContext";

export default function Employees() {
  const records = useAppRecords();
  const remote = useRemoteData();
  const directory: AppEmployee[] = remote?.employees ?? employees;
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("");
  const [editing, setEditing] = useState<AppEmployee | null>(null);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  const lock = useRef(false);
  const matches = (employee: AppEmployee, record: typeof records[number]) => remote ? record.employeeId === employee.id : record.employee === employee.name;
  const filtered = directory.filter(e => (!status || e.status === status) && (e.name + " " + e.user).toLocaleLowerCase("es-AR").includes(search.trim().toLocaleLowerCase("es-AR")));
  const selected = records.filter(r => filtered.some(e => matches(e,r)));
  async function save(event: React.FormEvent) {
    event.preventDefault(); if (!editing || !remote || lock.current) return;
    lock.current = true; setBusy(true); setError(""); setNotice("");
    try { await remote.saveEmployee(editing); setEditing(null); setNotice("Empleado actualizado."); }
    catch (failure) { setError(failure instanceof Error ? failure.message : "No se pudo guardar el empleado."); }
    finally { lock.current = false; setBusy(false); }
  }
  async function changeRole(employee: AppEmployee, role: "admin" | "employee") {
    if (!remote || lock.current || employee.appRole === role || employee.profileId === remote.profile.id) return;
    lock.current = true; setBusy(true); setError(""); setNotice("");
    try {
      await remote.saveEmployee({ ...employee, appRole: role });
      setNotice(employee.name + (role === "admin" ? " ahora tiene rol de administrador." : " ahora tiene rol de empleado."));
    } catch (failure) { setError(failure instanceof Error ? failure.message : "No se pudo cambiar el rol."); }
    finally { lock.current = false; setBusy(false); }
  }
  return <><PageTitle title="Empleados" subtitle={remote ? "Los usuarios pueden crear su cuenta desde la pantalla de acceso. Elegí su rol en esta tabla para asignar o quitar acceso de administrador." : "Directorio de demostración. Los totales corresponden al historial local completo."} />
    {error && <p role="alert" className="error-banner">{error}</p>}{notice && <p role="status" className="success-banner">{notice}</p>}
    <div className="quick-summary"><span><b>{directory.filter(e => e.status === "Activo").length}</b> Activos</span><i /><span><b>{directory.filter(e => e.status === "Inactivo").length}</b> Inactivos</span><i /><span><b>{formatMinutes(records.filter(r => r.status !== "Rechazado").reduce((s, r) => s + r.minutes, 0))}</b> Horas calculadas</span></div>
    {editing && <Card><form onSubmit={save}><fieldset disabled={busy}><h2>Editar empleado</h2><div className="form-grid"><label>Nombre<Input autoFocus required maxLength={150} value={editing.name} onChange={e => setEditing({ ...editing,name:e.target.value })} /></label><label>Legajo<Input required maxLength={100} value={editing.employeeNumber || ""} onChange={e => setEditing({ ...editing,employeeNumber:e.target.value })} /></label><label>Estado<Select value={editing.status} onChange={e => setEditing({ ...editing,status:e.target.value as "Activo" | "Inactivo" })}><option>Activo</option><option>Inactivo</option></Select></label><label>Rol<Select disabled={editing.profileId === remote?.profile.id} value={editing.appRole} onChange={e => setEditing({ ...editing,appRole:e.target.value as "admin" | "employee" })}><option value="employee">Empleado</option><option value="admin">Administrador</option></Select></label></div><div className="title-actions"><Button type="button" variant="secondary" onClick={() => setEditing(null)}>Cancelar</Button><Button disabled={busy}>{busy ? "Guardando…" : "Guardar empleado"}</Button></div></fieldset></form></Card>}
    <Card className="table-card"><div className="filters-row"><div className="search wide"><Search size={17} /><Input value={search} aria-label="Buscar empleado" onChange={e => setSearch(e.target.value)} placeholder="Buscar por nombre o legajo..." /></div><Select value={status} aria-label="Estado del empleado" onChange={e => setStatus(e.target.value)}><option value="">Todos los estados</option><option>Activo</option><option>Inactivo</option></Select><Button variant="ghost" disabled={!selected.length} onClick={() => exportRecords(selected, "fichajes-empleados.csv")}><Download size={16} /> Exportar fichajes</Button></div>
    <div className="table-scroll"><table><thead><tr><th>Empleado</th><th>Legajo</th><th>Estado</th>{remote && <th>Rol</th>}<th>Registros</th><th>Horas calculadas</th><th>Aprobadas</th><th>Pendientes</th><th>Último registro</th>{remote && <th>Acciones</th>}</tr></thead><tbody>{filtered.map(employee => { const own = records.filter(r => matches(employee,r)); return <tr key={employee.id}><td><div className="person"><div className="avatar tiny">{employee.initials}</div><div><b>{employee.name}</b><small>{employee.role}</small></div></div></td><td>{employee.user}</td><td><Badge tone={employee.status === "Activo" ? "green" : "neutral"}>{employee.status}</Badge></td>{remote && <td><Select className="employee-role" aria-label={"Rol de " + employee.name} value={employee.appRole || "employee"} disabled={busy || employee.profileId === remote.profile.id} onChange={e => void changeRole(employee, e.target.value as "admin" | "employee")}><option value="employee">Empleado</option><option value="admin">Administrador</option></Select>{employee.profileId === remote.profile.id && <small className="sub-cell">Tu cuenta</small>}</td>}<td>{own.length}</td><td>{formatMinutes(own.filter(r => r.status !== "Rechazado").reduce((s, r) => s + r.minutes, 0))}</td><td className="text-green">{formatMinutes(own.filter(r => ["Aprobado", "Corregido"].includes(r.status)).reduce((s, r) => s + r.minutes, 0))}</td><td>{own.filter(r => r.status === "Pendiente").length}</td><td>{own[0]?.date || "Sin movimientos"}</td>{remote && <td><Button variant="secondary" disabled={busy} onClick={() => { setEditing({ ...employee }); setError(""); setNotice(""); }}><Pencil size={14} /> Editar</Button></td>}</tr>; })}{!filtered.length && <tr><td colSpan={remote ? 10 : 8}>No hay empleados que coincidan con los filtros.</td></tr>}</tbody></table></div><div className="table-foot">{filtered.length} de {directory.length} empleados{!remote && " de demostración"}{remote && " · Los cambios de rol se guardan al elegirlos."}</div></Card>
  </>;
}
