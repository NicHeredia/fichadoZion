import { createBrowserRouter } from "react-router";
import { AppShell } from "../components/AppShell";
export const router = createBrowserRouter([
  { path: "/", Component: AppShell, children: [
    { index: true, lazy: async () => ({ Component: (await import("../pages/Dashboard")).default }) },
    { path: "registrar", lazy: async () => ({ Component: (await import("../pages/Register")).default }) },
    { path: "fichaje-manual", lazy: async () => ({ Component: (await import("../pages/ManualPunch")).default }) },
    { path: "empleados", lazy: async () => ({ Component: (await import("../pages/Employees")).default }) },
    { path: "historial", lazy: async () => ({ Component: (await import("../pages/History")).default }) },
    { path: "revisiones", lazy: async () => ({ Component: (await import("../pages/Reviews")).default }) },
    { path: "reportes", lazy: async () => ({ Component: (await import("../pages/Reports")).default }) },
    { path: "compensaciones", lazy: async () => ({ Component: (await import("../pages/Compensations")).default }) },
    { path: "cierre", lazy: async () => ({ Component: (await import("../pages/Closure")).default }) },
    { path: "instituciones", lazy: async () => ({ Component: (await import("../pages/Settings")).default }) },
    { path: "configuracion", lazy: async () => ({ Component: (await import("../pages/Settings")).default }) },
    { path: "auditoria", lazy: async () => ({ Component: (await import("../pages/Audit")).default }) },
    { path: "*", lazy: async () => ({ Component: (await import("../pages/Dashboard")).default }) },
  ] },
]);
