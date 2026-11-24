export const roles = {
  super_admin: 'Super Admin', admin: 'Admin', supervisor: 'Supervisor',
  technician: 'Teknisi', customer: 'Pelanggan',
}
export const visitTypes = {
  routine_monthly: 'Rutin Bulanan', routine_biweekly: 'Rutin Dua Mingguan',
  emergency: 'Kunjungan Darurat', initial_inspection: 'Inspeksi Awal',
}
export const visitStatus = {
  scheduled: 'Terjadwal', in_progress: 'Sedang dikerjakan', pending_review: 'Menunggu review',
  revision: 'Revisi', published: 'Terbit', cancelled: 'Dibatalkan',
}
export const levels = { none: 'Nihil', low: 'Rendah', medium: 'Sedang', high: 'Tinggi' }
export const categories = { exclusion: 'Penutupan Akses', sanitation: 'Sanitasi', storage: 'Penyimpanan', habitual: 'Kebiasaan' }
export const stationStatus = { ok: 'OK', check: 'Periksa', replace: 'Ganti' }
export const consumption = { none: 'Tidak ada aktivitas', partial: 'Dimakan sebagian', total: 'Habis total' }

export function fmtDate(d) {
  if (!d) return '-'
  return new Date(d.length === 10 ? d + 'T00:00:00' : d).toLocaleDateString('id-ID', { day: 'numeric', month: 'short', year: 'numeric' })
}
export function fmtTime(d) {
  return d ? new Date(d).toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' }) : '--:--'
}

export function fmtDay(d) {
  if (!d) return '-'
  return new Date(d.length === 10 ? d + 'T00:00:00' : d).toLocaleDateString('id-ID', { weekday: 'short', day: 'numeric', month: 'short' })
}
export function initials(name = '') {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map((s) => s[0].toUpperCase()).join('') || '?'
}
/** Tanggal lokal hari ini dalam format YYYY-MM-DD (bukan UTC). */
export function todayISO(offsetDays = 0) {
  const d = new Date()
  d.setDate(d.getDate() + offsetDays)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}
