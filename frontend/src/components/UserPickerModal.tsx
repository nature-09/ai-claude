import { useEffect, useState } from 'react';
import { api } from '../api';
import type { User } from '../types';
import Avatar from './Avatar';
import Modal from './Modal';

export default function UserPickerModal({
  title,
  me,
  excludeIds,
  withRoomName,
  onClose,
  onConfirm,
}: {
  title: string;
  me: User;
  excludeIds: number[];
  withRoomName?: boolean;
  onClose: () => void;
  onConfirm: (ids: number[], roomName: string) => Promise<void>;
}) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<User[]>([]);
  const [selected, setSelected] = useState<User[]>([]);
  const [roomName, setRoomName] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    const q = query.trim();
    if (!q) {
      setResults([]);
      return;
    }
    const t = setTimeout(() => api.get<User[]>(`/api/users?q=${encodeURIComponent(q)}`).then(setResults), 250);
    return () => clearTimeout(t);
  }, [query]);

  const toggle = (u: User) =>
    setSelected((prev) => (prev.some((s) => s.id === u.id) ? prev.filter((s) => s.id !== u.id) : [...prev, u]));

  const confirm = async () => {
    setBusy(true);
    setError('');
    try {
      await onConfirm(
        selected.map((u) => u.id),
        roomName,
      );
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Modal title={title} onClose={onClose}>
      {withRoomName && (
        <label className="field">
          대화방 이름 (선택)
          <input value={roomName} onChange={(e) => setRoomName(e.target.value)} maxLength={100} />
        </label>
      )}
      <div className="chips">
        {selected.map((u) => (
          <span key={u.id} className="chip" onClick={() => toggle(u)}>
            {u.name} ✕
          </span>
        ))}
        {selected.length === 0 && <span className="muted">대화상대를 검색해서 선택하세요.</span>}
      </div>
      <input
        className="full"
        placeholder="이름, 아이디, 직급 검색"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        autoFocus
      />
      <ul className="list picker-list">
        {results
          .filter((u) => !excludeIds.includes(u.id) && u.id !== me.id)
          .map((u) => {
            const checked = selected.some((s) => s.id === u.id);
            return (
              <li key={u.id} className={`list-item ${checked ? 'active' : ''}`} onClick={() => toggle(u)}>
                <input type="checkbox" readOnly checked={checked} />
                <Avatar id={u.id} name={u.name} size={32} />
                <div className="list-item-body">
                  <span className="list-item-title">
                    {u.name} {u.position && <span className="position">{u.position}</span>}
                  </span>
                  <span className="list-item-sub">{u.departmentName}</span>
                </div>
              </li>
            );
          })}
      </ul>
      {error && <div className="error">{error}</div>}
      <div className="modal-actions">
        <button className="btn" onClick={onClose}>
          취소
        </button>
        <button className="btn primary" disabled={selected.length === 0 || busy} onClick={confirm}>
          확인 ({selected.length})
        </button>
      </div>
    </Modal>
  );
}
