/** 解析 WebSocket URL（开发态走 Vite 代理）。 */
export function resolveWsUrl(urls: string[]): string {
  if (import.meta.env.DEV) {
    const proto = location.protocol === "https:" ? "wss" : "ws";
    return `${proto}://${location.host}/ws`;
  }
  return (
    urls[0] ||
    `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/ws`
  );
}
