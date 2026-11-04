import '@mdi/font/css/materialdesignicons.css'
import 'vuetify/styles'
import { createVuetify } from 'vuetify'
import { th } from 'vuetify/locale'

export default defineNuxtPlugin((nuxtApp) => {
  const vuetify = createVuetify({
    ssr: true,
    locale: { locale: 'th', messages: { th } },
    theme: {
      defaultTheme: 'ifeew',
      themes: {
        ifeew: {
          dark: false,
          colors: {
            background: '#FBF6EE',
            surface: '#FFFDF9',
            primary: '#A9805B',
            secondary: '#E8B4B8',
            success: '#7FAE7A',
            info: '#8AAFC4',
            warning: '#D9A55B',
            error: '#C4645C',
            'on-primary': '#FFFFFF',
          },
        },
      },
    },
    defaults: {
      VBtn: { rounded: 'lg', size: 'large', class: 'touch-target' },
      VCard: { rounded: 'xl', elevation: 0, class: 'shadow-soft' },
      VTextField: { variant: 'outlined', rounded: 'lg', density: 'comfortable' },
      VSelect: { variant: 'outlined', rounded: 'lg', density: 'comfortable' },
    },
  })
  nuxtApp.vueApp.use(vuetify)
})
