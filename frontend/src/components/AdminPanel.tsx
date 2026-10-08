import { FormEvent, useCallback, useEffect, useState } from 'react';
import { api } from '../api';
import type { Department, User } from '../types';
import Modal from './Modal';

interface Page<T> {
  content: T[];
  totalElements: number;
  totalPages: number;
  page: number;
}

interface UserForm {
  username: string;
  password: string;
  name: string;
  email: string;
  phone: string;
  position: string;
  departmentId: string;
  role: 'USER' | 'ADMIN';
  active: boolean;
}

const emptyForm: UserForm = {
  username: '',
  password: '',
  name: '',
  email: '',
  phone: '',
  position: '',
  departmentId: '',
  role: 'USER',
  active: true,
};

function UserEditor({
  user,
  depts,
  onClose,
  onSaved,
}: {
  user: User | null;
  depts: Department[];
  onClose: () => void;
  onSaved: () => void;
}) {
  const [form, setForm] = useState<UserForm>(
    user
      ? {
          username: user.username,
          password: '',
          name: user.name,
          email: user.email ?? '',
          phone: user.phone ?? '',
          position: user.position ?? '',
          departmentId: user.departmentId ? String(user.departmentId) : '',
          role: user.role,
          active: user.active,
        }
      : emptyForm,
  );
  const [error, setError] = useState('');
  const set = (k: keyof UserForm, v: string | boolean) => setForm((f) => ({ ...f, [k]: v }));

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    const body = { ...form, departmentId: form.departmentId ? Number(form.departmentId) : null };
    try {
      if (user) {
        await api.put(`/api/admin/users/${user.id}`, body);
        if (form.password) await api.post(`/api/admin/users/${user.id}/reset-password`, { password: form.password });
      } else {
        await api.post('/api/admin/users', body);
      }
      onSaved();
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <Modal title={user ? '사용자 수정' : '사용자 등록'} onClose={onClose}>
      <form className="form grid2" onSubmit={submit}>
        <label className="field">
          아이디 *
          <input value={form.username} onChange={(e) => set('username', e.target.value)} required />
        </label>
        <label className="field">
          {user ? '비밀번호 초기화 (입력 시 변경)' : '비밀번호 * (8자 이상)'}
          <input type="password" value={form.password} onChange={(e) => set('password', e.target.value)} required={!user} autoComplete="new-password" />
        </label>
        <label className="field">
          이름 *
          <input value={form.name} onChange={(e) => set('name', e.target.value)} required />
        </label>
        <label className="field">
          직급
          <input value={form.position} onChange={(e) => set('position', e.target.value)} />
        </label>
        <label className="field">
          부서
          <select value={form.departmentId} onChange={(e) => set('departmentId', e.target.value)}>
            <option value="">(없음)</option>
            {depts.map((d) => (
              <option key={d.id} value={d.id}>
                {d.name}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          권한
          <select value={form.role} onChange={(e) => set('role', e.target.value)}>
            <option value="USER">일반 사용자</option>
            <option value="ADMIN">관리자</option>
          </select>
        </label>
        <label className="field">
          이메일
          <input value={form.email} onChange={(e) => set('email', e.target.value)} />
        </label>
        <label className="field">
          연락처
          <input value={form.phone} onChange={(e) => set('phone', e.target.value)} />
        </label>
        <label className="checkbox">
          <input type="checkbox" checked={form.active} onChange={(e) => set('active', e.target.checked)} /> 활성 계정
        </label>
        {error && <div className="error span2">{error}</div>}
        <div className="modal-actions span2">
          <button type="button" className="btn" onClick={onClose}>
            취소
          </button>
          <button className="btn primary">저장</button>
        </div>
      </form>
    </Modal>
  );
}

function UsersTab({ depts }: { depts: Department[] }) {
  const [q, setQ] = useState('');
  const [page, setPage] = useState(0);
  const [data, setData] = useState<Page<User> | null>(null);
  const [editing, setEditing] = useState<User | null | undefined>(undefined);
  const [importMsg, setImportMsg] = useState('');

  const load = useCallback(() => {
    api.get<Page<User>>(`/api/admin/users?q=${encodeURIComponent(q)}&page=${page}&size=50`).then(setData);
  }, [q, page]);

  useEffect(() => {
    const t = setTimeout(load, 200);
    return () => clearTimeout(t);
  }, [load]);

  const importCsv = async (file: File) => {
    setImportMsg('업로드 중...');
    try {
      const r = await api.upload<{ created: number; skipped: number; errors: string[] }>('/api/admin/users/import', file);
      setImportMsg(
        `등록 ${r.created}명, 중복 건너뜀 ${r.skipped}명` + (r.errors.length ? `\n오류:\n${r.errors.join('\n')}` : ''),
      );
      load();
    } catch (e) {
      setImportMsg((e as Error).message);
    }
  };

  return (
    <div>
      <div className="toolbar">
        <input
          placeholder="이름/아이디 검색"
          value={q}
          onChange={(e) => {
            setQ(e.target.value);
            setPage(0);
          }}
        />
        <div className="toolbar-right">
          <label className="btn">
            CSV 일괄 등록
            <input
              type="file"
              accept=".csv,text/csv"
              hidden
              onChange={(e) => {
                if (e.target.files?.[0]) importCsv(e.target.files[0]);
                e.target.value = '';
              }}
            />
          </label>
          <button className="btn primary" onClick={() => setEditing(null)}>
            + 사용자 등록
          </button>
        </div>
      </div>
      <p className="muted small">
        CSV 형식(UTF-8, 첫 행은 헤더): username,name,password,department,position,email,phone — 없는 부서는 자동 생성됩니다.
      </p>
      {importMsg && <pre className="notice">{importMsg}</pre>}
      <table className="table">
        <thead>
          <tr>
            <th>아이디</th>
            <th>이름</th>
            <th>부서</th>
            <th>직급</th>
            <th>권한</th>
            <th>상태</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {data?.content.map((u) => (
            <tr key={u.id} className={u.active ? '' : 'inactive'}>
              <td>{u.username}</td>
              <td>{u.name}</td>
              <td>{u.departmentName ?? '-'}</td>
              <td>{u.position ?? '-'}</td>
              <td>{u.role === 'ADMIN' ? '관리자' : '사용자'}</td>
              <td>{u.active ? '활성' : '비활성'}</td>
              <td>
                <button className="btn small" onClick={() => setEditing(u)}>
                  수정
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
      {data && (
        <div className="pager">
          <button className="btn small" disabled={page === 0} onClick={() => setPage(page - 1)}>
            이전
          </button>
          <span>
            {page + 1} / {Math.max(data.totalPages, 1)} (총 {data.totalElements}명)
          </span>
          <button className="btn small" disabled={page + 1 >= data.totalPages} onClick={() => setPage(page + 1)}>
            다음
          </button>
        </div>
      )}
      {editing !== undefined && (
        <UserEditor
          user={editing}
          depts={depts}
          onClose={() => setEditing(undefined)}
          onSaved={() => {
            setEditing(undefined);
            load();
          }}
        />
      )}
    </div>
  );
}

function DepartmentsTab({ depts, reload }: { depts: Department[]; reload: () => void }) {
  const [name, setName] = useState('');
  const [parentId, setParentId] = useState('');
  const [error, setError] = useState('');

  const run = async (fn: () => Promise<unknown>) => {
    setError('');
    try {
      await fn();
      reload();
    } catch (e) {
      setError((e as Error).message);
    }
  };

  const add = (e: FormEvent) => {
    e.preventDefault();
    run(async () => {
      await api.post('/api/admin/departments', { name, parentId: parentId ? Number(parentId) : null });
      setName('');
    });
  };

  const edit = (d: Department) => {
    const newName = prompt('부서 이름', d.name);
    if (newName === null) return;
    const order = prompt('정렬 순서 (숫자, 작을수록 위)', String(d.sortOrder));
    run(() =>
      api.put(`/api/admin/departments/${d.id}`, {
        name: newName,
        parentId: d.parentId,
        sortOrder: Number(order ?? d.sortOrder) || 0,
      }),
    );
  };

  const move = (d: Department, newParent: string) =>
    run(() =>
      api.put(`/api/admin/departments/${d.id}`, {
        name: d.name,
        parentId: newParent ? Number(newParent) : null,
        sortOrder: d.sortOrder,
      }),
    );

  return (
    <div>
      <form className="toolbar" onSubmit={add}>
        <input placeholder="새 부서 이름" value={name} onChange={(e) => setName(e.target.value)} required />
        <select value={parentId} onChange={(e) => setParentId(e.target.value)}>
          <option value="">(최상위)</option>
          {depts.map((d) => (
            <option key={d.id} value={d.id}>
              {d.name}
            </option>
          ))}
        </select>
        <button className="btn primary">추가</button>
      </form>
      {error && <div className="error">{error}</div>}
      <table className="table">
        <thead>
          <tr>
            <th>부서</th>
            <th>상위 부서</th>
            <th>정렬</th>
            <th />
          </tr>
        </thead>
        <tbody>
          {depts.map((d) => (
            <tr key={d.id}>
              <td>{d.name}</td>
              <td>
                <select value={d.parentId ?? ''} onChange={(e) => move(d, e.target.value)}>
                  <option value="">(최상위)</option>
                  {depts
                    .filter((p) => p.id !== d.id)
                    .map((p) => (
                      <option key={p.id} value={p.id}>
                        {p.name}
                      </option>
                    ))}
                </select>
              </td>
              <td>{d.sortOrder}</td>
              <td className="actions">
                <button className="btn small" onClick={() => edit(d)}>
                  수정
                </button>
                <button
                  className="btn small danger"
                  onClick={() => confirm(`'${d.name}' 부서를 삭제할까요?`) && run(() => api.del(`/api/admin/departments/${d.id}`))}
                >
                  삭제
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export default function AdminPanel() {
  const [tab, setTab] = useState<'users' | 'depts'>('users');
  const [depts, setDepts] = useState<Department[]>([]);
  const loadDepts = useCallback(() => {
    api.get<Department[]>('/api/departments').then(setDepts);
  }, []);
  useEffect(loadDepts, [loadDepts]);

  return (
    <div className="admin">
      <h2>관리자</h2>
      <div className="tabs">
        <button className={tab === 'users' ? 'active' : ''} onClick={() => setTab('users')}>
          사용자 관리
        </button>
        <button className={tab === 'depts' ? 'active' : ''} onClick={() => setTab('depts')}>
          부서 관리
        </button>
      </div>
      {tab === 'users' ? <UsersTab depts={depts} /> : <DepartmentsTab depts={depts} reload={loadDepts} />}
    </div>
  );
}
