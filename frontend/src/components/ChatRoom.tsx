import { ClipboardEvent, DragEvent, KeyboardEvent, useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { api, downloadFile } from '../api';
import { onEvent, onStatus } from '../realtime';
import type { Message, Room, User } from '../types';
import { formatDate, formatSize, formatTime } from '../util';
import Avatar from './Avatar';
import AuthImage from './AuthImage';
import UserPickerModal from './UserPickerModal';
import Modal from './Modal';

const PAGE = 50;

export default function ChatRoom({
  room,
  me,
  online,
  jumpToMessageId,
  onBack,
  onRead,
  onShowUser,
  onRoomChange,
}: {
  room: Room;
  me: User;
  online: Set<number>;
  jumpToMessageId: number | null;
  onBack: () => void;
  onRead: (roomId: number) => void;
  onShowUser: (userId: number) => void;
  onRoomChange: (room: Room) => void;
}) {
  const [messages, setMessages] = useState<Message[]>([]);
  const [hasMore, setHasMore] = useState(true);
  const [loading, setLoading] = useState(false);
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const [uploading, setUploading] = useState<string | null>(null);
  const [error, setError] = useState('');
  const [dragOver, setDragOver] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [showInvite, setShowInvite] = useState(false);
  const [showMembers, setShowMembers] = useState(false);
  const [highlightId, setHighlightId] = useState<number | null>(null);

  const listRef = useRef<HTMLDivElement>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const stickToBottom = useRef(true);
  const prevScrollHeight = useRef<number | null>(null);
  const lastReadSent = useRef(0);
  const messagesRef = useRef<Message[]>([]);
  messagesRef.current = messages;

  const markRead = useCallback(
    (msgs: Message[]) => {
      if (document.visibilityState !== 'visible' || msgs.length === 0) return;
      const lastId = msgs[msgs.length - 1].id;
      if (lastId <= lastReadSent.current) return;
      lastReadSent.current = lastId;
      onRead(room.id);
      api.post(`/api/rooms/${room.id}/read`, { messageId: lastId }).catch(() => undefined);
    },
    [room.id, onRead],
  );

  const loadLatest = useCallback(async () => {
    const page = await api.get<Message[]>(`/api/rooms/${room.id}/messages?size=${PAGE}`);
    setMessages((prev) => {
      // 기존에 더 과거 메시지를 불러왔다면 유지하면서 병합
      const map = new Map(prev.map((m) => [m.id, m]));
      page.forEach((m) => map.set(m.id, m));
      return [...map.values()].sort((a, b) => a.id - b.id);
    });
    if (page.length < PAGE) setHasMore(false);
    return page;
  }, [room.id]);

  // 최초 로딩 (+ 검색 결과로 이동)
  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        let all = await api.get<Message[]>(`/api/rooms/${room.id}/messages?size=${PAGE}`);
        let more = all.length === PAGE;
        if (jumpToMessageId) {
          let guard = 0;
          while (more && all.length > 0 && all[0].id > jumpToMessageId && guard++ < 20) {
            const older = await api.get<Message[]>(`/api/rooms/${room.id}/messages?before=${all[0].id}&size=100`);
            all = [...older, ...all];
            more = older.length === 100;
          }
        }
        if (cancelled) return;
        setMessages(all);
        setHasMore(more);
        if (jumpToMessageId) {
          stickToBottom.current = false;
          setHighlightId(jumpToMessageId);
        }
        markRead(all);
      } catch (e) {
        if (!cancelled) setError((e as Error).message);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [room.id, jumpToMessageId, markRead]);

  // 실시간 이벤트
  useEffect(() => {
    const offEvent = onEvent((ev) => {
      if (ev.type === 'MESSAGE' && ev.data.message.roomId === room.id) {
        const m = ev.data.message;
        const el = listRef.current;
        if (m.senderId === me.id || (el && el.scrollHeight - el.scrollTop - el.clientHeight < 120)) {
          stickToBottom.current = true;
        }
        setMessages((prev) => (prev.some((x) => x.id === m.id) ? prev : [...prev, m]));
        markRead([m]);
      } else if (ev.type === 'MESSAGE_DELETED' && ev.data.roomId === room.id) {
        setMessages((prev) =>
          prev.map((m) =>
            m.id === ev.data.messageId ? { ...m, deleted: true, content: null, attachment: null } : m,
          ),
        );
      }
    });
    const offStatus = onStatus((c) => {
      if (c) loadLatest().then(markRead).catch(() => undefined);
    });
    const onVisible = () => {
      if (document.visibilityState === 'visible') markRead(messagesRef.current);
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      offEvent();
      offStatus();
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [room.id, me.id, markRead, loadLatest]);

  // 스크롤 위치 관리
  useLayoutEffect(() => {
    const el = listRef.current;
    if (!el) return;
    if (prevScrollHeight.current !== null) {
      el.scrollTop = el.scrollHeight - prevScrollHeight.current;
      prevScrollHeight.current = null;
    } else if (highlightId) {
      document.getElementById(`msg-${highlightId}`)?.scrollIntoView({ block: 'center' });
    } else if (stickToBottom.current) {
      el.scrollTop = el.scrollHeight;
    }
  }, [messages, highlightId]);

  useEffect(() => {
    if (!highlightId) return;
    const t = setTimeout(() => setHighlightId(null), 2500);
    return () => clearTimeout(t);
  }, [highlightId]);

  const loadOlder = async () => {
    if (loading || !hasMore || messages.length === 0) return;
    setLoading(true);
    try {
      const older = await api.get<Message[]>(`/api/rooms/${room.id}/messages?before=${messages[0].id}&size=${PAGE}`);
      if (older.length < PAGE) setHasMore(false);
      prevScrollHeight.current = listRef.current?.scrollHeight ?? null;
      setMessages((prev) => [...older, ...prev]);
    } finally {
      setLoading(false);
    }
  };

  const onScroll = () => {
    const el = listRef.current;
    if (!el) return;
    stickToBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 60;
    if (el.scrollTop < 80) loadOlder();
  };

  const send = async () => {
    const content = text.trim();
    if (!content || sending) return;
    setSending(true);
    setError('');
    try {
      stickToBottom.current = true;
      const m = await api.post<Message>(`/api/rooms/${room.id}/messages`, { content });
      setMessages((prev) => (prev.some((x) => x.id === m.id) ? prev : [...prev, m]));
      setText('');
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setSending(false);
    }
  };

  const upload = async (files: FileList | File[]) => {
    for (const file of Array.from(files)) {
      setUploading(file.name);
      setError('');
      try {
        stickToBottom.current = true;
        const m = await api.upload<Message>(`/api/rooms/${room.id}/files`, file);
        setMessages((prev) => (prev.some((x) => x.id === m.id) ? prev : [...prev, m]));
      } catch (e) {
        setError(`${file.name}: ${(e as Error).message}`);
      } finally {
        setUploading(null);
      }
    }
  };

  const onKeyDown = (e: KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
      e.preventDefault();
      send();
    }
  };

  const onPaste = (e: ClipboardEvent<HTMLTextAreaElement>) => {
    const files = Array.from(e.clipboardData.files);
    if (files.length > 0) {
      e.preventDefault();
      upload(files);
    }
  };

  const onDrop = (e: DragEvent) => {
    e.preventDefault();
    setDragOver(false);
    if (e.dataTransfer.files.length) upload(e.dataTransfer.files);
  };

  const deleteMessage = async (m: Message) => {
    if (!confirm('메시지를 삭제할까요?')) return;
    try {
      await api.del(`/api/messages/${m.id}`);
    } catch (e) {
      setError((e as Error).message);
    }
  };

  const leave = async () => {
    setMenuOpen(false);
    if (!confirm('대화방을 나가시겠습니까? 대화 내용이 목록에서 사라집니다.')) return;
    await api.post(`/api/rooms/${room.id}/leave`);
  };

  const rename = async () => {
    setMenuOpen(false);
    const name = prompt('대화방 이름', room.name);
    if (name === null) return;
    const updated = await api.patch<Room>(`/api/rooms/${room.id}`, { name });
    onRoomChange(updated);
  };

  const invite = async (ids: number[]) => {
    const updated = await api.post<Room>(`/api/rooms/${room.id}/members`, { userIds: ids });
    onRoomChange(updated);
    setShowInvite(false);
  };

  const unreadFor = (m: Message) =>
    room.members.filter((mem) => mem.userId !== m.senderId && mem.lastReadMessageId < m.id).length;

  const other = room.type === 'DIRECT' ? room.members.find((m) => m.userId !== me.id) : undefined;

  return (
    <div
      className={`chat ${dragOver ? 'drag-over' : ''}`}
      onDragOver={(e) => {
        e.preventDefault();
        setDragOver(true);
      }}
      onDragLeave={() => setDragOver(false)}
      onDrop={onDrop}
    >
      <header className="chat-header">
        <button className="icon-btn back-btn" onClick={onBack} aria-label="뒤로">
          ←
        </button>
        <div className="chat-title" onClick={() => (other ? onShowUser(other.userId) : setShowMembers(true))}>
          <strong>{room.name}</strong>
          <span className="chat-subtitle">
            {other
              ? [other.departmentName, other.position, online.has(other.userId) ? '온라인' : '오프라인']
                  .filter(Boolean)
                  .join(' · ')
              : `참여자 ${room.members.length}명`}
          </span>
        </div>
        <div className="menu-wrap">
          <button className="icon-btn" onClick={() => setMenuOpen((o) => !o)} aria-label="메뉴">
            ⋮
          </button>
          {menuOpen && (
            <div className="menu" onMouseLeave={() => setMenuOpen(false)}>
              <button
                onClick={() => {
                  setMenuOpen(false);
                  setShowMembers(true);
                }}
              >
                참여자 보기
              </button>
              {room.type === 'GROUP' && (
                <>
                  <button
                    onClick={() => {
                      setMenuOpen(false);
                      setShowInvite(true);
                    }}
                  >
                    대화상대 초대
                  </button>
                  <button onClick={rename}>대화방 이름 변경</button>
                </>
              )}
              <button className="danger" onClick={leave}>
                나가기
              </button>
            </div>
          )}
        </div>
      </header>

      <div className="messages" ref={listRef} onScroll={onScroll}>
        {loading && <div className="loading-more">불러오는 중...</div>}
        {messages.map((m, i) => {
          const prev = messages[i - 1];
          const newDay = !prev || new Date(prev.createdAt).toDateString() !== new Date(m.createdAt).toDateString();
          const date = newDay ? <div className="date-sep">{formatDate(m.createdAt)}</div> : null;
          if (m.type === 'SYSTEM') {
            return (
              <div key={m.id} id={`msg-${m.id}`}>
                {date}
                <div className="system-msg">{m.content}</div>
              </div>
            );
          }
          const mine = m.senderId === me.id;
          const grouped =
            !newDay &&
            prev &&
            prev.type !== 'SYSTEM' &&
            prev.senderId === m.senderId &&
            new Date(m.createdAt).getTime() - new Date(prev.createdAt).getTime() < 60_000;
          const unread = unreadFor(m);
          return (
            <div key={m.id} id={`msg-${m.id}`}>
              {date}
              <div className={`msg-row ${mine ? 'mine' : ''} ${grouped ? 'grouped' : ''} ${highlightId === m.id ? 'highlight' : ''}`}>
                {!mine && (
                  <div className="msg-avatar" onClick={() => m.senderId && onShowUser(m.senderId)}>
                    {!grouped && <Avatar id={m.senderId ?? 0} name={m.senderName ?? '?'} size={36} />}
                  </div>
                )}
                <div className="msg-content">
                  {!mine && !grouped && <div className="msg-sender">{m.senderName}</div>}
                  <div className="msg-line">
                    <div className={`bubble ${m.deleted ? 'deleted' : ''} ${m.type === 'IMAGE' ? 'image' : ''}`}>
                      {m.deleted ? (
                        '삭제된 메시지입니다.'
                      ) : m.type === 'IMAGE' && m.attachment ? (
                        <AuthImage
                          id={m.attachment.id}
                          alt={m.attachment.name}
                          onClick={() => downloadFile(m.attachment!.id, m.attachment!.name)}
                        />
                      ) : m.type === 'FILE' && m.attachment ? (
                        <button
                          className="file-card"
                          onClick={() => downloadFile(m.attachment!.id, m.attachment!.name).catch((e) => setError(e.message))}
                        >
                          <span className="file-icon">📄</span>
                          <span className="file-info">
                            <span className="file-name">{m.attachment.name}</span>
                            <span className="file-size">{formatSize(m.attachment.size)} · 다운로드</span>
                          </span>
                        </button>
                      ) : (
                        <span className="text">{m.content}</span>
                      )}
                    </div>
                    <div className="msg-meta">
                      {unread > 0 && <span className="unread">{unread}</span>}
                      <span className="time">{formatTime(m.createdAt)}</span>
                      {mine && !m.deleted && (
                        <button className="msg-delete" onClick={() => deleteMessage(m)} title="삭제">
                          삭제
                        </button>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {error && (
        <div className="chat-error" onClick={() => setError('')}>
          {error}
        </div>
      )}
      {uploading && <div className="chat-uploading">업로드 중: {uploading}</div>}

      <footer className="composer">
        <button className="icon-btn" onClick={() => fileRef.current?.click()} title="파일 첨부" aria-label="파일 첨부">
          📎
        </button>
        <input
          ref={fileRef}
          type="file"
          multiple
          hidden
          onChange={(e) => {
            if (e.target.files) upload(e.target.files);
            e.target.value = '';
          }}
        />
        <textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          onKeyDown={onKeyDown}
          onPaste={onPaste}
          placeholder="메시지를 입력하세요 (Enter 전송, Shift+Enter 줄바꿈)"
          rows={1}
          maxLength={10000}
        />
        <button className="btn primary" onClick={send} disabled={!text.trim() || sending}>
          전송
        </button>
      </footer>

      {showInvite && (
        <UserPickerModal
          title="대화상대 초대"
          me={me}
          excludeIds={room.members.map((m) => m.userId)}
          onClose={() => setShowInvite(false)}
          onConfirm={invite}
        />
      )}
      {showMembers && (
        <Modal title={`참여자 ${room.members.length}명`} onClose={() => setShowMembers(false)}>
          <ul className="list">
            {room.members.map((m) => (
              <li
                key={m.userId}
                className="list-item"
                onClick={() => {
                  setShowMembers(false);
                  onShowUser(m.userId);
                }}
              >
                <Avatar id={m.userId} name={m.name} online={online.has(m.userId)} size={36} />
                <div className="list-item-body">
                  <span className="list-item-title">
                    {m.name} {m.userId === me.id && <span className="me-tag">나</span>}
                  </span>
                  <span className="list-item-sub">{[m.departmentName, m.position].filter(Boolean).join(' · ')}</span>
                </div>
              </li>
            ))}
          </ul>
        </Modal>
      )}
    </div>
  );
}
