import { useRef, useState } from "react";
import { AlertTriangle, Check, X, Pencil } from "lucide-react";
import { Button, Card, Input, PageTitle } from "../components/ui";
import { formatMinutes } from "../lib/demo";
import { updateRecord } from "../lib/records";
import { useAppRecords } from "../app/useAppRecords";
import { useRemoteData } from "../app/DataContext";

export default function Reviews() {
  const records = useAppRecords();
  const remote = useRemoteData();
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);
  const lock = useRef(false);
  const [editing, setEditing] = useState<string | null>(null);
  const [entry, setEntry] = useState("");
  const [exit, setExit] = useState("");
  const [notes, setNotes] = useState("");
  const pending = records.filter(r => r.status === "Pendiente");
  async function resolve(id: string, status: "Aprobado" | "Rechazado" | "Corregido") {
    if (lock.current) return;
    lock.current = true; setBusy(true); setError(""); setNotice("");
    try {
      if (remote) await remote.review(id, status, status === "Corregido" ? entry : undefined, status === "Corregido" ? exit : undefined, notes);
      else updateRecord(id, { status });
      setEditing(null); setNotes("");
      setNotice(status === "Rechazado" ? "Registro rechazado. Se excluyó de los totales." : status === "Corregido" ? "Horarios corregidos y cálculo actualizado. Los fichajes originales se conservaron." : "Registro aprobado.");
    } catch (failure) { setError(failure instanceof Error ? failure.message : "No se pudo guardar la revisión."); }
    finally { lock.current = false; setBusy(false); }
  }
  return <><PageTitle title="Revisiones" subtitle={remote ? "Resolvé movimientos incompletos o ambiguos. Cada decisión queda registrada en la auditoría." : "Revisá registros pendientes del historial local."} />
    {error && <p className="error-banner" role="alert">{error}</p>}{notice && <p className="success-banner" role="status">{notice}</p>}
    <div className="review-summary"><Card><span className="summary-icon orange"><AlertTriangle size={20} /></span><div><strong>{pending.length}</strong><span>Pendientes</span></div></Card><Card><span className="summary-icon green"><Check size={20} /></span><div><strong>{records.filter(r => ["Aprobado", "Corregido"].includes(r.status)).length}</strong><span>Aprobados o corregidos</span></div></Card></div>
    <div className="review-list">{pending.map(r => <Card className="review-item" key={r.id}><div className="review-person"><div className="avatar">{r.initials}</div><div><h3>{r.employee}</h3><p>{r.date} · {r.institution}</p></div></div><div className="review-detail"><AlertTriangle size={18} /><div><b>{!r.entry || !r.exit ? "Movimiento incompleto" : "Período que requiere revisión"}</b><p>Entrada: {r.entry || "Sin registrar"} · Salida: {r.exit || "Sin registrar"} · Calculado: {formatMinutes(r.minutes)}</p><p>{r.reason}</p></div></div>
      <div className="review-actions"><span>Para aprobar se requieren ambos horarios y un período válido.</span><div><Button variant="danger" disabled={busy} onClick={() => void resolve(r.id, "Rechazado")}><X size={16} /> Rechazar</Button>{remote && <Button variant="secondary" disabled={busy} onClick={() => { setEditing(r.id); setEntry(r.entry || ""); setExit(r.exit || ""); setNotes(""); }}><Pencil size={16} /> Corregir</Button>}<Button disabled={busy || !r.entry || !r.exit || r.exit <= r.entry} onClick={() => void resolve(r.id, "Aprobado")}><Check size={16} /> Aprobar</Button></div></div>
      {editing === r.id && <form className="correction-form" onSubmit={e => { e.preventDefault(); void resolve(r.id, "Corregido"); }}><fieldset disabled={busy}><h3>Corregir horarios del {r.date}</h3><p>Ingresá un período del mismo día. Los fichajes originales no se modifican.</p><div className="form-grid"><label>Entrada<Input type="time" required value={entry} onChange={e => setEntry(e.target.value)} /></label><label>Salida<Input type="time" required value={exit} onChange={e => setExit(e.target.value)} /></label><label className="full">Motivo de corrección<textarea required maxLength={2000} rows={2} value={notes} onChange={e => setNotes(e.target.value)} /></label></div><div className="title-actions"><Button type="button" variant="secondary" onClick={() => setEditing(null)}>Cancelar</Button><Button disabled={busy || !entry || !exit || exit <= entry || !notes.trim()}>{busy ? "Guardando…" : "Guardar corrección"}</Button></div></fieldset></form>}
    </Card>)}{!pending.length && <Card className="empty-state"><Check size={28} /><h2>Todo al día</h2><p>No hay registros pendientes de revisión.</p></Card>}</div>
  </>;
}
