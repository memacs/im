import type { im } from "../protocol/codec";

export type ConnStatus =
  | "idle"
  | "connecting"
  | "connected"
  | "authenticating"
  | "authenticated"
  | "reconnecting"
  | "kicked"
  | "disconnected"
  | "error";

export type PushEvent = {
  ts: number;
  cmd: number;
  kind: string;
  summary: string;
};

type State = {
  status: ConnStatus;
  auth?: im.protocol.IAuthResp;
  messages: im.protocol.IChatMessage[];
  lastAck?: im.protocol.IMsgAck;
  inboxSeq: number;
  pushEvents: PushEvent[];
  lastError?: { code: number; msg: string; refCmd?: number; refCid?: string };
};

let state: State = { status: "idle", messages: [], inboxSeq: 0, pushEvents: [] };
const listeners = new Set<() => void>();

function emit() {
  listeners.forEach((l) => l());
}

export const connectionStore = {
  snapshot: state,
  subscribe(fn: () => void) {
    listeners.add(fn);
    return () => listeners.delete(fn);
  },
  getSnapshot(): State {
    return state;
  },
  setStatus(status: ConnStatus) {
    state = { ...state, status };
    connectionStore.snapshot = state;
    emit();
  },
  setAuth(auth: im.protocol.IAuthResp) {
    state = { ...state, auth };
    connectionStore.snapshot = state;
    emit();
  },
  addMessage(msg: im.protocol.IChatMessage) {
    state = {
      ...state,
      messages: [msg, ...state.messages].slice(0, 500),
      inboxSeq: Math.max(state.inboxSeq, Number(msg.inboxSeq ?? 0)),
    };
    connectionStore.snapshot = state;
    emit();
  },
  noteAck(ack: im.protocol.IMsgAck) {
    state = { ...state, lastAck: ack };
    connectionStore.snapshot = state;
    emit();
  },
  setInboxSeq(seq: number) {
    state = { ...state, inboxSeq: seq };
    connectionStore.snapshot = state;
    emit();
  },
  clearMessages() {
    state = { ...state, messages: [] };
    connectionStore.snapshot = state;
    emit();
  },
  addPushEvent(ev: Omit<PushEvent, "ts">) {
    state = {
      ...state,
      pushEvents: [{ ...ev, ts: Date.now() }, ...state.pushEvents].slice(0, 100),
    };
    connectionStore.snapshot = state;
    emit();
  },
  setLastError(err: State["lastError"]) {
    state = { ...state, lastError: err };
    connectionStore.snapshot = state;
    emit();
  },
  clearPushEvents() {
    state = { ...state, pushEvents: [] };
    connectionStore.snapshot = state;
    emit();
  },
};
