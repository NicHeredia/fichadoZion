import { useRef, useState } from "react"
import { Link, useSearchParams } from "react-router"
import { useRemoteData } from "../app/DataContext"
import { Button, Card, Input, PageTitle, Select } from "../components/ui"
import { localDate } from "../lib/records"

export default function CorrectionRequests() {
  const remote = useRemoteData()
  const [params] = useSearchParams()
  const original = remote?.records.find((r) => r.id === params.get("jornada") && r.employeeId === remote.profile.employeeId)
  const [session, setSession] = useState(original?.id || "")
  const [date, setDate] = useState(original?.isoDate || localDate())
  const [institution, setInstitution] = useState(
    original?.institutionId ||
      remote?.institutions.find((i) => i.name === original?.institution)?.id ||
      remote?.institutions[0]?.id ||
      "",
  )
  const [entry, setEntry] = useState(original?.entry || "")
  const [exit, setExit] = useState(original?.exit || "")
  const [reason, setReason] = useState("")
  const [error, setError] = useState("")
  const [notice, setNotice] = useState("")
  const [busy, setBusy] = useState(false)
  const lock = useRef(false)
  const [institutionOnly, setInstitutionOnly] = useState(false)
  if (!remote?.improvementsAvailable)
    return (
      <>
        <PageTitle
          title="Solicitudes de corrección"
          subtitle="Pedí la revisión de un fichaje olvidado o incorrecto."
        />
        <Card>
          <p>
            Las solicitudes todavía no están habilitadas para tu organización.
          </p>
        </Card>
      </>
    )
  const ownRecords = remote.records.filter(
    (r) =>
      r.employeeId === remote.profile.employeeId && r.status !== "Rechazado",
  )
  const selected = ownRecords.find((r) => r.id === session)
  const historicalPlace =
    selected && !remote.institutions.some((i) => i.id === institution)
  async function submit(event: React.FormEvent) {
    event.preventDefault()
    if (lock.current) return
    lock.current = true
    setBusy(true)
    setError("")
    setNotice("")
    try {
      await remote!.requestCorrection({
        sessionId: session || null,
        institutionId: institution,
        date,
        entry,
        exit,
        reason,
        ...(remote!.specificCheckoutAvailable ? { institutionOnly: !!selected && institutionOnly } : {}),
      })
      setReason("")
      setNotice(
        "Solicitud enviada. Los datos de la jornada se mantienen hasta que el administrador la apruebe.",
      )
    } catch (failure) {
      setError(
        failure instanceof Error
          ? failure.message
          : "No se pudo enviar la solicitud.",
      )
    } finally {
      lock.current = false
      setBusy(false)
    }
  }
  const statuses = {
    pending: "Pendiente",
    approved: "Aprobada",
    rejected: "Rechazada",
  }
  const ownRequests =
    remote.correctionRequests?.filter(
      (r) => r.employee_id === remote.profile.employeeId,
    ) ?? []
  return (
    <>
      <PageTitle
        title="Mis solicitudes de corrección"
        subtitle="Proponé los horarios reales y explicá el motivo. Cada decisión queda registrada."
        action={
          remote.profile.role === "admin" ? (
            <Link className="btn btn-secondary" to="/revisiones">
              Revisar solicitudes del equipo
            </Link>
          ) : undefined
        }
      />
      {error && (
        <p role="alert" className="error-banner">
          {error}
        </p>
      )}
      {notice && (
        <p role="status" className="success-banner">
          {notice}
        </p>
      )}
      <Card>
        <h2>Nueva solicitud</h2>
        <form onSubmit={submit}>
          <fieldset disabled={busy || !remote.profile.active}>
            <div className="form-grid">
              <label className="full">
                Jornada
                <Select
                  value={session}
                  onChange={(e) => {
                    const r = ownRecords.find((r) => r.id === e.target.value)
                    setSession(e.target.value)
                    setInstitutionOnly(false)
                    setDate(r?.isoDate || localDate())
                    setInstitution(
                      r?.institutionId ||
                        remote.institutions.find(
                          (i) => i.name === r?.institution,
                        )?.id ||
                        remote.institutions[0]?.id ||
                        "",
                    )
                    setEntry(r?.entry || "")
                    setExit(r?.exit || "")
                  }}
                >
                  <option value="">
                    Olvidé ambos fichajes: solicitar una nueva jornada
                  </option>
                  {ownRecords.map((r) => (
                    <option key={r.id} value={r.id}>
                      {r.date} · {r.institution} · {r.entry || "Sin entrada"} →{" "}
                      {r.exit || "Sin salida"}
                    </option>
                  ))}
                </Select>
              </label>
              <label>
                Fecha
                <Input
                  type="date"
                  required
                  max={localDate()}
                  readOnly={!!selected}
                  value={date}
                  onChange={(e) => setDate(e.target.value)}
                />
              </label>
              <label>
                Institución
                <Select
                  required
                  disabled={!!selected && !remote.specificCheckoutAvailable}
                  value={institution}
                  onChange={(e) => setInstitution(e.target.value)}
                >
                  {historicalPlace && (
                    <option value={institution}>{selected?.institution}</option>
                  )}
                  {remote.institutions.map((i) => (
                    <option key={i.id} value={i.id}>
                      {i.name}
                    </option>
                  ))}
                </Select>
              </label>
              {selected && remote.specificCheckoutAvailable && <label className="full checkbox-label"><input type="checkbox" checked={institutionOnly} onChange={e => setInstitutionOnly(e.target.checked)} /> Solo corregir la institución; conservar los horarios y el estado actuales.</label>}
              {!institutionOnly && <><label>
                Entrada real
                <Input
                  type="time"
                  required
                  value={entry}
                  onChange={(e) => setEntry(e.target.value)}
                />
              </label>
              <label>
                Salida real
                <Input
                  type="time"
                  required
                  value={exit}
                  onChange={(e) => setExit(e.target.value)}
                />
              </label></>}
              <label className="full">
                Motivo
                <textarea
                  required
                  maxLength={1000}
                  rows={3}
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  placeholder="Por ejemplo: olvidé marcar la salida; salí a las 20:45."
                />
              </label>
            </div>
            <p>{institutionOnly ? "Podés corregir el lugar incluso si la jornada todavía no tiene salida. El administrador debe aprobarlo." : "Ingresá los dos horarios del mismo día, en hora de Argentina."}</p>
            <Button
              disabled={
                busy ||
                (!institutionOnly && (!entry || !exit || exit <= entry)) ||
                (institutionOnly && (!selected || institution === selected.institutionId)) ||
                !date ||
                !institution ||
                !reason.trim()
              }
            >
              {busy ? "Enviando…" : "Enviar solicitud"}
            </Button>
          </fieldset>
        </form>
      </Card>
      <Card className="table-card">
        <div className="card-head">
          <h2>Seguimiento de mis solicitudes</h2>
        </div>
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Fecha</th>
                <th>Lugar</th>
                <th>Horarios propuestos</th>
                <th>Motivo</th>
                <th>Estado</th>
                <th>Respuesta</th>
              </tr>
            </thead>
            <tbody>
              {ownRequests.map((r) => (
                <tr key={r.id}>
                  <td>{r.work_date.split("-").reverse().join("/")}</td>
                  <td>
                    {remote.institutions.find((i) => i.id === r.institution_id)
                      ?.name || "Institución histórica"}
                  </td>
                  <td>
                    {r.institution_only ? "Solo institución" : <>{r.proposed_entry?.slice(0, 5)} → {r.proposed_exit?.slice(0, 5)}</>}
                  </td>
                  <td className="description-cell">{r.reason}</td>
                  <td>{statuses[r.status]}</td>
                  <td className="description-cell">
                    {r.resolution_notes || "Esperando revisión"}
                  </td>
                </tr>
              ))}
              {!ownRequests.length && (
                <tr>
                  <td colSpan={6}>Todavía no enviaste solicitudes.</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </Card>
    </>
  )
}
