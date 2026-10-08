export function formatTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleTimeString('ko-KR', { hour: 'numeric', minute: '2-digit' });
}

export function formatRoomTime(iso: string): string {
  const d = new Date(iso);
  const now = new Date();
  if (d.toDateString() === now.toDateString()) return formatTime(iso);
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  if (d.toDateString() === yesterday.toDateString()) return '어제';
  return d.toLocaleDateString('ko-KR', { month: 'numeric', day: 'numeric' });
}

export function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('ko-KR', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    weekday: 'long',
  });
}

export function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(1)} GB`;
}

export function messagePreview(m: { type: string; content: string | null; deleted: boolean } | null): string {
  if (!m) return '';
  if (m.deleted) return '삭제된 메시지입니다.';
  if (m.type === 'IMAGE') return '사진';
  if (m.type === 'FILE') return `파일: ${m.content ?? ''}`;
  return m.content ?? '';
}

export function initials(name: string): string {
  return name ? name.slice(0, 2) : '?';
}

/** 이름 기반 아바타 색상 */
export function avatarColor(seed: number | string): string {
  const colors = ['#2563eb', '#0891b2', '#059669', '#7c3aed', '#db2777', '#ea580c', '#4f46e5', '#0d9488'];
  const n = typeof seed === 'number' ? seed : [...seed].reduce((a, c) => a + c.charCodeAt(0), 0);
  return colors[Math.abs(n) % colors.length];
}

export function notify(title: string, body: string, onClick?: () => void) {
  if (!('Notification' in window) || Notification.permission !== 'granted') return;
  const n = new Notification(title, { body, icon: '/favicon.svg', tag: title });
  n.onclick = () => {
    window.focus();
    onClick?.();
    n.close();
  };
}

export function requestNotificationPermission() {
  if ('Notification' in window && Notification.permission === 'default') {
    Notification.requestPermission().catch(() => undefined);
  }
}
