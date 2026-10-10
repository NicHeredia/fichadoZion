import { useAppRecords } from "../app/useAppRecords"

import { useRemoteData } from "../app/DataContext"

import { useEffect, useRef, useState } from "react"

import { Check, Download, LockKeyhole, RotateCcw } from "lucide-react"

import { Button, Card, PageTitle, Select } from "../components/ui"

import { formatMinutes } from "../lib/demo"

import {
  closeMonth,
  exportRecords,
  getClosures,
  type Closure as ClosureSnapshot,
  localDate,
  recordMonth,
  reopenMonth,
  TIME_ZONE,
} from "../lib/records"

export function Closure() {
  const records = useAppRecords()

  const remote = useRemoteData()

  const [busy, setBusy] = useState(false)

  const lock = useRef(false)

  const [reopenReason, setReopenReason] = useState("")

  const [month, setMonth] = useState(localDate().slice(0, 7))

  const [error, setError] = useState("")

  const [version, setVersion] = useState(0)

  void version

  useEffect(() => {
    const refresh = (event: StorageEvent) => {
      if (event.key === "horaclara-closures-v1" || event.key === null)
        setVersion((v) => v + 1)
    }
    window.addEventListener("storage", refresh)
    return () => window.removeEventListener("storage", refresh)
  }, [])

  let closure: ClosureSnapshot | undefined

  let readError = ""

  try {
    closure = (remote?.closures ?? getClosures())[month]
  } catch (failure) {
    readError =
      failure instanceof Error ? failure.message : "No se pudo leer el cierre."
  }

  const selected =
    closure?.records ?? records.filter((r) => recordMonth(r) === month)

  const accepted = selected.filter((r) => r.status !== "Rechazado")

  const pending = selected.filter((r) => r.status === "Pendiente").length

  const pendingRequests =
    remote?.correctionRequests?.filter(
      (r) => r.status === "pending" && r.work_date.slice(0, 7) === month,
    ).length || 0

  const total = accepted.reduce((sum, r) => sum + r.minutes, 0)

  async function changeClosure() {
    if (lock.current) return
    lock.current = true
    setBusy(true)

    try {
      if (remote) {
        if (closure) await remote.reopen(month, reopenReason)
        else await remote.close(month)
      } else {
        if (closure) reopenMonth(month)
        else closeMonth(month)
      }
      setReopenReason("")
      setError("")
      setVersion((v) => v + 1)
    } catch (failure) {
      setError(
        failure instanceof Error
          ? failure.message
          : "No se pudo guardar el cierre.",
      )
    } finally {
      lock.current = false
      setBusy(false)
    }
  }

  return (
    <>
      <PageTitle
        title="Cierre mensual"
        subtitle={
          remote
            ? "Cierre del período con copia de los registros, bloqueo de cambios y auditoría."
            : "Cierre local de demostración. Guarda una copia de los registros y bloquea cambios del período."
        }
        action={
          <Select
            disabled={busy}
            aria-label="Período"
            value={month}
            onChange={(e) => {
              setMonth(e.target.value)
              setError("")
            }}
          >
            {[
              ...new Set([
                localDate().slice(0, 7),
                ...records.map(recordMonth),
                ...Object.keys(remote?.closures ?? {}),
              ]),
            ]
              .filter(Boolean)
              .sort()
              .reverse()
              .map((m) => (
                <option key={m}>{m}</option>
              ))}
          </Select>
        }
      />
      {(error || readError) && (
        <p className="error-banner" role="alert">
          {error || readError}
        </p>
      )}
      <div className={closure ? "closure-banner closed" : "closure-banner"}>
        <LockKeyhole size={23} />
        <div>
          <h2>{closure ? "Período cerrado" : "Período abierto"}</h2>
          <p>
            {closure
              ? "Cerrado el " +
                new Date(closure.closedAt).toLocaleString("es-AR", {
                  timeZone: TIME_ZONE,
                })
              : pending +
                " registros pendientes y " +
                pendingRequests +
                " solicitudes de corrección. Deben resolverse antes de cerrar."}
          </p>
        </div>
      </div>
      <div className="closure-stats">
        <Card>
          <span>Empleados con actividad</span>
          <strong>
            {new Set(selected.map((r) => r.employeeId || r.employee)).size}
          </strong>
        </Card>
        <Card>
          <span>Horas calculadas</span>
          <strong>{formatMinutes(total)}</strong>
        </Card>
        <Card>
          <span>Registros</span>
          <strong>{selected.length}</strong>
        </Card>
        <Card>
          <span>Pendientes</span>
          <strong>{pending}</strong>
        </Card>
      </div>
      <Card className="table-card">
        <div className="card-head">
          <h2>Resumen por empleado</h2>
          <Button
            variant="secondary"
            disabled={!selected.length}
            onClick={() => exportRecords(selected, "cierre-" + month + ".csv")}
          >
            <Download size={16} /> Exportar
          </Button>
        </div>
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Empleado</th>
                <th>Registros</th>
                <th>Horas calculadas</th>
                <th>Pendientes</th>
              </tr>
            </thead>
            <tbody>
              {[
                ...new Set(selected.map((r) => r.employeeId || r.employee)),
              ].map((id) => {
                const own = selected.filter(
                  (r) => (r.employeeId || r.employee) === id,
                )
                return (
                  <tr key={id}>
                    <td>{own[0]?.employee}</td>
                    <td>{own.length}</td>
                    <td>
                      {formatMinutes(
                        own
                          .filter((r) => r.status !== "Rechazado")
                          .reduce((sum, r) => sum + r.minutes, 0),
                      )}
                    </td>
                    <td>
                      {own.filter((r) => r.status === "Pendiente").length}
                    </td>
                  </tr>
                )
              })}
              {!selected.length && (
                <tr>
                  <td colSpan={4}>No hay registros en este período.</td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </Card>
      <Card className="close-action">
        <div>
          <LockKeyhole size={22} />
          <div>
            <h3>{closure ? "Reabrir período" : "Confirmar cierre"}</h3>
            <p>
              {remote
                ? "El cierre bloquea fichajes y revisiones del período. La reapertura requiere un motivo y queda auditada."
                : "El cierre se guarda únicamente en este navegador."}
            </p>
          </div>
        </div>
        {closure && remote && (
          <label className="reopen-reason">
            Motivo de reapertura
            <textarea
              value={reopenReason}
              disabled={busy}
              onChange={(e) => setReopenReason(e.target.value)}
              maxLength={2000}
              required
              rows={2}
            />
          </label>
        )}
        <Button
          disabled={
            busy ||
            !!readError ||
            (!!closure && !!remote && !reopenReason.trim()) ||
            (!closure &&
              (pending > 0 || pendingRequests > 0 || !selected.length))
          }
          onClick={() => void changeClosure()}
        >
          {closure ? <RotateCcw size={16} /> : <Check size={16} />}
          {busy
            ? "Guardando…"
            : closure
              ? "Reabrir período"
              : "Confirmar cierre mensual"}
        </Button>
      </Card>
    </>
  )
}

export default Closure
