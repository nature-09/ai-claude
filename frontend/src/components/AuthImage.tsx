import { useEffect, useState } from 'react';
import { fetchFileBlob } from '../api';

export default function AuthImage({ id, alt, onClick }: { id: number; alt: string; onClick?: () => void }) {
  const [src, setSrc] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let url: string | null = null;
    let cancelled = false;
    fetchFileBlob(id)
      .then((blob) => {
        if (cancelled) return;
        url = URL.createObjectURL(blob);
        setSrc(url);
      })
      .catch(() => !cancelled && setFailed(true));
    return () => {
      cancelled = true;
      if (url) URL.revokeObjectURL(url);
    };
  }, [id]);

  if (failed) return <div className="image-placeholder">이미지를 불러올 수 없습니다</div>;
  if (!src) return <div className="image-placeholder">불러오는 중...</div>;
  return <img className="chat-image" src={src} alt={alt} onClick={onClick} />;
}
