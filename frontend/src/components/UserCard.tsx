import { useEffect, useState } from 'react';
import { api } from '../api';
import type { User } from '../types';
import Avatar from './Avatar';
import Modal from './Modal';

export default function UserCard({
  userId,
  me,
  online,
  onClose,
  onChat,
}: {
  userId: number;
  me: User;
  online: boolean;
  onClose: () => void;
  onChat: (userId: number) => void;
}) {
  const [user, setUser] = useState<User | null>(null);
  useEffect(() => {
    api.get<User>(`/api/users/${userId}`).then(setUser);
  }, [userId]);

  return (
    <Modal title="프로필" onClose={onClose}>
      {user ? (
        <div className="profile-card">
          <Avatar id={user.id} name={user.name} size={72} online={online} />
          <h3>
            {user.name} {user.position && <span className="position">{user.position}</span>}
          </h3>
          {user.statusMessage && <p className="status-message">{user.statusMessage}</p>}
          <dl>
            <dt>부서</dt>
            <dd>{user.departmentName ?? '-'}</dd>
            <dt>아이디</dt>
            <dd>{user.username}</dd>
            <dt>이메일</dt>
            <dd>{user.email ?? '-'}</dd>
            <dt>연락처</dt>
            <dd>{user.phone ?? '-'}</dd>
          </dl>
          <button className="btn primary block" onClick={() => onChat(user.id)}>
            {user.id === me.id ? '나와의 채팅' : '1:1 채팅'}
          </button>
        </div>
      ) : (
        <div className="muted">불러오는 중...</div>
      )}
    </Modal>
  );
}
