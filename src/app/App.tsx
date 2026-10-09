import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { RouterProvider } from "react-router";
import { router } from "./routes";
import { isDemoMode } from "../lib/supabase";
import { lazy, Suspense } from "react";
const ConnectedApp = lazy(() => import("./ConnectedApp"));

const queryClient = new QueryClient();

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      {isDemoMode ? <RouterProvider router={router} /> : <Suspense fallback={<main className="connected" role="status">Cargando…</main>}><ConnectedApp /></Suspense>}
    </QueryClientProvider>
  );
}
