import { FormEvent, useState } from 'react';
import { api } from '../api';
import type { User } from '../types';
import Modal from './Modal';
import { requestNotificationPermission } from '../util';

export default function ProfileModal({
  me,
  onUpdated,
  onClose,
  onLogout,
}: {
  me: User;
  onUpdated: (u: User) => void;
  onClose: () => void;
  onLogout: () => void;
}) {
  const [statusMessage, setStatusMessage] = useState(me.statusMessage ?? '');
  const [phone, setPhone] = useState(me.phone ?? '');
  const [email, setEmail] = useState(me.email ?? '');
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [newPassword2, setNewPassword2] = useState('');
  const [msg, setMsg] = useState('');
  const [error, setError] = useState('');
  const notifState = 'Notification' in window ? Notification.permission : 'unsupported';

  const saveProfile = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setMsg('');
    try {
      onUpdated(await api.patch<User>('/api/users/me', { statusMessage, phone, email }));
      setMsg('저장되었습니다.');
    } catch (err) {
      setError((err as Error).message);
    }
  };

  const changePassword = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setMsg('');
    if (newPassword !== newPassword2) {
      setError('새 비밀번호가 일치하지 않습니다.');
      return;
    }
    try {
      await api.post('/api/users/me/password', { currentPassword, newPassword });
      setCurrentPassword('');
      setNewPassword('');
      setNewPassword2('');
      setMsg('비밀번호가 변경되었습니다.');
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <Modal title="내 정보" onClose={onClose}>
      <div className="profile-summary">
        <strong>{me.name}</strong> ({me.username}) · {me.departmentName ?? '부서 없음'} {me.position ?? ''}
      </div>
      <form onSubmit={saveProfile} className="form">
        <label className="field">
          상태 메시지
          <input value={statusMessage} onChange={(e) => setStatusMessage(e.target.value)} maxLength={100} />
        </label>
        <label className="field">
          연락처
          <input value={phone} onChange={(e) => setPhone(e.target.value)} maxLength={30} />
        </label>
        <label className="field">
          이메일
          <input value={email} onChange={(e) => setEmail(e.target.value)} maxLength={100} />
        </label>
        <button className="btn primary">저장</button>
      </form>
      <hr />
      <form onSubmit={changePassword} className="form">
        <label className="field">
          현재 비밀번호
          <input type="password" value={currentPassword} onChange={(e) => setCurrentPassword(e.target.value)} autoComplete="current-password" />
        </label>
        <label className="field">
          새 비밀번호 (8자 이상)
          <input type="password" value={newPassword} onChange={(e) => setNewPassword(e.target.value)} autoComplete="new-password" />
        </label>
        <label className="field">
          새 비밀번호 확인
          <input type="password" value={newPassword2} onChange={(e) => setNewPassword2(e.target.value)} autoComplete="new-password" />
        </label>
        <button className="btn" disabled={!currentPassword || !newPassword}>
          비밀번호 변경
        </button>
      </form>
      <hr />
      <div className="row-between">
        <span className="muted">
          데스크톱 알림:{' '}
          {notifState === 'granted' ? '허용됨' : notifState === 'denied' ? '차단됨 (브라우저 설정에서 허용)' : notifState === 'unsupported' ? '미지원 (HTTPS 필요)' : '미설정'}
        </span>
        {notifState === 'default' && (
          <button className="btn small" onClick={requestNotificationPermission}>
            알림 허용
          </button>
        )}
      </div>
      {msg && <div className="success">{msg}</div>}
      {error && <div className="error">{error}</div>}
      <div className="modal-actions">
        <button className="btn danger" onClick={onLogout}>
          로그아웃
        </button>
      </div>
    </Modal>
  );
}
