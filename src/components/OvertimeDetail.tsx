import type { WorkRecord } from "../lib/demo"
import { formatMinutes } from "../lib/demo"
import { effectiveTimes, overtimeDetail } from "../lib/work-details"

export default function OvertimeDetail({ record: r }: { record: WorkRecord }) {
  const detail = overtimeDetail(r)
  const times = effectiveTimes(r)
  return (
    <details className="overtime-detail">
      <summary
        aria-label={`Ver cálculo de ${formatMinutes(r.minutes)} horas extra del ${r.date}`}
      >
        {formatMinutes(r.minutes)}
      </summary>
      <div>
        <strong>Detalle del cálculo</strong>
        <p>
          Fichaje: {times.entry || "Sin entrada"} → {times.exit || "Sin salida"}
        </p>
        <p>
          {r.workingDay === false
            ? "Día no laboral: se cuenta todo el período."
            : r.scheduleStart && r.scheduleEnd
              ? `Jornada aplicada: ${r.scheduleStart} a ${r.scheduleEnd}`
              : "Jornada histórica no disponible."}
        </p>
        {detail ? (
          r.workingDay === false ? (
            <p>Período completo: {formatMinutes(detail.full)}</p>
          ) : (
            <>
              <p>Antes de la jornada: {formatMinutes(detail.before)}</p>
              <p>Después de la jornada: {formatMinutes(detail.after)}</p>
            </>
          )
        ) : (
          <p>No hay datos suficientes para desglosar el cálculo.</p>
        )}
        {(r.inferredEntry || r.inferredExit) && (
          <p>Incluye un horario inferido.</p>
        )}
        <strong>Total registrado: {formatMinutes(r.minutes)}</strong>
        {r.status === "Rechazado" && <p>Excluido de los totales.</p>}
      </div>
    </details>
  )
}
