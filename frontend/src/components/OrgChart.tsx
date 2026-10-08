import { useEffect, useMemo, useState } from 'react';
import { api } from '../api';
import type { Department, User } from '../types';
import Avatar from './Avatar';

interface TreeNode extends Department {
  children: TreeNode[];
}

function buildTree(depts: Department[]): TreeNode[] {
  const map = new Map<number, TreeNode>();
  depts.forEach((d) => map.set(d.id, { ...d, children: [] }));
  const roots: TreeNode[] = [];
  map.forEach((n) => {
    const parent = n.parentId != null ? map.get(n.parentId) : undefined;
    if (parent) parent.children.push(n);
    else roots.push(n);
  });
  return roots;
}

function UserRow({
  u,
  me,
  online,
  onSelect,
  indent = 0,
}: {
  u: User;
  me: User;
  online: boolean;
  onSelect: (id: number) => void;
  indent?: number;
}) {
  return (
    <li className="list-item" style={indent ? { paddingLeft: indent } : undefined} onClick={() => onSelect(u.id)}>
      <Avatar id={u.id} name={u.name} online={online} size={36} />
      <div className="list-item-body">
        <span className="list-item-title">
          {u.name} {u.position && <span className="position">{u.position}</span>}
          {u.id === me.id && <span className="me-tag">나</span>}
        </span>
        <span className="list-item-sub">{u.statusMessage || u.departmentName || ''}</span>
      </div>
    </li>
  );
}

function DeptNode({
  node,
  depth,
  me,
  online,
  onSelectUser,
}: {
  node: TreeNode;
  depth: number;
  me: User;
  online: Set<number>;
  onSelectUser: (id: number) => void;
}) {
  const [open, setOpen] = useState(false);
  const [users, setUsers] = useState<User[] | null>(null);

  const toggle = () => {
    if (!open && users === null) {
      api.get<User[]>(`/api/departments/${node.id}/users`).then(setUsers);
    }
    setOpen(!open);
  };

  const onlineCount = users?.filter((u) => online.has(u.id)).length;

  return (
    <li>
      <div className="dept-row" style={{ paddingLeft: 12 + depth * 16 }} onClick={toggle}>
        <span className="caret">{open ? '▾' : '▸'}</span>
        <span className="dept-name">{node.name}</span>
        {users && (
          <span className="dept-count">
            {onlineCount}/{users.length}
          </span>
        )}
      </div>
      {open && (
        <ul className="list nested">
          {node.children.map((c) => (
            <DeptNode key={c.id} node={c} depth={depth + 1} me={me} online={online} onSelectUser={onSelectUser} />
          ))}
          {users?.map((u) => (
            <UserRow
              key={u.id}
              u={u}
              me={me}
              online={online.has(u.id)}
              onSelect={onSelectUser}
              indent={28 + depth * 16}
            />
          ))}
          {users?.length === 0 && node.children.length === 0 && (
            <li className="list-empty" style={{ paddingLeft: 28 + depth * 16 }}>
              구성원이 없습니다
            </li>
          )}
        </ul>
      )}
    </li>
  );
}

export default function OrgChart({
  me,
  online,
  onSelectUser,
}: {
  me: User;
  online: Set<number>;
  onSelectUser: (id: number) => void;
}) {
  const [depts, setDepts] = useState<Department[]>([]);
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<User[] | null>(null);

  useEffect(() => {
    api.get<Department[]>('/api/departments').then(setDepts);
  }, []);

  useEffect(() => {
    const q = query.trim();
    if (!q) {
      setResults(null);
      return;
    }
    const t = setTimeout(() => {
      api.get<User[]>(`/api/users?q=${encodeURIComponent(q)}`).then(setResults);
    }, 250);
    return () => clearTimeout(t);
  }, [query]);

  const tree = useMemo(() => buildTree(depts), [depts]);

  return (
    <div className="panel">
      <div className="panel-header">
        <h2>조직도</h2>
        <span className="muted">온라인 {online.size}명</span>
      </div>
      <div className="panel-search">
        <input placeholder="이름, 아이디, 직급 검색" value={query} onChange={(e) => setQuery(e.target.value)} />
      </div>
      <ul className="list">
        <UserRow u={me} me={me} online={online.has(me.id)} onSelect={onSelectUser} />
        {results ? (
          results.length === 0 ? (
            <li className="list-empty">검색 결과가 없습니다</li>
          ) : (
            results.map((u) => <UserRow key={u.id} u={u} me={me} online={online.has(u.id)} onSelect={onSelectUser} />)
          )
        ) : (
          tree.map((n) => <DeptNode key={n.id} node={n} depth={0} me={me} online={online} onSelectUser={onSelectUser} />)
        )}
      </ul>
    </div>
  );
}
