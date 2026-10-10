import { useEffect, useRef, useState, type FormEvent } from "react";
import { useRemoteData } from "../app/DataContext";
import type { WorkRecord } from "../lib/demo";
import { Button, Input, Select } from "./ui";

export default function AdminHistoryEditor({ record, onClose }: { record: WorkRecord; onClose: () => void }) {
  const remote = useRemoteData();
  const [action, setAction] = useState<"corrected" | "rejected">("corrected");
  const [entry, setEntry] = useState(record.entry || "");
  const [exit, setExit] = useState(record.exit || "");
  const [institutionId, setInstitutionId] = useState(record.institutionId || "");
  const [institutionOnly, setInstitutionOnly] = useState(false);
  const [notes, setNotes] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const lock = useRef(false);
  const panel = useRef<HTMLElement>(null);
  useEffect(() => { panel.current?.scrollIntoView({ behavior: "smooth", block: "center" }); }, []);
  if (!remote || remote.profile.role !== "admin" || !remote.profile.active || !remote.adminHistoryAvailable) return null;
  async function submit(event: FormEvent) {
    event.preventDefault();
    if (!remote || lock.current) return;
    if (!notes.trim()) { setError("Indicá el motivo del cambio."); return; }
    lock.current = true; setBusy(true); setError("");
    try {
      await remote.editHistory(record, {
        action, entry, exit, institutionOnly: action === "corrected" && institutionOnly,
        institutionId: action === "rejected" ? record.institutionId || "" : institutionId, notes,
      });
      onClose();
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : "No se pudo guardar el cambio.");
    } finally { lock.current = false; setBusy(false); }
  }
  return <section ref={panel} className="card history-editor" aria-labelledby="history-editor-title">
    <h2 id="history-editor-title">Modificar fichaje · {record.employee}</h2>
    <p>{record.date} · {record.institution} · {record.entry || "Sin entrada"} a {record.exit || "Sin salida"} · {record.status}</p>
    <p>Los movimientos originales se conservan. El motivo y los cambios quedan en la auditoría.</p>
    {error && <p className="error-banner" role="alert">{error}</p>}
    <form onSubmit={submit}><fieldset disabled={busy}>
      <div className="form-grid">
        <label>Acción<Select value={action} onChange={e => { setAction(e.target.value as "corrected" | "rejected"); setError(""); }}>
          <option value="corrected">Corregir fichaje</option>
          {record.status !== "Rechazado" && <option value="rejected">Desestimar fichaje</option>}
        </Select></label>
        {action === "corrected" && <>
          <label>Institución<Select required value={institutionId} onChange={e => setInstitutionId(e.target.value)}>
            <option value="">Seleccionar institución</option>
            {record.institutionId && !remote.institutions.some(i => i.id === record.institutionId) && <option value={record.institutionId}>{record.institution} (histórica)</option>}
            {remote.institutions.map(i => <option key={i.id} value={i.id}>{i.name}</option>)}
          </Select></label>
          {!institutionOnly && <>
            <label>Entrada<Input type="time" required value={entry} onChange={e => setEntry(e.target.value)} /></label>
            <label>Salida<Input type="time" required value={exit} onChange={e => setExit(e.target.value)} /></label>
          </>}
        </>}
      </div>
      {action === "corrected" && <label className="checkbox-label"><input type="checkbox" checked={institutionOnly} onChange={e => setInstitutionOnly(e.target.checked)} /> Cambiar solo la institución, conservando horarios y estado</label>}
      {action === "rejected" && <p className="warning-banner">El fichaje quedará rechazado y sus horas dejarán de contar en el saldo. El registro permanecerá en el historial.</p>}
      {action === "corrected" && record.status === "Rechazado" && !institutionOnly && <p className="warning-banner">Al guardar los horarios, este fichaje volverá a contar como Corregido.</p>}
      <label>Motivo obligatorio<textarea className="field" required maxLength={2000} rows={3} value={notes} onChange={e => setNotes(e.target.value)} placeholder="Explicá por qué realizás este cambio" /></label>
      <div className="title-actions">
        <Button type="submit" variant={action === "rejected" ? "danger" : "primary"} disabled={busy || !notes.trim() || (action === "corrected" && (institutionOnly ? institutionId === record.institutionId : !entry || !exit || exit <= entry))}>{busy ? "Guardando…" : action === "rejected" ? "Confirmar desestimación" : "Guardar corrección"}</Button>
        <Button type="button" variant="secondary" disabled={busy} onClick={onClose}>Cancelar</Button>
      </div>
    </fieldset></form>
  </section>;
}
