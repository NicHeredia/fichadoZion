import { useRef, useState } from "react"

import { AlertTriangle, Check, X, Pencil } from "lucide-react"

import { Button, Card, Input, PageTitle, Select } from "../components/ui"

import { needsReview, reviewReason, recordDate } from "../lib/work-details"

import OvertimeDetail from "../components/OvertimeDetail"

import { formatMinutes } from "../lib/demo"

import { updateRecord } from "../lib/records"

import { useAppRecords } from "../app/useAppRecords"

import { useRemoteData } from "../app/DataContext"

export default function Reviews() {
  const records = useAppRecords()

  const remote = useRemoteData()

  const [error, setError] = useState("")

  const [notice, setNotice] = useState("")

  const [busy, setBusy] = useState(false)

  const lock = useRef(false)

  const [editing, setEditing] = useState<string | null>(null)

  const [entry, setEntry] = useState("")

  const [exit, setExit] = useState("")

  const [notes, setNotes] = useState("")

  const [employeeFilter, setEmployeeFilter] = useState("")

  const [from, setFrom] = useState("")

  const [to, setTo] = useState("")

  const [category, setCategory] = useState("")

  const [resolutionNotes, setResolutionNotes] =
    useState<Record<string, string>>({})

  const candidates = records.filter(needsReview)

  const inRange = (employee: string, date: string) =>
    (!employeeFilter || employee === employeeFilter) &&
    (!from || date >= from) &&
    (!to || date <= to)

  const pending = candidates.filter(
    (r) =>
      inRange(r.employeeId || r.employee, recordDate(r)) &&
      (!category || category === reviewReason(r)),
  )

  const requests = (remote?.correctionRequests ?? []).filter(
    (r) =>
      r.status === "pending" &&
      inRange(r.employee_id, r.work_date) &&
      (!category || category === "Solicitud de corrección"),
  )

  async function resolveRequest(id: string, approve: boolean) {
    if (!remote || lock.current) return

    lock.current = true
    setBusy(true)
    setError("")
    setNotice("")

    try {
      await remote.resolveCorrection(id, approve, resolutionNotes[id] || "")
      setNotice(
        approve
          ? "Solicitud aprobada y jornada actualizada."
          : "Solicitud rechazada. Se conservaron los horarios.",
      )
    } catch (failure) {
      setError(
        failure instanceof Error
          ? failure.message
          : "No se pudo resolver la solicitud.",
      )
    } finally {
      lock.current = false
      setBusy(false)
    }
  }

  async function resolve(
    id: string,
    status: "Aprobado" | "Rechazado" | "Corregido",
  ) {
    if (lock.current) return

    lock.current = true
    setBusy(true)
    setError("")
    setNotice("")

    try {
      if (remote)
        await remote.review(
          id,
          status,
          status === "Corregido" ? entry : undefined,
          status === "Corregido" ? exit : undefined,
          notes,
        )
      else updateRecord(id, { status })

      setEditing(null)
      setNotes("")

      setNotice(
        status === "Rechazado"
          ? "Registro rechazado. Se excluyó de los totales."
          : status === "Corregido"
            ? "Horarios corregidos y cálculo actualizado. Los fichajes originales se conservaron."
            : "Registro aprobado.",
      )
    } catch (failure) {
      setError(
        failure instanceof Error
          ? failure.message
          : "No se pudo guardar la revisión.",
      )
    } finally {
      lock.current = false
      setBusy(false)
    }
  }

  return (
    <>
      <PageTitle
        title="Revisiones"
        subtitle={
          remote
            ? "Resolvé movimientos incompletos o ambiguos. Cada decisión queda registrada en la auditoría."
            : "Revisá registros pendientes del historial local."
        }
      />
      {error && (
        <p className="error-banner" role="alert">
          {error}
        </p>
      )}
      {notice && (
        <p className="success-banner" role="status">
          {notice}
        </p>
      )}
      <Card className="filter-card">
        <div className="form-grid">
          <label>
            Empleado
            <Select
              value={employeeFilter}
              onChange={(e) => setEmployeeFilter(e.target.value)}
            >
              <option value="">Todo el equipo</option>
              {remote
                ? remote.employees.map((e) => (
                    <option key={e.id} value={e.id}>
                      {e.name}
                    </option>
                  ))
                : [...new Set(records.map((r) => r.employee))].map((e) => (
                    <option key={e}>{e}</option>
                  ))}
            </Select>
          </label>
          <label>
            Tipo de pendiente
            <Select
              value={category}
              onChange={(e) => setCategory(e.target.value)}
            >
              <option value="">Todos los pendientes</option>
              {[
                "Movimiento incompleto",
                "Horario inferido",
                "Período por revisar",
                "Solicitud de corrección",
              ].map((c) => (
                <option key={c}>{c}</option>
              ))}
            </Select>
          </label>
          <label>
            Desde
            <Input
              type="date"
              value={from}
              onChange={(e) => setFrom(e.target.value)}
            />
          </label>
          <label>
            Hasta
            <Input
              type="date"
              min={from || undefined}
              value={to}
              onChange={(e) => setTo(e.target.value)}
            />
          </label>
        </div>
        <Button
          variant="secondary"
          onClick={() => {
            setEmployeeFilter("")
            setFrom("")
            setTo("")
            setCategory("")
          }}
        >
          Limpiar filtros
        </Button>
      </Card>
      {from && to && to < from && (
        <p role="alert" className="error-banner">
          La fecha final debe ser posterior o igual a la inicial.
        </p>
      )}
      <div className="review-summary">
        <Card>
          <div>
            <strong>
              {candidates.filter((r) => !r.entry || !r.exit).length}
            </strong>
            <span>Movimientos incompletos</span>
          </div>
        </Card>
        <Card>
          <div>
            <strong>
              {
                candidates.filter((r) => r.inferredEntry || r.inferredExit)
                  .length
              }
            </strong>
            <span>Horarios inferidos</span>
          </div>
        </Card>
        <Card>
          <div>
            <strong>
              {remote?.correctionRequests?.filter((r) => r.status === "pending")
                .length || 0}
            </strong>
            <span>Solicitudes por resolver</span>
          </div>
        </Card>
      </div>
      {requests.map((request) => (
        <Card className="request-review" key={request.id}>
          <h3>
            {remote?.employees.find((e) => e.id === request.employee_id)?.name}{" "}
            · Solicitud de corrección
          </h3>
          <p>
            {request.work_date.split("-").reverse().join("/")} ·{" "}
            {remote?.institutions.find((i) => i.id === request.institution_id)
              ?.name || "Institución histórica"}
          </p>
          <p>
            Propuesta:{" "}
            <strong>
              {request.proposed_entry.slice(0, 5)} →{" "}
              {request.proposed_exit.slice(0, 5)}
            </strong>
            {!request.session_id && " · Nueva jornada"}
          </p>
          <p>{request.reason}</p>
          {request.session_id && (
            <p>
              Jornada actual:{" "}
              {records.find((r) => r.id === request.session_id)?.entry ||
                "Sin entrada"}{" "}
              →{" "}
              {records.find((r) => r.id === request.session_id)?.exit ||
                "Sin salida"}
            </p>
          )}
          <label>
            Motivo de la decisión
            <textarea
              rows={2}
              maxLength={1000}
              value={resolutionNotes[request.id] || ""}
              onChange={(e) =>
                setResolutionNotes((previous) => ({
                  ...previous,
                  [request.id]: e.target.value,
                }))
              }
            />
          </label>
          <div className="title-actions">
            <Button
              variant="danger"
              disabled={busy || !resolutionNotes[request.id]?.trim()}
              onClick={() => void resolveRequest(request.id, false)}
            >
              Rechazar solicitud
            </Button>
            <Button
              disabled={busy || !resolutionNotes[request.id]?.trim()}
              onClick={() => void resolveRequest(request.id, true)}
            >
              Aprobar horarios propuestos
            </Button>
          </div>
        </Card>
      ))}
      <div className="review-summary">
        <Card>
          <span className="summary-icon orange">
            <AlertTriangle size={20} />
          </span>
          <div>
            <strong>{pending.length}</strong>
            <span>Pendientes</span>
          </div>
        </Card>
        <Card>
          <span className="summary-icon green">
            <Check size={20} />
          </span>
          <div>
            <strong>
              {
                records.filter((r) =>
                  ["Aprobado", "Corregido"].includes(r.status),
                ).length
              }
            </strong>
            <span>Aprobados o corregidos</span>
          </div>
        </Card>
      </div>
      <div className="review-list">
        {pending.map((r) => (
          <Card className="review-item" key={r.id}>
            <div className="review-person">
              <div className="avatar">{r.initials}</div>
              <div>
                <h3>{r.employee}</h3>
                <p>
                  {r.date} · {r.institution}
                </p>
              </div>
            </div>
            <div className="review-detail">
              <AlertTriangle size={18} />
              <div>
                <b>{reviewReason(r)}</b>
                <p>
                  Entrada: {r.entry || "Sin registrar"} · Salida:{" "}
                  {r.exit || "Sin registrar"} · Calculado:{" "}
                  {formatMinutes(r.minutes)}
                </p>
                <OvertimeDetail record={r} />
                <p>{r.reason}</p>
              </div>
            </div>
            <div className="review-actions">
              <span>
                Para aprobar se requieren ambos horarios y un período válido.
              </span>
              <div>
                <Button
                  variant="danger"
                  disabled={busy}
                  onClick={() => void resolve(r.id, "Rechazado")}
                >
                  <X size={16} /> Rechazar
                </Button>
                {remote && (
                  <Button
                    variant="secondary"
                    disabled={busy}
                    onClick={() => {
                      setEditing(r.id)
                      setEntry(r.entry || "")
                      setExit(r.exit || "")
                      setNotes("")
                    }}
                  >
                    <Pencil size={16} /> Corregir
                  </Button>
                )}
                <Button
                  disabled={busy || !r.entry || !r.exit || r.exit <= r.entry}
                  onClick={() => void resolve(r.id, "Aprobado")}
                >
                  <Check size={16} /> Aprobar
                </Button>
              </div>
            </div>
            {editing === r.id && (
              <form
                className="correction-form"
                onSubmit={(e) => {
                  e.preventDefault()
                  void resolve(r.id, "Corregido")
                }}
              >
                <fieldset disabled={busy}>
                  <h3>Corregir horarios del {r.date}</h3>
                  <p>
                    Ingresá un período del mismo día. Los fichajes originales no
                    se modifican.
                  </p>
                  <div className="form-grid">
                    <label>
                      Entrada
                      <Input
                        type="time"
                        required
                        value={entry}
                        onChange={(e) => setEntry(e.target.value)}
                      />
                    </label>
                    <label>
                      Salida
                      <Input
                        type="time"
                        required
                        value={exit}
                        onChange={(e) => setExit(e.target.value)}
                      />
                    </label>
                    <label className="full">
                      Motivo de corrección
                      <textarea
                        required
                        maxLength={2000}
                        rows={2}
                        value={notes}
                        onChange={(e) => setNotes(e.target.value)}
                      />
                    </label>
                  </div>
                  <div className="title-actions">
                    <Button
                      type="button"
                      variant="secondary"
                      onClick={() => setEditing(null)}
                    >
                      Cancelar
                    </Button>
                    <Button
                      disabled={
                        busy ||
                        !entry ||
                        !exit ||
                        exit <= entry ||
                        !notes.trim()
                      }
                    >
                      {busy ? "Guardando…" : "Guardar corrección"}
                    </Button>
                  </div>
                </fieldset>
              </form>
            )}
          </Card>
        ))}
        {!pending.length && !requests.length && (
          <Card className="empty-state">
            <Check size={28} />
            <h2>
              {candidates.length ||
              remote?.correctionRequests?.some((r) => r.status === "pending")
                ? "Sin coincidencias"
                : "Todo al día"}
            </h2>
            <p>No hay pendientes para los filtros elegidos.</p>
          </Card>
        )}
      </div>
    </>
  )
}
