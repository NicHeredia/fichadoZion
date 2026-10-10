import { useAppRecords } from "../app/useAppRecords"

import { useRemoteData } from "../app/DataContext"

import { useState } from "react"

import { Download, Printer } from "lucide-react"

import { Button, Card, Input, PageTitle, Select } from "../components/ui"

import {
  effectiveTimes,
  needsReview,
  recognized,
  recordDate,
} from "../lib/work-details"

import OvertimeDetail from "../components/OvertimeDetail"

import { formatMinutes } from "../lib/demo"

import { exportRecords, localDate, recordMonth } from "../lib/records"

import { StatusBadge } from "../components/StatusBadge"

import { compensationLabels, exportCompensations } from "../lib/compensations"

export function Reports() {
  const all = useAppRecords()

  const remote = useRemoteData()

  const [employee, setEmployee] = useState(
    remote?.profile.role === "employee"
      ? remote.profile.employeeId
      : remote?.employees[0]?.id || "María González",
  )

  const [month, setMonth] = useState(localDate().slice(0, 7))

  const [institution, setInstitution] = useState("")

  const [from, setFrom] = useState("")

  const [to, setTo] = useState("")

  const invalidRange = !!from && !!to && to < from

  const inPeriod = (date: string) =>
    !invalidRange &&
    (!month || date.slice(0, 7) === month) &&
    (!from || date >= from) &&
    (!to || date <= to)

  const records = all.filter(
    (r) =>
      (remote ? r.employeeId === employee : r.employee === employee) &&
      inPeriod(recordDate(r)) &&
      (!institution || r.institution === institution),
  )

  const accepted = records.filter((r) => r.status !== "Rechazado")

  const total = accepted.reduce((sum, r) => sum + r.minutes, 0)

  const credited = accepted
    .filter(recognized)
    .reduce((sum, r) => sum + r.minutes, 0)

  const pendingMinutes = accepted
    .filter((r) => r.status === "Pendiente")
    .reduce((sum, r) => sum + r.minutes, 0)

  const months = [
    ...new Set([localDate().slice(0, 7), ...all.map(recordMonth)]),
  ]
    .filter(Boolean)
    .sort()
    .reverse()

  const balance = remote?.compensationData?.balances.find(
    (b) => b.employeeId === employee,
  )

  const rests =
    remote?.compensationData?.compensations.filter(
      (c) => c.employeeId === employee && inPeriod(c.restDate),
    ) ?? []

  for (const c of remote?.compensationData?.compensations ?? [])
    if (c.employeeId === employee && !months.includes(c.restDate.slice(0, 7)))
      months.push(c.restDate.slice(0, 7))

  months.sort().reverse()

  return (
    <>
      <PageTitle
        title="Reporte mensual"
        subtitle={
          remote
            ? "Totales calculados en el servidor. Los rechazados no se suman."
            : "Totales calculados a partir del historial local. Los rechazados no se suman."
        }
        action={
          <div className="title-actions">
            <Button variant="secondary" onClick={() => window.print()}>
              <Printer size={16} /> Imprimir
            </Button>
            <Button
              disabled={!records.length}
              onClick={() =>
                exportRecords(records, "reporte-" + month + ".csv")
              }
            >
              <Download size={16} /> Exportar
            </Button>
          </div>
        }
      />
      <Card className="report-selector">
        <div>
          <label>
            Empleado
            <Select
              value={employee}
              onChange={(e) => setEmployee(e.target.value)}
            >
              {remote
                ? remote.employees.map((person) => (
                    <option key={person.id} value={person.id}>
                      {person.name} · {person.employeeNumber}
                    </option>
                  ))
                : [...new Set(all.map((r) => r.employee))].map((name) => (
                    <option key={name}>{name}</option>
                  ))}
            </Select>
          </label>
          <label>
            Período
            <Select value={month} onChange={(e) => setMonth(e.target.value)}>
              <option value="">Todos los períodos</option>
              {months.map((m) => (
                <option key={m}>{m}</option>
              ))}
            </Select>
          </label>
          <label>
            Institución
            <Select
              value={institution}
              onChange={(e) => setInstitution(e.target.value)}
            >
              <option value="">Todas las instituciones</option>
              {[...new Set(all.map((r) => r.institution))].map((i) => (
                <option key={i}>{i}</option>
              ))}
            </Select>
          </label>
          <label>
            Desde
            <Input
              type="date"
              value={from}
              onChange={(e) => {
                setFrom(e.target.value)
                setMonth("")
              }}
            />
          </label>
          <label>
            Hasta
            <Input
              type="date"
              min={from || undefined}
              value={to}
              onChange={(e) => {
                setTo(e.target.value)
                setMonth("")
              }}
            />
          </label>
          <Button
            variant="secondary"
            onClick={() => {
              setMonth(localDate().slice(0, 7))
              setFrom("")
              setTo("")
              setInstitution("")
            }}
          >
            Limpiar filtros
          </Button>
        </div>
        <span>
          {remote
            ? "Datos guardados en Supabase"
            : "Datos de demostración y fichajes locales"}
        </span>
      </Card>
      {invalidRange && (
        <p role="alert" className="error-banner">
          La fecha final debe ser posterior o igual a la inicial.
        </p>
      )}
      <div className="report-head">
        <div>
          <h2>
            {remote?.employees.find((p) => p.id === employee)?.name || employee}
          </h2>
          <p>
            {month || "Todos los períodos"}
            {from && " · Desde " + from}
            {to && " · Hasta " + to}
            {institution && " · " + institution}
          </p>
        </div>
        <div className="report-total">
          <span>Total del período</span>
          <strong>{formatMinutes(total)}</strong>
        </div>
      </div>
      <div className="report-stats">
        <Card>
          <span>Horas calculadas</span>
          <strong>{formatMinutes(total)}</strong>
          <small>{records.length} registros</small>
        </Card>
        <Card>
          <span>Reconocidas para compensación</span>
          <strong className="text-green">{formatMinutes(credited)}</strong>
          <small>
            Automáticas, aprobadas y corregidas. Antes de descontar descansos.
          </small>
        </Card>
        <Card>
          <span>Pendientes sin crédito</span>
          <strong className="text-orange">
            {formatMinutes(pendingMinutes)}
          </strong>
          <small>No generan saldo para descanso.</small>
        </Card>
        <Card>
          <span>Pendientes de revisión</span>
          <strong className="text-orange">
            {records.filter(needsReview).length}
          </strong>
          <small>Incluye horarios inferidos.</small>
        </Card>
      </div>
      {balance && (
        <>
          <div className="report-stats">
            <Card>
              <span>Compensadas en el período</span>
              <strong>
                {formatMinutes(
                  rests
                    .filter((c) => c.status === "completed")
                    .reduce((sum, c) => sum + c.minutes, 0),
                )}
              </strong>
            </Card>
            <Card>
              <span>Reservadas en el período</span>
              <strong>
                {formatMinutes(
                  rests
                    .filter((c) => c.status === "scheduled")
                    .reduce((sum, c) => sum + c.minutes, 0),
                )}
              </strong>
            </Card>
            <Card>
              <span>Saldo disponible acumulado</span>
              <strong className="text-green">
                {formatMinutes(balance.available)}
              </strong>
              <small>
                Todo el historial; descontadas reservas y descansos realizados.
              </small>
            </Card>
          </div>
          <Card className="table-card">
            <div className="card-head">
              <h2>Descansos del período</h2>
              <p>
                Los descansos se filtran por fecha y empleado; no están
                asociados a una institución.
              </p>
              <Button
                variant="secondary"
                disabled={!rests.length}
                onClick={() =>
                  exportCompensations(
                    rests,
                    remote?.employees ?? [],
                    "descansos-" + month + ".csv",
                  )
                }
              >
                Exportar descansos
              </Button>
            </div>
            <div className="table-scroll">
              <table>
                <thead>
                  <tr>
                    <th>Fecha</th>
                    <th>Horas</th>
                    <th>Estado</th>
                    <th>Motivo</th>
                  </tr>
                </thead>
                <tbody>
                  {rests.map((c) => (
                    <tr key={c.id}>
                      <td>{c.restDate.split("-").reverse().join("/")}</td>
                      <td>{formatMinutes(c.minutes)}</td>
                      <td>{compensationLabels[c.status]}</td>
                      <td>
                        {c.reason}
                        {c.cancellationReason && (
                          <small className="sub-cell">
                            Cancelación: {c.cancellationReason}
                          </small>
                        )}
                      </td>
                    </tr>
                  ))}
                  {!rests.length && (
                    <tr>
                      <td colSpan={4}>No hay descansos en este período.</td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </Card>
        </>
      )}
      <Card className="table-card report-table">
        <div className="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Fecha</th>
                <th>Lugar y motivo</th>
                <th>Entrada</th>
                <th>Salida</th>
                <th>Horas extra</th>
                <th>Estado</th>
              </tr>
            </thead>
            <tbody>
              {records.map((r) => (
                <tr key={r.id}>
                  <td>{r.date}</td>
                  <td className="description-cell">
                    {r.institution}
                    <small className="sub-cell">{r.reason}</small>
                  </td>
                  <td>
                    {effectiveTimes(r).entry || "—"}
                    {r.inferredEntry && " *"}
                  </td>
                  <td>
                    {effectiveTimes(r).exit || "—"}
                    {r.inferredExit && " *"}
                  </td>
                  <td>
                    <OvertimeDetail record={r} />
                  </td>
                  <td>
                    <StatusBadge status={r.status} />
                  </td>
                </tr>
              ))}
              {!records.length && (
                <tr>
                  <td colSpan={6}>
                    No hay registros que coincidan con los filtros.
                  </td>
                </tr>
              )}
            </tbody>
            <tfoot>
              <tr>
                <td colSpan={4}>TOTAL (sin rechazados)</td>
                <td>{formatMinutes(total)}</td>
                <td />
              </tr>
            </tfoot>
          </table>
        </div>
        <div className="table-foot">
          * Horario inferido. Las compensaciones se muestran por separado y no
          alteran las horas trabajadas.
        </div>
      </Card>
    </>
  )
}

export default Reports
