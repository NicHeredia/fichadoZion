import { createContext, useContext } from "react";
import type { Employee, WorkRecord } from "../lib/demo";
import type { SettingsData } from "../lib/settings";
import type { Closure } from "../lib/records";

export type AppEmployee = Employee & { profileId?: string; employeeNumber?: string; appRole?: "admin" | "employee" };
export type TimeEvent = { id: string; employeeId: string; institution: string; kind: "Entrada" | "Salida"; occurredAt: string; reason: string; notes: string | null };
export type AuditEvent = { id: string; action: string; entity_type: string; created_at: string; actor_name: string };
export type RemoteData = {
  profile: { id: string; name: string; role: "admin" | "employee"; employeeId: string; employeeNumber: string; active: boolean };
  records: WorkRecord[];
  employees: AppEmployee[];
  events: TimeEvent[];
  settings: SettingsData;
  institutions: { id: string; name: string }[];
  closures: Record<string, Closure>;
  audit: AuditEvent[];
};
export type RemoteContextValue = RemoteData & {
  refreshing: boolean;
  syncError: string;
  refresh: () => Promise<void>;
  logout: () => Promise<void>;
  punch: (input: { kind: "Entrada" | "Salida"; institution: string; reason: string; notes: string }) => Promise<void>;
  review: (id: string, status: "Aprobado" | "Rechazado" | "Corregido", entry?: string, exit?: string, notes?: string) => Promise<void>;
  saveSettings: (settings: SettingsData) => Promise<void>;
  close: (month: string) => Promise<void>;
  reopen: (month: string, reason: string) => Promise<void>;
  saveEmployee: (employee: AppEmployee) => Promise<void>;
};
export const DataContext = createContext<RemoteContextValue | null>(null);
export function useRemoteData() { return useContext(DataContext); }
