import { useRef, useState } from "react";
import { Link } from "react-router";
import { useRemoteData } from "../app/DataContext";
import { Button, Card, Input, PageTitle, Select } from "../components/ui";
import { localDate } from "../lib/records";

export default function ManualPunch() {
  const remote = useRemoteData();
  const [employee, setEmployee] = useState(remote?.employees[0]?.id || "");
  const [kind, setKind] = useState<"Entrada" | "Salida">("Entrada");
  const [institution, setInstitution] = useState(remote?.institutions[0]?.id || "");
  const [date, setDate] = useState(localDate());
  const [time, setTime] = useState("");
  const [reason, setReason] = useState("");
  const [notes, setNotes] = useState("");
  const [target, setTarget] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const lock = useRef(false);
  if (!remote || remote.profile.role !== "admin") return <PageTitle title="Fichaje manual" subtitle="La carga manual requiere un administrador habilitado." />;
  if (!remote.manualPunchAvailable) return <><PageTitle title="Fichaje manual" subtitle="La carga manual todavía no está habilitada para tu organización." /><Card><p>El administrador debe habilitar el módulo antes de cargar movimientos.</p></Card></>;
  const place = remote.institutions.find(i => i.id === institution);
  const candidates = remote.records.filter(r => r.employeeId === employee && r.isoDate === date && r.institution === place?.name
    && ["Pendiente","Automático"].includes(r.status)
    && (kind === "Entrada" ? !r.entry || r.inferredEntry : !r.exit || r.inferredExit));
  const selectedTarget = candidates.some(r => r.id === target) ? target : candidates.length === 1 ? candidates[0].id : "";
  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (lock.current) return;
    lock.current = true; setBusy(true); setError(""); setNotice("");
    try {
      if (candidates.length && !selectedTarget) throw new Error("Seleccioná la jornada que querés completar.");
      await remote!.manualPunch({ employeeId: employee, kind, institutionId: institution, date, time, reason, notes, targetId: selectedTarget || null });
      setTime(""); setReason(""); setNotes(""); setTarget("");
      setNotice("Fichaje manual guardado. La jornada y sus horas se actualizaron; podés revisarlas en el historial.");
    } catch (failure) { setError(failure instanceof Error ? failure.message : "No se pudo guardar el fichaje manual."); }
    finally { lock.current = false; setBusy(false); }
  }
  return <><PageTitle title="Cargar fichaje manual" subtitle="Registrá un movimiento olvidado con su fecha y hora reales. Tu cuenta queda identificada como responsable de la carga." action={<Link className="btn btn-secondary" to="/historial">Ver historial</Link>} />
    {error && <p className="error-banner" role="alert">{error}</p>}{notice && <p className="success-banner" role="status">{notice}</p>}
    <Card><form onSubmit={submit}><fieldset disabled={busy}><div className="form-grid">
      <label>Empleado<Select required value={employee} onChange={e => { setEmployee(e.target.value); setTarget(""); }}>{remote.employees.map(e => <option key={e.id} value={e.id}>{e.name} · {e.employeeNumber}{e.status !== "Activo" ? " · Inactivo" : ""}</option>)}</Select></label>
      <label>Movimiento<Select value={kind} onChange={e => { setKind(e.target.value as "Entrada" | "Salida"); setTarget(""); }}><option>Entrada</option><option>Salida</option></Select></label>
      <label>Institución<Select required value={institution} onChange={e => { setInstitution(e.target.value); setTarget(""); }}>{remote.institutions.map(i => <option key={i.id} value={i.id}>{i.name}</option>)}</Select></label>
      <label>Fecha real del movimiento<Input type="date" required max={localDate()} value={date} onChange={e => { setDate(e.target.value); setTarget(""); }} /></label>
      <label>Hora real del movimiento<Input type="time" required value={time} onChange={e => setTime(e.target.value)} /><small>Hora de Argentina.</small></label>
      <label>Jornada a completar<Select value={selectedTarget} onChange={e => setTarget(e.target.value)} required={candidates.length > 0}><option value="">{candidates.length ? "Elegí una jornada" : "Crear un nuevo período"}</option>{candidates.map(r => <option key={r.id} value={r.id}>{r.entry || "Sin entrada"}{r.inferredEntry ? " (inferida)" : ""} → {r.exit || "Sin salida"}{r.inferredExit ? " (inferida)" : ""} · {r.status}</option>)}</Select></label>
      <label className="full">Motivo de la carga manual<textarea required maxLength={1000} rows={3} value={reason} onChange={e => setReason(e.target.value)} placeholder="Por ejemplo: olvidó marcar la salida; horario verificado por el responsable." /></label>
      <label className="full">Observaciones opcionales<textarea maxLength={2000} rows={2} value={notes} onChange={e => setNotes(e.target.value)} /></label>
    </div><p>La hora indicada se usa para el cálculo. También se conserva cuándo se realizó esta carga. Si la salida fue inferida, elegí esa jornada para reemplazarla por la salida real.</p><p>Los meses cerrados requieren reapertura. Para una jornada ya aprobada, corregida o rechazada no se agregan nuevos movimientos. Los períodos nuevos usan la jornada y los feriados configurados actualmente.</p><div className="title-actions"><Button disabled={busy || !employee || !institution || !date || !time || !reason.trim() || (candidates.length > 0 && !selectedTarget)}>{busy ? "Guardando…" : "Guardar fichaje manual"}</Button></div></fieldset></form></Card>
  </>;
}
