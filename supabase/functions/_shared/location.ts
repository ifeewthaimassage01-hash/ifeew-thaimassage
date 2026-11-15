// ตรวจว่าพนักงานอยู่ในร้านด้วย GPS: ตำแหน่งของเครื่องต้องอยู่ในรัศมีจากพิกัดร้าน

export interface LocationRule {
  latitude: number | null
  longitude: number | null
  radius_m: number
}

export interface ClientLocation {
  lat: number
  lng: number
  accuracy: number
}

/** ระยะทาง (เมตร) ระหว่างสองพิกัด */
export function distanceM(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6_371_000
  const rad = (d: number) => (d * Math.PI) / 180
  const dLat = rad(lat2 - lat1)
  const dLng = rad(lng2 - lng1)
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLng / 2) ** 2
  return 2 * R * Math.asin(Math.sqrt(a))
}

export function parseLocation(v: unknown): ClientLocation | null {
  const o = v as { lat?: unknown; lng?: unknown; accuracy?: unknown } | null
  const lat = Number(o?.lat)
  const lng = Number(o?.lng)
  const accuracy = Number(o?.accuracy ?? 0)
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return null
  return { lat, lng, accuracy: Number.isFinite(accuracy) && accuracy >= 0 ? accuracy : 0 }
}

/** ผ่านไหม · เผื่อความคลาดเคลื่อนของ GPS ได้สูงสุด 100 ม. (ตำแหน่งที่หยาบกว่า 500 ม. ไม่นับ) */
export function locationOk(rule: LocationRule, loc: ClientLocation | null): boolean {
  if (!loc || rule.latitude === null || rule.longitude === null || loc.accuracy > 500) return false
  return distanceM(rule.latitude, rule.longitude, loc.lat, loc.lng) <= rule.radius_m + Math.min(loc.accuracy, 100)
}
