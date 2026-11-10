import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  // GitHub Pages serves this repository under /MITHAQ/.
  base: '/MITHAQ/',
  plugins: [react()],
  server: { host: '0.0.0.0' },
})
