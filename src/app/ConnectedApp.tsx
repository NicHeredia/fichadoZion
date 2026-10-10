import { useEffect, useRef, useState } from "react"

import type { Session } from "@supabase/supabase-js"

import { useQuery, useQueryClient } from "@tanstack/react-query"

import { RouterProvider } from "react-router"

import { configurationError, supabase } from "../lib/supabase"

import { validateSettings } from "../lib/settings"

import {
  DataContext,
  type RemoteContextValue,
  type RemoteData,
} from "./DataContext"

import { callRpc, loadRemoteData } from "../services/remote"

import { router } from "./routes"

import AuthForm from "../components/AuthForm"
import zionLogo from "../assets/zion-logo.jpg"

function Workspace({
  session,
  logout,
}: {
  session: Session
  logout: () => Promise<void>
}) {
  const request = useRef<{ signature: string; id: string } | null>(null)

  const compensationRequest = useRef<{ signature: string; id: string } | null>(
    null,
  )

  const manualRequest = useRef<{ signature: string; id: string } | null>(null)

  const journeyRequest = useRef<{ signature: string; id: string } | null>(null)

  const correctionRequest = useRef<{ signature: string; id: string } | null>(
    null,
  )

  const query = useQuery({
    queryKey: ["workspace", session.user.id],

    queryFn: loadRemoteData,

    refetchInterval: 30000,

    retry: 1,
  })

  async function refresh() {
    await query.refetch()
  }

  async function mutate(name: string, args: Record<string, unknown>) {
    await callRpc(name, args)

    await refresh()
  }

  if (!query.data)
    return (
      <main className="connected" role={query.isError ? "alert" : "status"}>
        <h1>
          {query.isError
            ? "No se pudo abrir el panel"
            : "Cargando Fichado Zion ortopedia…"}
        </h1>
        {query.isError && (
          <>
            <p>
              {query.error instanceof Error
                ? query.error.message
                : "Revisá la conexión."}
            </p>
            <button className="btn btn-primary" onClick={() => void refresh()}>
              Reintentar
            </button>{" "}
            <button
              className="btn btn-secondary"
              onClick={() => void logout().catch(() => {})}
            >
              Cerrar sesión
            </button>
          </>
        )}
      </main>
    )

  const data = query.data as RemoteData

  const value: RemoteContextValue = {
    ...data,
    refreshing: query.isFetching,

    syncError: query.isError
      ? "No se pudo actualizar el panel. Los datos visibles corresponden a la última consulta correcta."
      : "",

    refresh,
    logout,

    async punch(input) {
      const target = input.targetId ? data.records.find(r => r.id === input.targetId && r.employeeId === data.profile.employeeId) : undefined
      const institution = data.institutions.find(
        (i) => i.name === input.institution,
      )

      const institutionId = target?.institutionId || institution?.id
      if (!institutionId) throw new Error("Elegí una institución habilitada.")
      if (input.kind === "Salida" && !data.specificCheckoutAvailable) throw new Error("Falta habilitar el cierre de entradas en tu organización. Contactá al administrador.")
      if (input.targetId && (!target || target.institution !== input.institution)) throw new Error("La institución debe coincidir con la entrada elegida. Actualizá los datos.")

      const payload = {
        p_event_type: input.kind === "Entrada" ? "entry" : "exit",
        p_institution_id: institutionId,
        p_reason: input.reason.trim(),
        p_notes: input.notes.trim(),
      }

      const checkoutPayload = data.specificCheckoutAvailable ? { p_target: input.targetId || null, p_confirm_without_entry: !!input.confirmWithoutEntry } : {}
      const signature = JSON.stringify([session.user.id, payload, checkoutPayload])

      if (request.current?.signature !== signature)
        request.current = { signature, id: crypto.randomUUID() }

      await callRpc(data.specificCheckoutAvailable ? "register_time_event_v2" : "register_time_event", {
        ...payload,
        ...checkoutPayload,
        p_request_id: request.current.id,
      })

      request.current = null

      await refresh()
    },

    async manualPunch(input) {
      const signature = JSON.stringify(input)

      if (manualRequest.current?.signature !== signature)
        manualRequest.current = { signature, id: crypto.randomUUID() }

      await callRpc("admin_register_manual_event", {
        p_employee: input.employeeId,
        p_event_type: input.kind === "Entrada" ? "entry" : "exit",
        p_institution: input.institutionId,
        p_date: input.date,
        p_time: input.time,
        p_reason: input.reason.trim(),
        p_notes: input.notes.trim(),
        p_request_id: manualRequest.current.id,
        p_target: input.targetId,
      })

      manualRequest.current = null

      await refresh()
    },

    async manualSession(input) {
      const signature = JSON.stringify(input)

      if (journeyRequest.current?.signature !== signature)
        journeyRequest.current = { signature, id: crypto.randomUUID() }

      await callRpc("admin_register_manual_session", {
        p_employee: input.employeeId,
        p_institution: input.institutionId,
        p_date: input.date,
        p_entry: input.entry,
        p_exit: input.exit,
        p_reason: input.reason.trim(),
        p_notes: input.notes.trim(),
        p_request_id: journeyRequest.current.id,
      })

      journeyRequest.current = null

      await refresh()
    },

    async requestCorrection(input) {
      const signature = JSON.stringify(input)

      if (correctionRequest.current?.signature !== signature)
        correctionRequest.current = { signature, id: crypto.randomUUID() }

      await callRpc(data.specificCheckoutAvailable ? "request_session_correction_v2" : "request_session_correction", {
        p_id: correctionRequest.current.id,
        p_session: input.sessionId,
        p_institution: input.institutionId,
        p_date: input.date,
        p_entry: input.institutionOnly ? null : input.entry,
        p_exit: input.institutionOnly ? null : input.exit,
        p_reason: input.reason.trim(),
        ...(data.specificCheckoutAvailable ? { p_institution_only: !!input.institutionOnly } : {}),
      })

      correctionRequest.current = null

      await refresh()
    },

    async resolveCorrection(id, approve, notes) {
      await mutate("admin_resolve_correction", {
        p_id: id,
        p_approve: approve,
        p_notes: notes.trim(),
      })
    },

    async review(id, status, entry, exit, notes) {
      await mutate("admin_review_session", {
        p_id: id,
        p_status:
          status === "Aprobado"
            ? "approved"
            : status === "Rechazado"
              ? "rejected"
              : "corrected",
        p_entry: entry || null,
        p_exit: exit || null,
        p_notes: notes || "",
      })
    },

    async saveSettings(settings) {
      validateSettings(settings)

      await mutate("admin_save_settings", {
        p_start: settings.startsAt,
        p_end: settings.endsAt,
        p_weekdays: settings.weekdays,
        p_institutions: settings.institutions,
        p_holidays: settings.holidays,
      })
    },

    async close(month) {
      await mutate("admin_close_month", { p_month: month + "-01" })
    },

    async reopen(month, reason) {
      await mutate("admin_reopen_month", {
        p_month: month + "-01",
        p_reason: reason,
      })
    },

    async saveEmployee(employee) {
      await mutate("admin_save_employee", {
        p_id: employee.id,
        p_name: employee.name,
        p_number: employee.employeeNumber,
        p_active: employee.status === "Activo",
        p_role: employee.appRole,
      })
    },

    async createCompensation(input) {
      const signature = JSON.stringify(input)

      if (compensationRequest.current?.signature !== signature)
        compensationRequest.current = { signature, id: crypto.randomUUID() }

      await callRpc("admin_create_compensation", {
        p_id: compensationRequest.current.id,
        p_employee: input.employeeId,
        p_minutes: input.minutes,
        p_date: input.restDate,
        p_reason: input.reason.trim(),
        p_status: input.status,
      })

      compensationRequest.current = null

      await refresh()
    },

    async changeCompensation(id, status, reason = "") {
      await mutate("admin_change_compensation", {
        p_id: id,
        p_status: status,
        p_reason: reason.trim(),
      })
    },
  }

  return (
    <DataContext.Provider value={value}>
      <RouterProvider router={router} />
    </DataContext.Provider>
  )
}

export default function ConnectedApp() {
  const [session, setSession] = useState<Session | null>(null)

  const [loading, setLoading] = useState(true)

  const [busy, setBusy] = useState(false)

  const [error, setError] = useState("")

  const lock = useRef(false)

  const userId = useRef<string | null>(null)

  const queryClient = useQueryClient()

  useEffect(() => {
    if (!supabase) {
      setLoading(false)
      return
    }

    let active = true,
      changed = false

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, next) => {
      changed = true

      if (!active) return

      if (userId.current !== (next?.user.id ?? null)) queryClient.clear()

      userId.current = next?.user.id ?? null

      setSession(next)
      setLoading(false)
    })

    supabase.auth
      .getSession()
      .then(({ data, error }) => {
        if (!active || changed) return

        if (error) setError("No se pudo recuperar la sesión.")

        userId.current = data.session?.user.id ?? null

        setSession(data.session)
        setLoading(false)
      })
      .catch(() => {
        if (active) {
          setError("No se pudo recuperar la sesión. Recargá la página.")
          setLoading(false)
        }
      })

    return () => {
      active = false
      subscription.unsubscribe()
    }
  }, [queryClient])

  function authenticated(next: Session) {
    if (userId.current !== next.user.id) queryClient.clear()

    userId.current = next.user.id

    setSession(next)
    setError("")
  }

  async function logout() {
    if (lock.current || !supabase) return

    lock.current = true
    setBusy(true)
    setError("")

    try {
      const { error } = await supabase.auth.signOut()
      if (error) throw error

      queryClient.clear()
      setSession(null)
      userId.current = null
    } catch {
      setError("No se pudo cerrar la sesión. Intentá nuevamente.")
      throw new Error("No se pudo cerrar la sesión.")
    } finally {
      lock.current = false
      setBusy(false)
    }
  }

  if (configurationError || !supabase)
    return (
      <main className="connected">
        <h1>Configuración de Supabase pendiente</h1>
        <p>{configurationError || "Revisá las variables de conexión."}</p>
        <p>Consultá SUPABASE_SETUP.md en el proyecto.</p>
      </main>
    )

  if (loading)
    return (
      <main className="connected" role="status">
        Cargando sesión…
      </main>
    )

  if (session)
    return (
      <>
        <Workspace key={session.user.id} session={session} logout={logout} />
        {error && (
          <p className="auth-error error-banner" role="alert">
            {error}
          </p>
        )}
      </>
    )

  return (
    <main className="auth-page">
      <div className="auth-layout">
      <aside className="auth-brand-panel" aria-label="Zion Cirugías e Implantes">
        <div className="auth-logo-wrap"><img src={zionLogo} alt="Zion — Cirugías e Implantes" className="auth-logo" /></div>
        <div className="auth-brand-copy">
          <span className="auth-eyebrow">PORTAL DEL EQUIPO</span>
          <h1>Tu jornada,<br />en un solo lugar.</h1>
          <p>Registrá tus fichajes, consultá tus horas y seguí tus solicitudes de forma simple.</p>
        </div>
        <div className="auth-brand-footer"><span className="auth-brand-dot" /> Fichado Zion ortopedia</div>
      </aside>
      <div className="auth-form-panel">
      {error && (
        <p className="error-banner" role="alert">
          {error}
        </p>
      )}
      <AuthForm onAuthenticated={authenticated} />
      <p className="auth-page-footer">Zion · Gestión de jornadas y horas extra</p>
      </div>
      </div>
    </main>
  )
}
