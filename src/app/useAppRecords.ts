import { useEffect, useSyncExternalStore } from "react";
import { isDemoMode } from "../lib/supabase";
import { finalizeOpenRecords, getRecords, subscribeRecords } from "../lib/records";
import { useRemoteData } from "./DataContext";
import type { WorkRecord } from "../lib/demo";
const empty: WorkRecord[] = [];
const emptySnapshot = () => empty;
const noSubscription = () => () => {};
export function useAppRecords() {
  const remote = useRemoteData();
  useEffect(() => {
    if (!isDemoMode) return;
    const finalize = () => {
      try { finalizeOpenRecords(); }
      catch (error) { console.error("No se pudo completar la salida automática", error); }
    };
    finalize();
    const timer = window.setInterval(finalize, 60000);
    return () => window.clearInterval(timer);
  }, []);
  const local = useSyncExternalStore(isDemoMode ? subscribeRecords : noSubscription, isDemoMode ? getRecords : emptySnapshot);
  return isDemoMode ? local : remote?.records ?? empty;
}
