<script setup lang="ts">
const supabase = useSupabaseClient()
const user = useSupabaseUser()
const { company, branches, activeBranchId, isOwner, clear } = useAccess()

const drawer = ref(true)

// ล็อกหน้าจออัตโนมัติเมื่อไม่มีการใช้งาน (ค่าจาก company_settings)
const idleMinutes = ref(5)
const { lastActive } = useIdle()
const now = ref(Date.now())
useIntervalFn(() => (now.value = Date.now()), 15_000)
const idle = computed(() => now.value - lastActive.value > idleMinutes.value * 60_000)

watch(
  () => company.value?.company_id,
  async (companyId) => {
    if (!companyId) return
    const { data } = await supabase
      .from('company_settings')
      .select('staff_idle_lock_minutes')
      .eq('company_id', companyId)
      .maybeSingle()
    if (data) idleMinutes.value = data.staff_idle_lock_minutes
  },
  { immediate: true },
)

async function logout(reason?: string) {
  await supabase.auth.signOut()
  clear()
  await navigateTo(reason ? `/login?error=${reason}` : '/login')
}

watch(idle, (isIdle) => {
  if (isIdle && user.value) logout('idle')
})

const menu = computed(() => [
  { title: 'แดชบอร์ด', icon: 'mdi-view-dashboard-outline', to: '/' },
  { title: 'การจอง', icon: 'mdi-calendar-check-outline', to: '/bookings' },
  { title: 'ตารางงาน', icon: 'mdi-calendar-clock-outline', to: '/schedules' },
  { title: 'ลูกค้า', icon: 'mdi-account-heart-outline', to: '/customers' },
  ...(isOwner.value
    ? [
        { title: 'บริการและราคา', icon: 'mdi-spa-outline', to: '/services' },
        { title: 'เตียงและอุปกรณ์', icon: 'mdi-bed-outline', to: '/resources' },
        { title: 'พนักงาน', icon: 'mdi-account-group-outline', to: '/employees' },
        { title: 'สาขา', icon: 'mdi-store-outline', to: '/branches' },
        { title: 'ตั้งค่าบริษัท', icon: 'mdi-cog-outline', to: '/settings' },
        { title: 'ตั้งค่าเครื่อง', icon: 'mdi-tablet-cellphone', to: '/settings/devices' },
      ]
    : []),
])
</script>

<template>
  <v-app>
    <v-navigation-drawer v-model="drawer" color="surface" width="248">
      <div class="px-5 py-6">
        <p class="m-0 text-lg font-semibold text-cocoa">Ifeew's Thaimassage</p>
        <p class="m-0 text-sm text-light-brown">{{ company?.company_name }}</p>
      </div>
      <v-list nav density="comfortable">
        <v-list-item
          v-for="m in menu"
          :key="m.to"
          :to="m.to"
          :prepend-icon="m.icon"
          :title="m.title"
          rounded="lg"
          :exact="m.to === '/' || m.to === '/settings'"
        />
      </v-list>
    </v-navigation-drawer>

    <v-app-bar flat color="background">
      <v-app-bar-nav-icon aria-label="เมนู" @click="drawer = !drawer" />
      <v-select
        v-if="branches.length > 1"
        v-model="activeBranchId"
        :items="branches"
        item-title="name"
        item-value="branch_id"
        label="สาขา"
        hide-details
        class="ml-2 max-w-xs"
      />
      <span v-else class="ml-2 font-medium">{{ branches[0]?.name }}</span>
      <v-spacer />
      <v-chip class="mr-2" :color="isOwner ? 'primary' : 'success'" variant="tonal">
        {{ isOwner ? 'เจ้าของร้าน' : 'พนักงาน' }}
      </v-chip>
      <v-btn variant="text" prepend-icon="mdi-logout" class="mr-2" @click="logout()">ออกจากระบบ</v-btn>
    </v-app-bar>

    <v-main>
      <div class="p-6">
        <slot />
      </div>
    </v-main>

    <StepUpDialog />
  </v-app>
</template>
