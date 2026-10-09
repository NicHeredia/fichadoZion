import { useRef, useState } from "react";
import { useRemoteData } from "../app/DataContext";
import { Badge, Button, Card, Input, PageTitle, Select } from "../components/ui";
import { formatMinutes } from "../lib/demo";
import { localDate } from "../lib/records";
import { compensationLabels, exportCompensations, parseDuration } from "../lib/compensations";

export default function Compensations() {
  const remote = useRemoteData();
  const admin = remote?.profile.role === "admin";
  const [employee, setEmployee] = useState(remote?.profile.employeeId || "");
  const [duration, setDuration] = useState("");
  const [date, setDate] = useState(localDate());
  const [reason, setReason] = useState("");
  const [status, setStatus] = useState<"scheduled" | "completed">("scheduled");
  const [cancelling, setCancelling] = useState<string | null>(null);
  const [cancellationReason, setCancellationReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const lock = useRef(false);
  if (!remote) return <PageTitle title="Compensaciones" subtitle="Las compensaciones están disponibles al conectar la aplicación al servidor." />;
  if (!remote.compensationData) return <><PageTitle title="Compensaciones" subtitle="Este módulo todavía no está habilitado para tu organización." /><Card><p>Contactá al administrador para habilitar la gestión de descansos por horas extras.</p></Card></>;
  const { compensations, balances } = remote.compensationData;
  const balance = balances.find(b => b.employeeId === employee);
  const person = remote.employees.find(e => e.id === employee);
  const selected = compensations.filter(c => c.employeeId === employee);
  async function perform(action: () => Promise<void>, message: string) {
    if (lock.current) return;
    lock.current = true; setBusy(true); setError(""); setNotice("");
    try { await action(); setNotice(message); }
    catch (failure) { setError(failure instanceof Error ? failure.message : "No se pudo guardar la compensación."); }
    finally { lock.current = false; setBusy(false); }
  }
  async function create(event: React.FormEvent) {
    event.preventDefault();
    await perform(async () => {
      const minutes = parseDuration(duration);
      if (minutes > (balance?.available ?? 0)) throw new Error("Las horas solicitadas superan el saldo disponible.");
      await remote!.createCompensation({ employeeId: employee, minutes, restDate: date, reason, status });
      setDuration(""); setReason("");
    }, status === "scheduled" ? "Descanso programado. Las horas quedaron reservadas." : "Descanso registrado. Las horas se descontaron del saldo.");
  }
  return <>
    <PageTitle title="Compensaciones" subtitle="Canje de horas extras por descanso. Los fichajes y las horas trabajadas se conservan." action={<Button variant="secondary" disabled={!selected.length} onClick={() => exportCompensations(selected, remote.employees)}>Exportar descansos</Button>} />
    {error && <p className="error-banner" role="alert">{error}</p>}{notice && <p className="success-banner" role="status">{notice}</p>}
    <Card className="report-selector"><label>Empleado<Select aria-label="Empleado para compensaciones" disabled={busy || !admin} value={employee} onChange={e => { setEmployee(e.target.value); setCancelling(null); setCancellationReason(""); setError(""); setNotice(""); }}>{remote.employees.map(e => <option key={e.id} value={e.id}>{e.name} · {e.employeeNumber}</option>)}</Select></label><p>Saldo acumulado de todo el historial. Incluye horas automáticas, aprobadas y corregidas; excluye pendientes y rechazadas.</p></Card>
    <div className="report-stats"><Card><span>Horas extras acumuladas</span><strong>{formatMinutes(balance?.earned ?? 0)}</strong></Card><Card><span>Reservadas para descanso</span><strong className="text-orange">{formatMinutes(balance?.reserved ?? 0)}</strong></Card><Card><span>Compensadas con descanso</span><strong>{formatMinutes(balance?.used ?? 0)}</strong></Card><Card><span>Saldo disponible</span><strong className="text-green">{formatMinutes(balance?.available ?? 0)}</strong></Card></div>
    {admin && <Card><form onSubmit={create}><fieldset disabled={busy || person?.status !== "Activo"}><h2>Registrar descanso</h2><div className="form-grid">
      <label>Horas a compensar<Input aria-label="Horas a compensar" placeholder="3:30" required inputMode="text" pattern="[0-9]{1,6}:[0-5][0-9]" maxLength={9} value={duration} onChange={e => setDuration(e.target.value)} /><small>Formato horas:minutos. Ejemplo: 3:30.</small></label>
      <label>Estado<Select value={status} onChange={e => { setStatus(e.target.value as "scheduled" | "completed"); setDate(localDate()); }}><option value="scheduled">Programado — reservar horas</option><option value="completed">Realizado — descontar horas</option></Select></label>
      <label>Fecha del descanso<Input type="date" required min={status === "scheduled" ? localDate() : undefined} max={status === "completed" ? localDate() : undefined} value={date} onChange={e => setDate(e.target.value)} /></label>
      <label className="full">Motivo<textarea required maxLength={2000} rows={2} value={reason} onChange={e => setReason(e.target.value)} /></label>
    </div><div className="title-actions"><Button disabled={busy || !reason.trim() || !duration || !balance || balance.available <= 0}>{busy ? "Guardando…" : "Registrar descanso"}</Button></div></fieldset></form>{person?.status !== "Activo" && <p>Este legajo está inactivo; no se pueden registrar nuevos descansos.</p>}</Card>}
    <Card className="table-card"><div className="card-head"><div><h2>Descansos de {person?.name}</h2><p>Programado reserva horas; realizado confirma su uso; cancelado libera las horas. Los cambios quedan auditados.</p></div></div><div className="table-scroll"><table><thead><tr><th>Fecha del descanso</th><th>Horas</th><th>Motivo</th><th>Estado</th>{admin && <th>Acciones</th>}</tr></thead><tbody>{selected.map(c => <tr key={c.id}><td>{c.restDate.split("-").reverse().join("/")}</td><td>{formatMinutes(c.minutes)}</td><td className="description-cell">{c.reason}{c.cancellationReason && <small className="sub-cell">Cancelación: {c.cancellationReason}</small>}</td><td><Badge tone={c.status === "scheduled" ? "orange" : c.status === "completed" ? "green" : "neutral"}>{compensationLabels[c.status]}</Badge></td>{admin && <td><div className="title-actions">{c.status === "scheduled" && <Button variant="secondary" disabled={busy || c.restDate > localDate()} onClick={() => void perform(() => remote.changeCompensation(c.id,"completed"), "Descanso confirmado. Las horas reservadas pasaron a compensadas.")}>Confirmar realizado</Button>}{c.status !== "cancelled" && <Button variant="danger" disabled={busy} onClick={() => { setCancelling(c.id); setCancellationReason(""); setError(""); }}>{c.status === "completed" ? "Anular descuento" : "Cancelar"}</Button>}</div>{cancelling === c.id && <form onSubmit={e => { e.preventDefault(); void perform(async () => { await remote.changeCompensation(c.id,"cancelled",cancellationReason); setCancelling(null); setCancellationReason(""); }, "Compensación cancelada. Las horas volvieron al saldo disponible."); }}><fieldset disabled={busy}><label>Motivo de cancelación<textarea required maxLength={2000} rows={2} value={cancellationReason} onChange={e => setCancellationReason(e.target.value)} /></label><div className="title-actions"><Button type="button" variant="secondary" onClick={() => setCancelling(null)}>Volver</Button><Button variant="danger" disabled={busy || !cancellationReason.trim()}>Confirmar cancelación</Button></div></fieldset></form>}</td>}</tr>)}{!selected.length && <tr><td colSpan={admin ? 5 : 4}>Todavía no hay descansos registrados.</td></tr>}</tbody></table></div></Card>
  </>;
}
