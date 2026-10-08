import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// 로컬 개발 시 백엔드(8080)로 프록시. 운영(OCP)에서는 Route 의 path 기반 라우팅으로 분기한다.
const backend = process.env.BACKEND_URL ?? 'http://localhost:8080';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': backend,
      '/ws': { target: backend.replace(/^http/, 'ws'), ws: true },
    },
  },
});
