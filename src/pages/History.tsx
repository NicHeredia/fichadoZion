import { useAppRecords } from "../app/useAppRecords";
import { useRemoteData } from "../app/DataContext";
import { useState } from "react";
import { useSearchParams } from "react-router";
import { Download, Search } from "lucide-react";
import { Button, Card, Input, PageTitle, Select } from "../components/ui";
import { formatMinutes } from "../lib/demo";
import { exportRecords, getStorageError, recordMonth } from "../lib/records";
import { StatusBadge } from "../components/StatusBadge";

export function History() {
  const records = useAppRecords();
  const remote = useRemoteData();
  const [params, setParams] = useSearchParams();
  const search = params.get("q") || "";
  const setSearch = (value: string) => setParams(value ? { q: value } : {}, { replace: true });
  const [month, setMonth] = useState("");
  const [institution, setInstitution] = useState("");
  const [status, setStatus] = useState("");
  const normalized = (value: string) => value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  const filtered = records.filter(r => (!month || recordMonth(r) === month) && (!institution || r.institution === institution) && (!status || r.status === status) && normalized([r.employee, r.reason, r.notes, r.institution].join(" ")).includes(normalized(search.trim())));
  const months = [...new Set(records.map(recordMonth).filter(Boolean))].sort().reverse();
  return <>
    <PageTitle title="Historial de movimientos" subtitle={remote ? "Períodos registrados y calculados en el servidor. Los movimientos originales se muestran abajo." : "Fichajes de demostración y registros guardados en este navegador."} action={<Button variant="secondary" disabled={!filtered.length} onClick={() => exportRecords(filtered)}><Download size={16} /> Exportar resultados</Button>} />
    {!remote && getStorageError() && <p role="alert" className="error-banner">{getStorageError()}</p>}
    <Card className="filter-card"><div className="filters-row">
      <div className="search wide"><Search size={17} /><Input aria-label="Buscar empleado o motivo" placeholder="Buscar empleado o motivo..." value={search} onChange={e => setSearch(e.target.value)} /></div>
      <Select aria-label="Período" value={month} onChange={e => setMonth(e.target.value)}><option value="">Todos los períodos</option>{months.map(m => <option key={m}>{m}</option>)}</Select>
      <Select aria-label="Institución" value={institution} onChange={e => setInstitution(e.target.value)}><option value="">Todas las instituciones</option>{[...new Set(records.map(r => r.institution))].map(i => <option key={i}>{i}</option>)}</Select>
      <Select aria-label="Estado" value={status} onChange={e => setStatus(e.target.value)}><option value="">Todos los estados</option>{["Aprobado", "Automático", "Pendiente", "Corregido", "Rechazado"].map(s => <option key={s}>{s}</option>)}</Select>
      <Button variant="secondary" onClick={() => { setSearch(""); setMonth(""); setInstitution(""); setStatus(""); }}>Limpiar</Button>
    </div></Card>
    <Card className="table-card"><div className="table-scroll"><table><thead><tr><th>Fecha</th><th>Empleado</th><th>Entrada</th><th>Salida</th><th>Institución y motivo</th><th>Horas extra</th><th>Estado</th></tr></thead><tbody>
      {filtered.map(r => <tr key={r.id}><td><b>{r.date}</b></td><td><div className="person"><div className="avatar tiny">{r.initials}</div><b>{r.employee}</b></div></td><td><span className={r.inferredEntry ? "time inferred" : "time"}>{r.entry ?? (r.inferredEntry ? "08:00" : "Sin registrar")}{r.inferredEntry && <small>Inferido</small>}</span></td><td><span className={r.inferredExit ? "time inferred" : "time"}>{r.exit ?? (r.inferredExit ? "17:00" : "Sin registrar")}{r.inferredExit && <small>Inferido</small>}</span></td><td className="description-cell"><div className="stack"><b>{r.institution}</b><span>{r.reason}</span>{r.notes && <span>Observaciones: {r.notes}</span>}</div></td><td><b>{formatMinutes(r.minutes)}</b></td><td><StatusBadge status={r.status} /></td></tr>)}
      {!filtered.length && <tr><td colSpan={7}>No hay movimientos que coincidan con los filtros.</td></tr>}
    </tbody></table></div><div className="table-foot">{filtered.length} de {records.length} registros · Los horarios inferidos se indican explícitamente.</div></Card>
    {remote && <Card className="table-card"><div className="card-head"><div><h2>Movimientos originales</h2><p>Hora del servidor. Las correcciones de períodos no alteran estos fichajes.</p></div></div><div className="table-scroll"><table><thead><tr><th>Fecha y hora</th><th>Empleado</th><th>Movimiento</th><th>Institución</th><th>Motivo</th><th>Observaciones</th></tr></thead><tbody>{remote.events.filter(e => { const person = remote.employees.find(p => p.id === e.employeeId); return (!month || e.occurredAt && new Intl.DateTimeFormat("en-CA", { timeZone: "America/Argentina/Buenos_Aires", year: "numeric", month: "2-digit" }).format(new Date(e.occurredAt)) === month) && (!institution || e.institution === institution) && normalized([person?.name, e.reason, e.notes, e.institution].join(" ")).includes(normalized(search.trim())); }).map(e => <tr key={e.id}><td>{new Date(e.occurredAt).toLocaleString("es-AR", { timeZone: "America/Argentina/Buenos_Aires" })}</td><td>{remote.employees.find(p => p.id === e.employeeId)?.name}</td><td>{e.kind}</td><td>{e.institution}</td><td>{e.reason}</td><td>{e.notes || "—"}</td></tr>)}{!remote.events.length && <tr><td colSpan={6}>Todavía no hay movimientos.</td></tr>}</tbody></table></div><div className="table-foot">El filtro de estado aplica a los períodos calculados; los movimientos originales no tienen estado de revisión.</div></Card>}
  </>;
}
export default History;
