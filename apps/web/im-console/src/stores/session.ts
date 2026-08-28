const DEVICE_KEY = "im_console_device_id";
const SESSION_KEY = "im_console_session";

export type SessionData = {
  appKey: string;
  userId: string;
  accessToken: string;
  websocketUrls: string[];
  deviceId: string;
};

export function getOrCreateDeviceId(): string {
  let id = localStorage.getItem(DEVICE_KEY);
  if (!id) {
    id = crypto.randomUUID();
    localStorage.setItem(DEVICE_KEY, id);
  }
  return id;
}

export function saveSession(data: SessionData) {
  localStorage.setItem(SESSION_KEY, JSON.stringify(data));
}

export function loadSession(): SessionData | null {
  const raw = localStorage.getItem(SESSION_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as SessionData;
  } catch {
    return null;
  }
}

export function clearSession() {
  localStorage.removeItem(SESSION_KEY);
}
