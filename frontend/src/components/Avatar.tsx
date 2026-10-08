import { avatarColor, initials } from '../util';

export default function Avatar({
  id,
  name,
  online,
  size = 40,
}: {
  id: number | string;
  name: string;
  online?: boolean;
  size?: number;
}) {
  return (
    <div className="avatar" style={{ width: size, height: size, background: avatarColor(id), fontSize: size * 0.36 }}>
      {initials(name)}
      {online !== undefined && <span className={`presence-dot ${online ? 'on' : 'off'}`} />}
    </div>
  );
}
