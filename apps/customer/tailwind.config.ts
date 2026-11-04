// Tailwind v3 config (ใช้ผ่าน @nuxtjs/tailwindcss)

// Tailwind ใช้จัดระยะและ Layout เท่านั้น ปิด preflight เพื่อไม่ชนกับ reset ของ Vuetify
export default {
  corePlugins: { preflight: false },
  content: ['./components/**/*.vue', './layouts/**/*.vue', './pages/**/*.vue', './app.vue'],
  theme: {
    extend: {
      colors: {
        cream: '#FBF6EE',
        'warm-white': '#FFFDF9',
        beige: '#EFE3D3',
        'soft-pink': '#F4D6D6',
        'pastel-green': '#D7E9D3',
        'light-brown': '#A9805B',
        cocoa: '#5B4636',
      },
      borderRadius: { card: '20px' },
      boxShadow: { soft: '0 6px 24px rgba(91, 70, 54, 0.08)' },
      fontFamily: { sans: ['"Noto Sans Thai"', '"Prompt"', 'system-ui', 'sans-serif'] },
    },
  },
}
