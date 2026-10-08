export interface User {
  id: number;
  username: string;
  name: string;
  email: string | null;
  phone: string | null;
  position: string | null;
  departmentId: number | null;
  departmentName: string | null;
  role: 'USER' | 'ADMIN';
  statusMessage: string | null;
  active: boolean;
}

export interface Department {
  id: number;
  name: string;
  parentId: number | null;
  sortOrder: number;
}

export interface Attachment {
  id: number;
  name: string;
  contentType: string;
  size: number;
}

export interface Message {
  id: number;
  roomId: number;
  senderId: number | null;
  senderName: string | null;
  type: 'TEXT' | 'IMAGE' | 'FILE' | 'SYSTEM';
  content: string | null;
  attachment: Attachment | null;
  deleted: boolean;
  createdAt: string;
}

export interface Member {
  userId: number;
  name: string;
  position: string | null;
  departmentName: string | null;
  lastReadMessageId: number;
}

export interface Room {
  id: number;
  type: 'DIRECT' | 'GROUP';
  name: string;
  members: Member[];
  lastMessage: Message | null;
  lastMessageAt: string;
  unreadCount: number;
}

export interface SearchResult {
  message: Message;
  roomName: string;
}

export type ServerEvent =
  | { type: 'MESSAGE'; data: { message: Message } }
  | { type: 'READ'; data: { roomId: number; userId: number; lastReadMessageId: number } }
  | { type: 'ROOM_UPDATED'; data: { roomId: number } }
  | { type: 'ROOM_LEFT'; data: { roomId: number } }
  | { type: 'MESSAGE_DELETED'; data: { roomId: number; messageId: number } }
  | { type: 'PRESENCE'; data: { userId: number; online: boolean } };
