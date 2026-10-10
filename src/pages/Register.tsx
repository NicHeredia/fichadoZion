import { useAppRecords } from "../app/useAppRecords"

import { useRemoteData } from "../app/DataContext"

import { useEffect, useRef, useState } from "react"

import {
  ArrowDownToLine,
  ArrowUpFromLine,
  Check,
  Clock3,
  ShieldCheck,
  X,
} from "lucide-react"

import { Button, Card, Input, PageTitle, Select } from "../components/ui"

import { defaultSettings, getSettings } from "../lib/settings"

import { formatMinutes } from "../lib/demo"

import {
  localDate,
  recordMonth,
  registerPunch,
  TIME_ZONE,
} from "../lib/records"

import { Link } from "react-router"

import { recordDate } from "../lib/work-details"

type Kind = "Entrada" | "Salida"

const clockOptions = {
  timeZone: TIME_ZONE,
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hourCycle: "h23",
} as const

export function Register() {
  const records = useAppRecords()

  const remote = useRemoteData()

  const [busy, setBusy] = useState(false)

  let settings = defaultSettings

  let settingsError = ""

  try {
    settings = remote?.settings ?? getSettings()
  } catch {
    settingsError =
      "No se pudo leer la configuración guardada. Revisala antes de fichar."
  }

  const [now, setNow] = useState(new Date())

  const [kind, setKind] = useState<Kind | null>(null)

  const [captured, setCaptured] = useState(new Date())

  const [institution, setInstitution] = useState(
    settings.institutions[0] || "Otra",
  )

  const [customInstitution, setCustomInstitution] = useState("")

  const [reason, setReason] = useState("")

  const [notes, setNotes] = useState("")

  const [error, setError] = useState("")

  const [success, setSuccess] = useState("")

  const dialogRef = useRef<HTMLDivElement>(null)

  const previousFocus = useRef<HTMLElement | null>(null)

  const submitting = useRef(false)
  const [targetId, setTargetId] = useState("")
  const [confirmWithoutEntry, setConfirmWithoutEntry] = useState(false)

  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 1000)
    return () => window.clearInterval(timer)
  }, [])

  useEffect(() => {
    if (!kind) return

    const previousOverflow = document.body.style.overflow

    document.body.style.overflow = "hidden"

    dialogRef.current?.querySelector<HTMLElement>("button")?.focus()

    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape" && !submitting.current) setKind(null)

      if (event.key === "Tab") {
        const items = dialogRef.current?.querySelectorAll<HTMLElement>(
          "button:not(:disabled), input, select, textarea",
        )

        if (!items?.length) return

        const first = items[0],
          last = items[items.length - 1]

        if (event.shiftKey && document.activeElement === first) {
          event.preventDefault()
          last.focus()
        }

        if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault()
          first.focus()
        }
      }
    }

    document.addEventListener("keydown", onKey)

    return () => {
      document.body.style.overflow = previousOverflow
      document.removeEventListener("keydown", onKey)
      previousFocus.current?.focus()
    }
  }, [kind])

  function open(next: Kind) {
    previousFocus.current = (document.activeElement as HTMLElement)

    if (remote && !settings.institutions.includes(institution))
      setInstitution(settings.institutions[0] || "")

    if (next === "Salida" && openEntries.length === 1)
      setInstitution(openEntries[0].institution)

    setTargetId(next === "Salida" && openEntries.length === 1 ? openEntries[0].id : "")
    setConfirmWithoutEntry(false)

    setCaptured(new Date())
    setError("")
    setSuccess("")
    setKind(next)
  }

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()

    if (!kind || submitting.current) return

    const place = kind === "Salida" && selectedEntry ? selectedEntry.institution :
      !remote && institution === "Otra" ? customInstitution.trim() : institution

    if (!place || !reason.trim()) {
      setError("Completá el lugar y el motivo.")
      return
    }

    submitting.current = true
    setBusy(true)

    try {
      if (settingsError) throw new Error(settingsError)
      if (kind === "Salida") {
        if (openEntries.length && !selectedEntry) throw new Error("Elegí la entrada que querés cerrar. Actualizá los datos si ya no aparece.")
        if (!openEntries.length && targetId) throw new Error("La entrada elegida ya no está abierta. Actualizá los datos.")
        if (!openEntries.length && !confirmWithoutEntry) throw new Error("Confirmá que querés registrar solo la salida, por una urgencia u otro motivo.")
      }

      if (remote)
        await remote.punch({
          kind,
          institution: place,
          reason: reason.trim(),
          notes: notes.trim(),
          targetId: kind === "Salida" ? selectedEntry?.id || null : null,
          confirmWithoutEntry: kind === "Salida" && !openEntries.length && confirmWithoutEntry,
        })
      else
        registerPunch({
          kind,
          institution: place,
          reason: reason.trim(),
          notes: notes.trim(),
          capturedAt: captured,
          targetId: kind === "Salida" ? selectedEntry?.id || null : null,
          confirmWithoutEntry: kind === "Salida" && !openEntries.length && confirmWithoutEntry,
        })

      setSuccess(
        remote
          ? kind === "Salida" && !selectedEntry ? "Salida guardada con la hora del servidor. Se aplicaron las reglas de tu jornada; los horarios inferidos se indican en el historial." : kind + " guardada correctamente con la hora del servidor."
          : kind +
              " registrada el " +
              captured.toLocaleString("es-AR", { timeZone: TIME_ZONE }),
      )

      setKind(null)
      setReason("")
      setNotes("")
      setCustomInstitution("")
    } catch (failure) {
      setError(
        failure instanceof Error
          ? failure.message
          : "No se pudo guardar el fichaje.",
      )
    } finally {
      submitting.current = false
      setBusy(false)
    }
  }

  const personal = records.filter((r) =>
    remote
      ? r.employeeId === remote.profile.employeeId
      : r.employee === "María González",
  )

  const openEntries = personal.filter(
    (r) =>
      recordDate(r) === localDate(now) &&
      r.entry &&
      !r.exit &&
      r.status === "Pendiente",
  )
  const selectedEntry = openEntries.find(r => r.id === targetId)
  const checkoutBlocked = !!remote && !remote.specificCheckoutAvailable

  const monthly = personal.filter(
    (r) => recordMonth(r) === localDate(now).slice(0, 7),
  )

  const accepted = monthly.filter((r) => r.status !== "Rechazado")

  const total = accepted.reduce((sum, r) => sum + r.minutes, 0)

  const approved = accepted
    .filter((r) => r.status === "Aprobado" || r.status === "Corregido")
    .reduce((sum, r) => sum + r.minutes, 0)

  const latest = personal.find((r) => r.lastEventAt)

  const latestEvent = remote?.events.find(
    (e) => e.employeeId === remote.profile.employeeId,
  )

  return (
    <>
      <PageTitle
        title="Registrar fichaje"
        subtitle={
          remote
            ? "Registrá tus movimientos. La fecha y hora oficial se guardan en el servidor al confirmar."
            : "Registrá movimientos fuera de tu jornada habitual. En demo se guardan en este navegador."
        }
        action={
          remote?.profile.role === "admin" ? (
            <Link className="btn btn-secondary" to="/fichaje-manual">
              Cargar fichaje manual
            </Link>
          ) : undefined
        }
      />
      {settingsError && (
        <p role="alert" className="error-banner">
          {settingsError}
        </p>
      )}
      {openEntries.length > 0 && (
        <Card className="open-entry-banner">
          <div>
            <h3>
              {openEntries.length === 1
                ? "Tenés una entrada abierta"
                : `Tenés ${openEntries.length} entradas abiertas`}
            </h3>
            {openEntries.map((r) => (
              <p key={r.id}>
                Desde las <strong>{r.entry}</strong> en{" "}
                <strong>{r.institution}</strong>
              </p>
            ))}
            {openEntries.length > 1 && (
              <p>
                Elegí la entrada que querés cerrar por su hora y lugar.
              </p>
            )}
          </div>
          <Button
            disabled={
              busy || !!settingsError || (!!remote && !remote.profile.active)
            }
            onClick={() => open("Salida")}
          >
            Registrar salida
          </Button>
        </Card>
      )}
      {success && (
        <div className="success-banner" role="status">
          <span>
            <Check size={18} />
          </span>
          <div>
            <b>{success}</b>
            <p>Podés consultarla en el historial.</p>
          </div>
        </div>
      )}
      <div className="register-layout">
        <Card className="clock-card">
          <div className="employee-summary">
            <div className="avatar large">
              {remote
                ? remote.profile.name
                    .split(" ")
                    .map((p) => p[0])
                    .slice(0, 2)
                    .join("")
                : "MG"}
            </div>
            <div>
              <span>{remote ? "MI FICHAJE" : "EMPLEADO DE DEMOSTRACIÓN"}</span>
              <h2>{remote?.profile.name || "María González"}</h2>
              <p>
                {remote
                  ? "Legajo " + remote.profile.employeeNumber
                  : "Administración · Legajo #0042"}
              </p>
            </div>
          </div>
          <div className="live-clock">
            <p>
              {now.toLocaleDateString("es-AR", {
                timeZone: TIME_ZONE,
                weekday: "long",
                day: "numeric",
                month: "long",
                year: "numeric",
              })}
            </p>
            <strong>{now.toLocaleTimeString("es-AR", clockOptions)}</strong>
            <span>{TIME_ZONE}</span>
          </div>
          <div className="last-movement">
            <div className="status-pulse" />
            <div>
              <span>
                {remote ? "ÚLTIMO MOVIMIENTO" : "ÚLTIMO MOVIMIENTO LOCAL"}
              </span>
              <b>
                {latestEvent
                  ? latestEvent.kind +
                    " · " +
                    new Date(latestEvent.occurredAt).toLocaleString("es-AR", {
                      timeZone: TIME_ZONE,
                    })
                  : latest?.lastEventAt
                    ? (latest.exit ? "Salida" : "Entrada") +
                      " · " +
                      new Date(latest.lastEventAt).toLocaleString("es-AR", {
                        timeZone: TIME_ZONE,
                      })
                    : "Todavía no registraste movimientos"}
              </b>
            </div>
          </div>
          <div className="punch-actions">
            <button
              className="punch-btn entry"
              disabled={
                busy ||
                !!settingsError ||
                (!!remote &&
                  (!remote.profile.active || !settings.institutions.length))
              }
              onClick={() => open("Entrada")}
            >
              <span>
                <ArrowDownToLine size={30} />
              </span>
              <b>REGISTRAR ENTRADA</b>
              <small>Comenzar período extraordinario</small>
            </button>
            <button
              className="punch-btn exit"
              disabled={
                busy ||
                !!settingsError ||
                (!!remote &&
                  (!remote.profile.active || !settings.institutions.length))
              }
              onClick={() => open("Salida")}
            >
              <span>
                <ArrowUpFromLine size={30} />
              </span>
              <b>REGISTRAR SALIDA</b>
              <small>Finalizar período extraordinario</small>
            </button>
          </div>
          <div className="secure-time">
            <ShieldCheck size={16} />{" "}
            {remote
              ? "Hora oficial del servidor. El reloj visible es orientativo."
              : "Demo: hora del dispositivo. La hora oficial requiere Supabase."}
          </div>
        </Card>
        <div className="register-side">
          <Card>
            <h3>
              Tu resumen de{" "}
              {now.toLocaleDateString("es-AR", {
                month: "long",
                timeZone: TIME_ZONE,
              })}
            </h3>
            <div className="mini-stats">
              <div>
                <strong>{formatMinutes(total)}</strong>
                <span>Horas calculadas</span>
              </div>
              <div>
                <strong>{formatMinutes(approved)}</strong>
                <span>Aprobadas o corregidas</span>
              </div>
              <div>
                <strong>
                  {monthly.filter((r) => r.status === "Pendiente").length}
                </strong>
                <span>Registros pendientes</span>
              </div>
            </div>
          </Card>
          <Card className="help-card">
            <Clock3 size={20} />
            <div>
              <h3>¿Cuándo debo fichar?</h3>
              <p>
                La jornada configurada es de {settings.startsAt} a{" "}
                {settings.endsAt}. Al salir, elegí la entrada que querés cerrar;
                se conserva su institución. Si solo registrás la salida por una urgencia
                u otro motivo, se usa la entrada habitual como inferida en días laborales,
                cuando el horario lo permite. Al pasar las 00:00 (hora argentina), una
                entrada sin salida de un día laboral se cierra con la salida
                habitual y queda marcada como inferida. Entradas posteriores a
                ese horario, feriados y movimientos ambiguos necesitan revisión.
              </p>
            </div>
          </Card>
        </div>
      </div>
      {kind && (
        <div
          className="modal-backdrop"
          onClick={(e) => {
            if (e.target === e.currentTarget && !submitting.current)
              setKind(null)
          }}
        >
          <div
            className="modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="punch-title"
            ref={dialogRef}
          >
            <form onSubmit={submit}>
              <fieldset disabled={busy}>
                <div className="modal-head">
                  <div>
                    <span
                      className={
                        kind === "Entrada"
                          ? "modal-icon green"
                          : "modal-icon blue"
                      }
                    >
                      <Clock3 size={21} />
                    </span>
                    <div>
                      <h2 id="punch-title">Registrar {kind.toLowerCase()}</h2>
                      <p>Revisá los datos antes de confirmar.</p>
                    </div>
                  </div>
                  <button
                    type="button"
                    className="icon-button"
                    aria-label="Cerrar"
                    disabled={busy}
                    onClick={() => setKind(null)}
                  >
                    <X size={19} />
                  </button>
                </div>
                <div className="captured-time">
                  <span>
                    {remote
                      ? "Hora orientativa · se confirma en el servidor"
                      : "Fecha y hora capturada"}
                  </span>
                  <b>
                    {captured.toLocaleString("es-AR", { timeZone: TIME_ZONE })}
                  </b>
                </div>
                {error && (
                  <p role="alert" className="error-banner">
                    {error}
                  </p>
                )}
                {kind === "Salida" && checkoutBlocked && <p role="alert" className="error-banner">El cierre de entradas todavía no está habilitado para tu organización. Contactá al administrador.</p>}
                {kind === "Salida" && targetId && !selectedEntry && <p role="alert" className="error-banner">La entrada elegida ya no está abierta. Volvé a abrir el formulario para revisar los movimientos actuales.</p>}
                {kind === "Salida" && openEntries.length > 0 && <>
                  {(openEntries.length > 1 || !selectedEntry) && <label>Entrada a cerrar<Select aria-label="Entrada a cerrar" required value={targetId} onChange={e => { setTargetId(e.target.value); const entry = openEntries.find(r => r.id === e.target.value); if (entry) setInstitution(entry.institution); }}><option value="">Elegí una entrada</option>{openEntries.map(r => <option key={r.id} value={r.id}>{r.entry} · {r.institution}</option>)}</Select></label>}
                  {selectedEntry ? <div className="calculation-preview"><strong>Vas a cerrar tu entrada de las {selectedEntry.entry} en {selectedEntry.institution}.</strong><p>La institución de la salida queda fija.</p>{remote?.specificCheckoutAvailable && <Link to={"/solicitudes?jornada=" + selectedEntry.id}>¿Elegiste mal la institución al entrar? Solicitá una corrección.</Link>}</div> : <p>Elegí una entrada para ver su institución.</p>}
                </>}
                {kind === "Salida" && !openEntries.length && <div className="calculation-preview"><strong>No encontramos una entrada abierta para hoy.</strong><p>Podés registrar solo la salida por una urgencia u otro motivo. En un día laboral se usa la entrada habitual ({settings.startsAt}), marcada como inferida, para calcular las horas extra. Si el día o el horario no permiten inferirla, quedará pendiente de revisión.</p><label className="checkbox-label"><input type="checkbox" checked={confirmWithoutEntry} onChange={e => setConfirmWithoutEntry(e.target.checked)} /> Confirmo registrar solo la salida.</label></div>}
                {(kind === "Entrada" || !openEntries.length) && <label>
                  Institución o lugar
                  <Select
                    value={institution}
                    onChange={(e) => setInstitution(e.target.value)}
                  >
                    {[
                      ...new Set(
                        remote
                          ? settings.institutions
                          : [...settings.institutions, "Otra"],
                      ),
                    ].map((i) => (
                      <option key={i}>{i}</option>
                    ))}
                  </Select>
                </label>}
                {!remote && institution === "Otra" && (kind === "Entrada" || !openEntries.length) && (
                  <label>
                    Nombre del lugar
                    <Input
                      value={customInstitution}
                      onChange={(e) => setCustomInstitution(e.target.value)}
                      required
                      maxLength={150}
                    />
                  </label>
                )}
                <label>
                  Motivo <em>Obligatorio</em>
                  <textarea
                    value={reason}
                    onChange={(e) => setReason(e.target.value)}
                    required
                    maxLength={1000}
                    rows={3}
                  />
                </label>
                <label>
                  Observaciones <small>Opcional</small>
                  <textarea
                    value={notes}
                    onChange={(e) => setNotes(e.target.value)}
                    maxLength={2000}
                    rows={2}
                  />
                </label>
                <div className="modal-actions">
                  <Button
                    type="button"
                    variant="secondary"
                    onClick={() => setKind(null)}
                  >
                    Cancelar
                  </Button>
                  <Button
                    type="submit"
                    disabled={
                      busy ||
                      (kind === "Salida" && (checkoutBlocked || (openEntries.length > 0 ? !selectedEntry : !confirmWithoutEntry || !!targetId))) ||
                      !(selectedEntry?.institution || institution) ||
                      !reason.trim() ||
                      (!remote &&
                        institution === "Otra" &&
                        (kind === "Entrada" || !openEntries.length) &&
                        !customInstitution.trim())
                    }
                  >
                    <Check size={17} />{" "}
                    {busy ? "Guardando…" : "Confirmar " + kind.toLowerCase()}
                  </Button>
                </div>
              </fieldset>
            </form>
          </div>
        </div>
      )}
    </>
  )
}

export default Register
