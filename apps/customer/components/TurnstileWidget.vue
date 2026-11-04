<script setup lang="ts">
// Cloudflare Turnstile (CAPTCHA) — token ตรวจซ้ำฝั่ง Edge Function เสมอ
const emit = defineEmits<{ token: [value: string] }>()
const config = useRuntimeConfig()
const el = ref<HTMLElement | null>(null)
let widgetId: string | null = null

interface TurnstileApi {
  render: (el: HTMLElement, opts: Record<string, unknown>) => string
  reset: (id: string) => void
  remove: (id: string) => void
}

function api(): TurnstileApi | undefined {
  return (window as unknown as { turnstile?: TurnstileApi }).turnstile
}

function loadScript(): Promise<void> {
  if (api()) return Promise.resolve()
  return new Promise((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>('script[data-turnstile]')
    const script = existing ?? document.createElement('script')
    script.addEventListener('load', () => resolve())
    script.addEventListener('error', () => reject(new Error('turnstile')))
    if (!existing) {
      script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'
      script.async = true
      script.dataset.turnstile = '1'
      document.head.appendChild(script)
    }
  })
}

onMounted(async () => {
  await loadScript()
  if (!el.value || !api()) return
  widgetId = api()!.render(el.value, {
    sitekey: config.public.turnstileSiteKey,
    language: 'th',
    callback: (t: string) => emit('token', t),
    'expired-callback': () => emit('token', ''),
    'error-callback': () => emit('token', ''),
  })
})

onBeforeUnmount(() => {
  if (widgetId && api()) api()!.remove(widgetId)
})

defineExpose({ reset: () => widgetId && api()?.reset(widgetId) })
</script>

<template>
  <div ref="el" class="my-3 min-h-[65px]" />
</template>
