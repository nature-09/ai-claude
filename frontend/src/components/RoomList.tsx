import { useMemo, useState } from 'react';
import type { Room, User } from '../types';
import { formatRoomTime, messagePreview } from '../util';
import Avatar from './Avatar';

export default function RoomList({
  rooms,
  me,
  online,
  activeRoomId,
  onSelect,
  onNewGroup,
}: {
  rooms: Room[];
  me: User;
  online: Set<number>;
  activeRoomId: number | null;
  onSelect: (id: number) => void;
  onNewGroup: () => void;
}) {
  const [filter, setFilter] = useState('');
  const filtered = useMemo(() => {
    const q = filter.trim().toLowerCase();
    if (!q) return rooms;
    return rooms.filter(
      (r) => r.name.toLowerCase().includes(q) || r.members.some((m) => m.name.toLowerCase().includes(q)),
    );
  }, [rooms, filter]);

  return (
    <div className="panel">
      <div className="panel-header">
        <h2>채팅</h2>
        <button className="btn small" onClick={onNewGroup}>
          + 그룹 채팅
        </button>
      </div>
      <div className="panel-search">
        <input placeholder="대화방, 참여자 검색" value={filter} onChange={(e) => setFilter(e.target.value)} />
      </div>
      <ul className="list">
        {filtered.length === 0 && <li className="list-empty">대화방이 없습니다. 조직도에서 대화를 시작하세요.</li>}
        {filtered.map((r) => {
          const other = r.type === 'DIRECT' ? r.members.find((m) => m.userId !== me.id) : undefined;
          const avatarId = other?.userId ?? (r.type === 'DIRECT' ? me.id : `g${r.id}`);
          return (
            <li
              key={r.id}
              className={`list-item ${r.id === activeRoomId ? 'active' : ''}`}
              onClick={() => onSelect(r.id)}
            >
              <Avatar
                id={avatarId}
                name={r.name}
                online={other ? online.has(other.userId) : undefined}
              />
              <div className="list-item-body">
                <div className="list-item-top">
                  <span className="list-item-title">
                    {r.name}
                    {r.type === 'GROUP' && <span className="member-count">{r.members.length}</span>}
                  </span>
                  <span className="list-item-time">{formatRoomTime(r.lastMessageAt)}</span>
                </div>
                <div className="list-item-bottom">
                  <span className="list-item-sub">{messagePreview(r.lastMessage)}</span>
                  {r.unreadCount > 0 && (
                    <span className="badge inline">{r.unreadCount > 999 ? '999+' : r.unreadCount}</span>
                  )}
                </div>
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
