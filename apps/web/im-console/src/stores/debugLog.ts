export type DebugEntry = {
  ts: number;
  dir: "in" | "out";
  cmd: number;
  seq: number;
  bytes: number;
  note?: string;
};

const MAX = 200;
const entries: DebugEntry[] = [];
const listeners = new Set<() => void>();

export function pushDebug(partial: Omit<DebugEntry, "ts">) {
  entries.unshift({ ...partial, ts: Date.now() });
  if (entries.length > MAX) entries.length = MAX;
  listeners.forEach((l) => l());
}

export function getDebugEntries() {
  return entries;
}

export function subscribeDebug(fn: () => void) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function clearDebug() {
  entries.length = 0;
  listeners.forEach((l) => l());
}
