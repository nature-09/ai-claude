import { useCallback, useEffect, useState } from 'react';
import { api, getToken, setToken, setUnauthorizedHandler } from './api';
import { connect, disconnect } from './realtime';
import type { User } from './types';
import Login from './components/Login';
import Messenger from './components/Messenger';

export default function App() {
  const [me, setMe] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  const logout = useCallback(() => {
    setToken(null);
    disconnect();
    setMe(null);
  }, []);

  useEffect(() => {
    setUnauthorizedHandler(logout);
    const token = getToken();
    if (!token) {
      setLoading(false);
      return;
    }
    api
      .get<User>('/api/users/me')
      .then((user) => {
        setMe(user);
        connect(token);
      })
      .catch(() => setToken(null))
      .finally(() => setLoading(false));
  }, [logout]);

  const onLogin = (token: string, user: User) => {
    setToken(token);
    setMe(user);
    connect(token);
  };

  if (loading) return <div className="center-screen">불러오는 중...</div>;
  if (!me) return <Login onLogin={onLogin} />;
  return <Messenger me={me} setMe={setMe} onLogout={logout} />;
}
