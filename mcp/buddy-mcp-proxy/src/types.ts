export interface BuddySession {
  id: string;
  host: string;
  port: number;
  cwd: string;
  label?: string | null;
  pid?: number;
  auth_token?: string | null;
  started_at?: number | string;
  last_seen?: number;
}

export type SessionsRegistryV1 = {
  version?: number;
  sessions: Record<string, Omit<BuddySession, "id">>;
};

export type SessionsRegistryLegacyArray = {
  sessions: BuddySession[];
};

export type SessionSelector = {
  id?: string;
  label?: string;
  cwd?: string;
  index?: number;
};
