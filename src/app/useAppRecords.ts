import { useSyncExternalStore } from "react";
import { isDemoMode } from "../lib/supabase";
import { getRecords, subscribeRecords } from "../lib/records";
import { useRemoteData } from "./DataContext";
import type { WorkRecord } from "../lib/demo";
const empty: WorkRecord[] = [];
const emptySnapshot = () => empty;
const noSubscription = () => () => {};
export function useAppRecords() {
  const remote = useRemoteData();
  const local = useSyncExternalStore(isDemoMode ? subscribeRecords : noSubscription, isDemoMode ? getRecords : emptySnapshot);
  return isDemoMode ? local : remote?.records ?? empty;
}
