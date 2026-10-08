import { FormEvent, useState } from 'react';
import { api } from '../api';
import type { SearchResult } from '../types';
import { formatRoomTime, messagePreview } from '../util';

function highlight(text: string, q: string) {
  if (!q) return text;
  const idx = text.toLowerCase().indexOf(q.toLowerCase());
  if (idx < 0) return text;
  return (
    <>
      {text.slice(0, idx)}
      <mark>{text.slice(idx, idx + q.length)}</mark>
      {text.slice(idx + q.length)}
    </>
  );
}

export default function SearchPanel({ onSelect }: { onSelect: (roomId: number, messageId: number) => void }) {
  const [query, setQuery] = useState('');
  const [searched, setSearched] = useState('');
  const [results, setResults] = useState<SearchResult[] | null>(null);
  const [error, setError] = useState('');

  const search = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    try {
      const q = query.trim();
      setResults(await api.get<SearchResult[]>(`/api/messages/search?q=${encodeURIComponent(q)}`));
      setSearched(q);
    } catch (err) {
      setError((err as Error).message);
    }
  };

  return (
    <div className="panel">
      <div className="panel-header">
        <h2>메시지 검색</h2>
      </div>
      <form className="panel-search" onSubmit={search}>
        <input placeholder="검색어 (2자 이상) 입력 후 Enter" value={query} onChange={(e) => setQuery(e.target.value)} />
      </form>
      {error && <div className="error pad">{error}</div>}
      <ul className="list">
        {results?.length === 0 && <li className="list-empty">검색 결과가 없습니다</li>}
        {results?.map(({ message: m, roomName }) => (
          <li key={m.id} className="list-item" onClick={() => onSelect(m.roomId, m.id)}>
            <div className="list-item-body">
              <div className="list-item-top">
                <span className="list-item-title">{roomName}</span>
                <span className="list-item-time">{formatRoomTime(m.createdAt)}</span>
              </div>
              <span className="list-item-sub wrap">
                <b>{m.senderName}</b>: {highlight(messagePreview(m), searched)}
              </span>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}
