import { useEffect, useRef, useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { RouterProvider } from "react-router";
import { configurationError, supabase } from "../lib/supabase";
import { validateSettings } from "../lib/settings";
import { DataContext, type RemoteContextValue, type RemoteData } from "./DataContext";
import { callRpc, loadRemoteData } from "../services/remote";
import { router } from "./routes";
import AuthForm from "../components/AuthForm";

function Workspace({ session, logout }: { session: Session; logout: () => Promise<void> }) {
  const request = useRef<{ signature: string; id: string } | null>(null);
  const query = useQuery({
    queryKey: ["workspace", session.user.id],
    queryFn: loadRemoteData,
    refetchInterval: 30000,
    retry: 1,
  });
  async function refresh() { await query.refetch(); }
  async function mutate(name: string, args: Record<string, unknown>) {
    await callRpc(name, args);
    await refresh();
  }
  if (!query.data) return <main className="connected" role={query.isError ? "alert" : "status"}>
    <h1>{query.isError ? "No se pudo abrir el panel" : "Cargando HoraClara…"}</h1>
    {query.isError && <><p>{query.error instanceof Error ? query.error.message : "Revisá la conexión."}</p><button className="btn btn-primary" onClick={() => void refresh()}>Reintentar</button> <button className="btn btn-secondary" onClick={() => void logout().catch(() => {})}>Cerrar sesión</button></>}
  </main>;
  const data = query.data as RemoteData;
  const value: RemoteContextValue = {
    ...data, refreshing: query.isFetching,
    syncError: query.isError ? "No se pudo actualizar el panel. Los datos visibles corresponden a la última consulta correcta." : "",
    refresh, logout,
    async punch(input) {
      const institution = data.institutions.find(i => i.name === input.institution);
      if (!institution) throw new Error("Elegí una institución habilitada.");
      const payload = { p_event_type: input.kind === "Entrada" ? "entry" : "exit", p_institution_id: institution.id, p_reason: input.reason.trim(), p_notes: input.notes.trim() };
      const signature = JSON.stringify([session.user.id, payload]);
      if (request.current?.signature !== signature) request.current = { signature, id: crypto.randomUUID() };
      await callRpc("register_time_event", { ...payload, p_request_id: request.current.id });
      request.current = null;
      await refresh();
    },
    async review(id, status, entry, exit, notes) {
      await mutate("admin_review_session", { p_id: id, p_status: status === "Aprobado" ? "approved" : status === "Rechazado" ? "rejected" : "corrected", p_entry: entry || null, p_exit: exit || null, p_notes: notes || "" });
    },
    async saveSettings(settings) {
      validateSettings(settings);
      await mutate("admin_save_settings", { p_start: settings.startsAt, p_end: settings.endsAt, p_weekdays: settings.weekdays, p_institutions: settings.institutions, p_holidays: settings.holidays });
    },
    async close(month) { await mutate("admin_close_month", { p_month: month + "-01" }); },
    async reopen(month, reason) { await mutate("admin_reopen_month", { p_month: month + "-01", p_reason: reason }); },
    async saveEmployee(employee) {
      await mutate("admin_save_employee", { p_id: employee.id, p_name: employee.name, p_number: employee.employeeNumber, p_active: employee.status === "Activo", p_role: employee.appRole });
    },
  };
  return <DataContext.Provider value={value}><RouterProvider router={router} /></DataContext.Provider>;
}

export default function ConnectedApp() {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const lock = useRef(false);
  const userId = useRef<string | null>(null);
  const queryClient = useQueryClient();
  useEffect(() => {
    if (!supabase) { setLoading(false); return; }
    let active = true, changed = false;
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, next) => {
      changed = true;
      if (!active) return;
      if (userId.current !== (next?.user.id ?? null)) queryClient.clear();
      userId.current = next?.user.id ?? null;
      setSession(next); setLoading(false);
    });
    supabase.auth.getSession().then(({ data, error }) => {
      if (!active || changed) return;
      if (error) setError("No se pudo recuperar la sesión.");
      userId.current = data.session?.user.id ?? null;
      setSession(data.session); setLoading(false);
    }).catch(() => { if (active) { setError("No se pudo recuperar la sesión. Recargá la página."); setLoading(false); } });
    return () => { active = false; subscription.unsubscribe(); };
  }, [queryClient]);
  function authenticated(next: Session) {
    if (userId.current !== next.user.id) queryClient.clear();
    userId.current = next.user.id;
    setSession(next); setError("");
  }
  async function logout() {
    if (lock.current || !supabase) return;
    lock.current = true; setBusy(true); setError("");
    try {
      const { error } = await supabase.auth.signOut(); if (error) throw error;
      queryClient.clear(); setSession(null); userId.current = null;
    } catch { setError("No se pudo cerrar la sesión. Intentá nuevamente."); throw new Error("No se pudo cerrar la sesión."); }
    finally { lock.current = false; setBusy(false); }
  }
  if (configurationError || !supabase) return <main className="connected"><h1>Configuración de Supabase pendiente</h1><p>{configurationError || "Revisá las variables de conexión."}</p><p>Consultá SUPABASE_SETUP.md en el proyecto.</p></main>;
  if (loading) return <main className="connected" role="status">Cargando sesión…</main>;
  if (session) return <><Workspace key={session.user.id} session={session} logout={logout} />{error && <p className="auth-error error-banner" role="alert">{error}</p>}</>;
  return <main className="connected"><div className="page-title"><div><h1>HoraClara</h1><p>Ingresá o creá tu cuenta para acceder a tu panel</p></div></div>
    {error && <p className="error-banner" role="alert">{error}</p>}
    <AuthForm onAuthenticated={authenticated} />
  </main>;
}
