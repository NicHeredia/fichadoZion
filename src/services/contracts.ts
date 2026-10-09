import type { Employee, WorkRecord } from "../lib/demo";

export interface AuthService {
  signIn(user: string, password: string): Promise<{ userId: string; role: "admin" | "employee" }>;
  signOut(): Promise<void>;
}

export interface EmployeeService {
  list(): Promise<Employee[]>;
  get(id: string): Promise<Employee | null>;
}

export interface TimeEventService {
  list(filters?: { employeeId?: string; month?: string }): Promise<WorkRecord[]>;
  register(input: Omit<WorkRecord, "id" | "minutes" | "status">): Promise<WorkRecord>;
}

export interface ReportService {
  monthly(employeeId: string, year: number, month: number): Promise<WorkRecord[]>;
}
