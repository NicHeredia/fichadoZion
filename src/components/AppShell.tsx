import { useAppRecords } from "../app/useAppRecords";
import { useRemoteData } from "../app/DataContext";
import { useState } from "react";
import { NavLink, Navigate, Outlet, useLocation, useNavigate } from "react-router";
import {
  Bell, Building2, CalendarCheck, Clock3, FileBarChart, History, LayoutDashboard,
  Menu, Search, Settings, ShieldCheck, Users, X,
} from "lucide-react";

const nav = [
  { label: "Dashboard", path: "/", icon: LayoutDashboard },
  { label: "Registrar fichaje", path: "/registrar", icon: Clock3 },
  { label: "Empleados", path: "/empleados", icon: Users },
  { label: "Historial", path: "/historial", icon: History },
  { label: "Revisiones", path: "/revisiones", icon: ShieldCheck },
  { label: "Reportes", path: "/reportes", icon: FileBarChart },
  { label: "Cierre mensual", path: "/cierre", icon: CalendarCheck },
  { label: "Instituciones", path: "/instituciones", icon: Building2 },
  { label: "Auditoría", path: "/auditoria", icon: ShieldCheck },
  { label: "Configuración", path: "/configuracion", icon: Settings },
];

export function AppShell() {
  const records = useAppRecords();
  const remote = useRemoteData();
  const admin = !remote || remote.profile.role === "admin";
  const visibleNav = nav.filter(item => (admin || ["/", "/registrar", "/historial", "/reportes"].includes(item.path)) && (item.path !== "/auditoria" || !!remote));
  const name = remote?.profile.name || "Mariana Gómez";
  const initials = name.split(" ").map(part => part[0]).slice(0,2).join("").toUpperCase();
  const [sessionError, setSessionError] = useState("");
  const [signingOut, setSigningOut] = useState(false);
  async function logout() { if (!remote || signingOut) return; setSigningOut(true); setSessionError(""); try { await remote.logout(); } catch { setSessionError("No se pudo cerrar la sesión. Intentá nuevamente."); } finally { setSigningOut(false); } }
  const pendingCount = records.filter(r => r.status === "Pendiente").length;
  const [open, setOpen] = useState(false);
  const location = useLocation();
  const navigate = useNavigate();
  const [search, setSearch] = useState("");
  const current = nav.find((item) => item.path === location.pathname)?.label ?? "Dashboard";
  return (
    <div className="app-shell">
      {open && <div className="mobile-overlay" onClick={() => setOpen(false)} />}
      <aside className={open ? "sidebar sidebar-open" : "sidebar"}>
        <div className="brand">
          <div className="brand-mark"><Clock3 size={21} /></div>
          <div><strong>Fichado Zion ortopedia</strong><small>Control de horas extras</small></div>
          <button className="icon-button sidebar-close" onClick={() => setOpen(false)} aria-label="Cerrar menú"><X size={19} /></button>
        </div>
        <div className="workspace"><span>ORGANIZACIÓN</span><div className="workspace-row"><div className="mini-logo">ZO</div><div><b>Zion ortopedia</b><small>{admin ? "Administración" : "Mi panel"}</small></div></div></div>
        <nav>
          {visibleNav.map(({ label, path, icon: Icon }) => (
            <NavLink to={path} end={path === "/"} onClick={() => setOpen(false)} key={path} className={({ isActive }) => isActive ? "nav-item active" : "nav-item"}>
              <Icon size={18} /><span>{label}</span>{path === "/revisiones" && pendingCount > 0 && <em>{pendingCount}</em>}
            </NavLink>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="demo-note"><ShieldCheck size={16} /><div><b>{remote ? "Conectado a Supabase" : "Modo demostración"}</b><span>{remote ? "Datos guardados en el servidor" : "Datos almacenados localmente"}</span></div></div>
          <div className="user-card"><div className="avatar">{initials}</div><div><b>{name}</b><span>{admin ? "Administrador" : "Empleado"}</span></div></div>
          {remote && <button className="btn btn-secondary logout-button" disabled={signingOut} onClick={() => void logout()}>{signingOut ? "Cerrando…" : "Cerrar sesión"}</button>}
        </div>
      </aside>
      <main className="main">
        <header className="topbar">
          <div className="mobile-head"><button className="icon-button" aria-label="Abrir menú" onClick={() => setOpen(true)}><Menu size={20} /></button><b>{current}</b></div>
          <div className="search"><Search size={17} /><input aria-label="Buscar en el historial" placeholder="Buscar fichajes y presionar Enter..." value={search} onChange={e => setSearch(e.target.value)} onKeyDown={e => { if (e.key === "Enter") navigate("/historial?q=" + encodeURIComponent(search)); }} /></div>
          <div className="top-actions"><span className="live-dot">{remote ? "Conectado" : "Demo activo"}</span>{remote && <button className="btn btn-secondary" disabled={remote.refreshing} onClick={() => void remote.refresh()}>{remote.refreshing ? "Actualizando…" : "Actualizar"}</button>}<button className="icon-button notification" aria-label="Ver revisiones pendientes" onClick={() => navigate(admin ? "/revisiones" : "/historial")}><Bell size={19} />{pendingCount > 0 && <i />}</button><div className="avatar small">{initials}</div></div>
        </header>
        <div className="content">{(sessionError || remote?.syncError) && <p className="error-banner" role="alert">{sessionError || remote?.syncError}</p>}{remote && !remote.profile.active && <p className="error-banner" role="alert">Tu legajo está inactivo. Podés consultar tus registros, pero no fichar. Contactá al administrador.</p>}{!admin && !visibleNav.some(item => item.path === location.pathname) ? <Navigate to="/" replace /> : <Outlet />}</div>
      </main>
    </div>
  );
}

export default AppShell;
