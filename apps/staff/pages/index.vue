<script setup lang="ts">
// Phase 1: แดชบอร์ดชั่วคราว แสดงสิทธิ์ของผู้ใช้ (ข้อมูลธุรกิจจะเพิ่มใน Phase ถัดไป)
const user = useSupabaseUser()
const supabase = useSupabaseClient()
const { company, branches, activeBranch, isOwner } = useAccess()

const displayName = ref('')
watch(
  () => user.value?.sub,
  async (id) => {
    if (!id) return
    const { data } = await supabase.from('profiles').select('display_name').eq('id', id).maybeSingle()
    displayName.value = data?.display_name ?? ''
  },
  { immediate: true },
)
</script>

<template>
  <div>
    <h1 class="m-0 mb-6 text-2xl font-semibold text-cocoa">สวัสดี {{ displayName || 'ผู้ใช้' }}</h1>

    <div class="grid gap-4 md:grid-cols-3">
      <v-card class="p-5">
        <p class="m-0 text-sm text-light-brown">บริษัท</p>
        <p class="m-0 mt-1 text-lg font-medium">{{ company?.company_name }}</p>
      </v-card>
      <v-card class="p-5">
        <p class="m-0 text-sm text-light-brown">บทบาท</p>
        <p class="m-0 mt-1 text-lg font-medium">{{ isOwner ? 'เจ้าของร้าน (ยืนยัน MFA แล้ว)' : 'พนักงาน' }}</p>
      </v-card>
      <v-card class="p-5">
        <p class="m-0 text-sm text-light-brown">สาขาที่กำลังใช้งาน</p>
        <p class="m-0 mt-1 text-lg font-medium">{{ activeBranch?.name ?? '-' }}</p>
      </v-card>
    </div>

    <v-card class="mt-6 p-5">
      <p class="m-0 mb-3 font-medium">สาขาที่เข้าถึงได้ ({{ branches.length }})</p>
      <div class="flex flex-wrap gap-2">
        <v-chip v-for="b in branches" :key="b.branch_id" variant="tonal" color="primary">
          {{ b.code }} · {{ b.name }}
        </v-chip>
      </div>
    </v-card>
  </div>
</template>
