import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig(({ mode }) => ({
  // Capacitor loads assets from the app bundle; GitHub Pages uses a repository subpath.
  base: mode === 'capacitor' ? './' : '/MITHAQ/',
  plugins: [react()],
  server: { host: '0.0.0.0' },
}))
