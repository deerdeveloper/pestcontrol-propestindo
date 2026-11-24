import { createRouter, createWebHistory } from 'vue-router'
import { useAuth } from './stores/auth'

const staff = { roles: ['super_admin', 'admin', 'supervisor'] }
const admins = { roles: ['super_admin', 'admin'] }
const customer = { roles: ['customer'] }
const superAdmin = { roles: ['super_admin'] }
const technician = { roles: ['technician'], layout: 'tech' }

const routes = [
  { path: '/login', component: () => import('./views/LoginView.vue'), meta: { public: true } },
  { path: '/', redirect: () => useAuth().home },
  { path: '/dashboard', component: () => import('./views/DashboardView.vue'), meta: { ...staff, title: 'Dashboard' } },
  { path: '/visits', component: () => import('./views/VisitsView.vue'), meta: { ...staff, title: 'Jadwal kunjungan' } },
  { path: '/visits/:id', component: () => import('./views/VisitDetailView.vue'), meta: { roles: [...staff.roles, 'customer'], title: 'Detail kunjungan' } },
  { path: '/customers', component: () => import('./views/CustomersView.vue'), meta: { ...staff, title: 'Pelanggan & lokasi' } },
  { path: '/customers/:id', component: () => import('./views/CustomerDetailView.vue'), meta: { ...staff, title: 'Pelanggan' } },
  { path: '/sites/:id', component: () => import('./views/SiteDetailView.vue'), meta: { ...staff, title: 'Lokasi' } },
  { path: '/master', redirect: '/master/pest-types' },
  { path: '/master/:resource', component: () => import('./views/MasterView.vue'), meta: { ...staff, title: 'Data master' } },
  { path: '/users', component: () => import('./views/UsersView.vue'), meta: { ...admins, title: 'Pengguna' } },
  { path: '/system', component: () => import('./views/SystemView.vue'), meta: { ...superAdmin, title: 'Sistem & update' } },
  { path: '/portal', component: () => import('./views/PortalHomeView.vue'), meta: { ...customer, title: 'Laporan & jadwal' } },
  { path: '/portal/recommendations', component: () => import('./views/PortalRecommendationsView.vue'), meta: { ...customer, title: 'Rekomendasi' } },
  // Aplikasi teknisi (PWA, untuk HP)
  { path: '/tech', component: () => import('./views/tech/TechHomeView.vue'), meta: { ...technician, title: 'Jadwal' } },
  { path: '/tech/visits/:id', component: () => import('./views/tech/TechVisitView.vue'), meta: { ...technician, title: 'Kunjungan', full: true } },
  { path: '/tech/account', component: () => import('./views/tech/TechAccountView.vue'), meta: { ...technician, title: 'Akun' } },
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes,
  scrollBehavior: (to, from, saved) => saved || { top: 0 },
})

router.beforeEach(async (to) => {
  const auth = useAuth()
  if (!auth.user) await auth.load()
  if (to.meta.public) return auth.user && to.path === '/login' ? '/' : true
  if (!auth.user) return '/login'
  if (to.meta.roles && !to.meta.roles.includes(auth.user.role)) return auth.home
  return true
})

router.afterEach((to) => {
  document.title = (to.meta.title ? to.meta.title + ' · ' : '') + 'Propestindo'
})

export default router
