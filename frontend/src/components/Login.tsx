import { FormEvent, useState } from 'react';
import { api } from '../api';
import type { User } from '../types';
import { requestNotificationPermission } from '../util';

export default function Login({ onLogin }: { onLogin: (token: string, user: User) => void }) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setBusy(true);
    requestNotificationPermission();
    try {
      const res = await api.post<{ token: string; user: User }>('/api/auth/login', { username, password });
      onLogin(res.token, res.user);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="login-screen">
      <form className="login-card" onSubmit={submit}>
        <div className="login-logo">
          <img src="/favicon.svg" alt="" width={48} height={48} />
          <h1>사내 메신저</h1>
        </div>
        <label>
          아이디
          <input value={username} onChange={(e) => setUsername(e.target.value)} autoFocus autoComplete="username" />
        </label>
        <label>
          비밀번호
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            autoComplete="current-password"
          />
        </label>
        {error && <div className="error">{error}</div>}
        <button className="btn primary" disabled={busy || !username || !password}>
          {busy ? '로그인 중...' : '로그인'}
        </button>
      </form>
    </div>
  );
}
