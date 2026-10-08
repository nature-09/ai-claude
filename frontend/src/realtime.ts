import { Client } from '@stomp/stompjs';
import type { ServerEvent } from './types';

type Listener = (event: ServerEvent) => void;
type StatusListener = (connected: boolean) => void;

const listeners = new Set<Listener>();
const statusListeners = new Set<StatusListener>();
let client: Client | null = null;

export function onEvent(fn: Listener): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function onStatus(fn: StatusListener): () => void {
  statusListeners.add(fn);
  return () => statusListeners.delete(fn);
}

function emit(body: string) {
  try {
    const event = JSON.parse(body) as ServerEvent;
    listeners.forEach((l) => l(event));
  } catch (e) {
    console.error('잘못된 이벤트', e);
  }
}

export function connect(token: string) {
  disconnect();
  const scheme = location.protocol === 'https:' ? 'wss' : 'ws';
  client = new Client({
    brokerURL: `${scheme}://${location.host}/ws`,
    connectHeaders: { Authorization: `Bearer ${token}` },
    reconnectDelay: 3000,
    heartbeatIncoming: 10000,
    heartbeatOutgoing: 10000,
    onConnect: () => {
      client?.subscribe('/user/queue/events', (m) => emit(m.body));
      client?.subscribe('/topic/events', (m) => emit(m.body));
      statusListeners.forEach((l) => l(true));
    },
    onWebSocketClose: () => statusListeners.forEach((l) => l(false)),
    onStompError: (frame) => console.warn('STOMP error', frame.headers.message),
  });
  client.activate();
}

export function disconnect() {
  if (client) {
    client.deactivate();
    client = null;
  }
}
