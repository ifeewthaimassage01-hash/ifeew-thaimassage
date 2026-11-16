<script setup lang="ts">
// OWNER: ตั้งค่าของสาขาเดียวแบบเต็มหน้า (เวลาทำการ วันหยุด บัญชีรับมัดจำ พื้นที่เข้าระบบ)
// หน้า /branches เปิดแต่ละส่วนเป็น popup ด้วยคอมโพเนนต์เดียวกัน
definePageMeta({ ownerOnly: true })

const route = useRoute()
const supabase = useSupabaseClient()
const branchId = computed(() => String(route.params.id))
const branchName = ref('')
const companyId = ref('')

onMounted(async () => {
  const { data } = await supabase.from('branches').select('name, company_id').eq('id', branchId.value).maybeSingle()
  branchName.value = data?.name ?? ''
  companyId.value = data?.company_id ?? ''
})
</script>

<template>
  <div class="mx-auto max-w-4xl">
    <PageHeader :title="branchName || 'สาขา'" description="เวลาทำการ วันหยุด และบัญชีรับมัดจำ ใช้ในหน้าจองของลูกค้า">
      <template #actions><Button as-child variant="outline"><NuxtLink to="/branches">สาขาทั้งหมด</NuxtLink></Button></template>
    </PageHeader>

    <div v-if="companyId" class="grid gap-6">
      <SectionCard id="hours" class="scroll-mt-20" title="เวลาทำการและวันหยุด">
        <BranchHoursForm :branch-id="branchId" :company-id="companyId" />
      </SectionCard>
      <SectionCard id="deposit" class="scroll-mt-20" title="บัญชีรับมัดจำ" description="ลูกค้าจะเห็น QR PromptPay ของบัญชีนี้ · SlipOK Branch ID ต้องผูกกับบัญชีเดียวกันในระบบ SlipOK">
        <BranchDepositForm :branch-id="branchId" :company-id="companyId" />
      </SectionCard>
      <BranchLoginLock id="login-lock" class="scroll-mt-20" :branch-id="branchId" :company-id="companyId" />
    </div>
  </div>
</template>
