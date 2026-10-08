import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { api } from '../api';
import { onEvent, onStatus } from '../realtime';
import type { Room, ServerEvent, User } from '../types';
import { messagePreview, notify } from '../util';
import Avatar from './Avatar';
import RoomList from './RoomList';
import ChatRoom from './ChatRoom';
import OrgChart from './OrgChart';
import SearchPanel from './SearchPanel';
import AdminPanel from './AdminPanel';
import ProfileModal from './ProfileModal';
import UserPickerModal from './UserPickerModal';
import UserCard from './UserCard';

type Tab = 'chats' | 'org' | 'search' | 'admin';

function sortRooms(rooms: Room[]): Room[] {
  return [...rooms].sort((a, b) => b.lastMessageAt.localeCompare(a.lastMessageAt));
}

export default function Messenger({
  me,
  setMe,
  onLogout,
}: {
  me: User;
  setMe: (u: User) => void;
  onLogout: () => void;
}) {
  const [tab, setTab] = useState<Tab>('chats');
  const [rooms, setRooms] = useState<Room[]>([]);
  const [online, setOnline] = useState<Set<number>>(new Set());
  const [activeRoomId, setActiveRoomId] = useState<number | null>(null);
  const [connected, setConnected] = useState(false);
  const [showProfile, setShowProfile] = useState(false);
  const [showNewGroup, setShowNewGroup] = useState(false);
  const [userCardId, setUserCardId] = useState<number | null>(null);
  const [jumpTo, setJumpTo] = useState<{ roomId: number; messageId: number } | null>(null);

  const activeRef = useRef<number | null>(null);
  activeRef.current = activeRoomId;
  const roomsRef = useRef<Room[]>([]);
  roomsRef.current = rooms;

  const loadRooms = useCallback(() => {
    api.get<Room[]>('/api/rooms').then((r) => setRooms(sortRooms(r)));
  }, []);

  const loadPresence = useCallback(() => {
    api.get<number[]>('/api/presence').then((ids) => setOnline(new Set(ids)));
  }, []);

  const upsertRoom = useCallback((room: Room) => {
    setRooms((prev) => sortRooms([...prev.filter((r) => r.id !== room.id), room]));
  }, []);

  const refreshRoom = useCallback(
    (roomId: number) => {
      api
        .get<Room>(`/api/rooms/${roomId}`)
        .then(upsertRoom)
        .catch(() => undefined);
    },
    [upsertRoom],
  );

  useEffect(() => {
    loadRooms();
    loadPresence();
  }, [loadRooms, loadPresence]);

  // 재연결 시 놓친 이벤트 보정
  useEffect(
    () =>
      onStatus((c) => {
        setConnected(c);
        if (c) {
          loadRooms();
          loadPresence();
        }
      }),
    [loadRooms, loadPresence],
  );

  useEffect(
    () =>
      onEvent((event: ServerEvent) => {
        switch (event.type) {
          case 'MESSAGE': {
            const m = event.data.message;
            const known = roomsRef.current.find((r) => r.id === m.roomId);
            if (!known) {
              refreshRoom(m.roomId);
            }
            const isMine = m.senderId === me.id;
            const viewing = activeRef.current === m.roomId && document.visibilityState === 'visible';
            setRooms((prev) =>
              sortRooms(
                prev.map((r) =>
                  r.id === m.roomId
                    ? {
                        ...r,
                        lastMessage: m,
                        lastMessageAt: m.createdAt,
                        unreadCount:
                          isMine || viewing || m.type === 'SYSTEM' ? r.unreadCount : r.unreadCount + 1,
                      }
                    : r,
                ),
              ),
            );
            if (!isMine && m.type !== 'SYSTEM' && !viewing) {
              const roomName = known?.name ?? m.senderName ?? '';
              const title = known?.type === 'GROUP' ? `${m.senderName} (${roomName})` : (m.senderName ?? '새 메시지');
              notify(title, messagePreview(m), () => {
                setTab('chats');
                setActiveRoomId(m.roomId);
              });
            }
            break;
          }
          case 'READ': {
            const { roomId, userId, lastReadMessageId } = event.data;
            setRooms((prev) =>
              prev.map((r) =>
                r.id === roomId
                  ? {
                      ...r,
                      unreadCount: userId === me.id ? 0 : r.unreadCount,
                      members: r.members.map((mem) =>
                        mem.userId === userId ? { ...mem, lastReadMessageId } : mem,
                      ),
                    }
                  : r,
              ),
            );
            break;
          }
          case 'ROOM_UPDATED':
            refreshRoom(event.data.roomId);
            break;
          case 'ROOM_LEFT':
            setRooms((prev) => prev.filter((r) => r.id !== event.data.roomId));
            if (activeRef.current === event.data.roomId) setActiveRoomId(null);
            break;
          case 'MESSAGE_DELETED':
            setRooms((prev) =>
              prev.map((r) =>
                r.id === event.data.roomId && r.lastMessage?.id === event.data.messageId
                  ? { ...r, lastMessage: { ...r.lastMessage, deleted: true, content: null } }
                  : r,
              ),
            );
            break;
          case 'PRESENCE':
            setOnline((prev) => {
              const next = new Set(prev);
              if (event.data.online) next.add(event.data.userId);
              else next.delete(event.data.userId);
              return next;
            });
            break;
        }
      }),
    [me.id, refreshRoom],
  );

  const totalUnread = useMemo(() => rooms.reduce((s, r) => s + r.unreadCount, 0), [rooms]);
  useEffect(() => {
    document.title = totalUnread > 0 ? `(${totalUnread}) 사내 메신저` : '사내 메신저';
  }, [totalUnread]);

  const openDirect = async (userId: number) => {
    const room = await api.post<Room>('/api/rooms/direct', { userId });
    upsertRoom(room);
    setUserCardId(null);
    setTab('chats');
    setActiveRoomId(room.id);
  };

  const createGroup = async (ids: number[], name: string) => {
    const room = await api.post<Room>('/api/rooms/group', { name, memberIds: ids });
    upsertRoom(room);
    setShowNewGroup(false);
    setTab('chats');
    setActiveRoomId(room.id);
  };

  // 모바일에서는 목록과 대화방이 한 화면을 공유하므로 탭 이동 시 대화방을 닫는다
  const selectTab = (t: Tab) => {
    setTab(t);
    if (window.matchMedia('(max-width: 760px)').matches) setActiveRoomId(null);
  };

  const activeRoom = rooms.find((r) => r.id === activeRoomId) ?? null;

  const markRoomRead = useCallback((roomId: number) => {
    setRooms((prev) => prev.map((r) => (r.id === roomId && r.unreadCount ? { ...r, unreadCount: 0 } : r)));
  }, []);

  return (
    <div className={`app ${activeRoom && tab !== 'admin' ? 'has-active-room' : ''}`}>
      <nav className="nav-rail">
        <button className={`nav-btn ${tab === 'chats' ? 'active' : ''}`} onClick={() => selectTab('chats')} title="채팅">
          <span className="nav-icon">💬</span>
          {totalUnread > 0 && <span className="badge">{totalUnread > 99 ? '99+' : totalUnread}</span>}
        </button>
        <button className={`nav-btn ${tab === 'org' ? 'active' : ''}`} onClick={() => selectTab('org')} title="조직도">
          <span className="nav-icon">👥</span>
        </button>
        <button
          className={`nav-btn ${tab === 'search' ? 'active' : ''}`}
          onClick={() => selectTab('search')}
          title="메시지 검색"
        >
          <span className="nav-icon">🔍</span>
        </button>
        {me.role === 'ADMIN' && (
          <button
            className={`nav-btn ${tab === 'admin' ? 'active' : ''}`}
            onClick={() => selectTab('admin')}
            title="관리자"
          >
            <span className="nav-icon">⚙️</span>
          </button>
        )}
        <div className="nav-spacer" />
        <span className={`conn-dot ${connected ? 'on' : 'off'}`} title={connected ? '연결됨' : '연결 끊김 - 재연결 중'} />
        <button className="nav-btn" onClick={() => setShowProfile(true)} title="내 정보">
          <Avatar id={me.id} name={me.name} size={36} />
        </button>
      </nav>

      {tab === 'admin' ? (
        <main className="main-panel admin-main">
          <AdminPanel />
        </main>
      ) : (
        <>
          <aside className="side-panel">
            {tab === 'chats' && (
              <RoomList
                rooms={rooms}
                me={me}
                online={online}
                activeRoomId={activeRoomId}
                onSelect={setActiveRoomId}
                onNewGroup={() => setShowNewGroup(true)}
              />
            )}
            {tab === 'org' && <OrgChart me={me} online={online} onSelectUser={setUserCardId} />}
            {tab === 'search' && (
              <SearchPanel
                onSelect={(roomId, messageId) => {
                  setActiveRoomId(roomId);
                  setJumpTo({ roomId, messageId });
                }}
              />
            )}
          </aside>
          <main className="main-panel">
            {activeRoom ? (
              <ChatRoom
                key={activeRoom.id}
                room={activeRoom}
                me={me}
                online={online}
                jumpToMessageId={jumpTo?.roomId === activeRoom.id ? jumpTo.messageId : null}
                onBack={() => setActiveRoomId(null)}
                onRead={markRoomRead}
                onShowUser={setUserCardId}
                onRoomChange={upsertRoom}
              />
            ) : (
              <div className="empty-main">
                <img src="/favicon.svg" alt="" width={64} height={64} />
                <p>대화방을 선택하거나 조직도에서 대화 상대를 찾아보세요.</p>
              </div>
            )}
          </main>
        </>
      )}

      {showProfile && (
        <ProfileModal me={me} onUpdated={setMe} onClose={() => setShowProfile(false)} onLogout={onLogout} />
      )}
      {showNewGroup && (
        <UserPickerModal
          title="그룹 채팅 만들기"
          me={me}
          withRoomName
          excludeIds={[me.id]}
          onClose={() => setShowNewGroup(false)}
          onConfirm={createGroup}
        />
      )}
      {userCardId !== null && (
        <UserCard
          userId={userCardId}
          me={me}
          online={online.has(userCardId)}
          onClose={() => setUserCardId(null)}
          onChat={openDirect}
        />
      )}
    </div>
  );
}
