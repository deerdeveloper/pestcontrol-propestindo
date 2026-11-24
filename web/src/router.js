import { createRouter, createWebHistory } from 'vue-router'
import { useAuth } from './stores/auth'

const staff = { roles: ['super_admin', 'admin', 'supervisor'] }
const admins = { roles: ['super_admin', 'admin'] }
const customer = { roles: ['customer'] }
const superAdmin = { roles: ['super_admin'] }

const routes = [
  { path: '/login', component: () => import('./views/LoginView.vue'), meta: { public: true } },
  { path: '/', redirect: () => (useAuth().isCustomer ? '/portal' : '/dashboard') },
  { path: '/dashboard', component: () => import('./views/DashboardView.vue'), meta: staff },
  { path: '/visits', component: () => import('./views/VisitsView.vue'), meta: staff },
  { path: '/visits/:id', component: () => import('./views/VisitDetailView.vue'), meta: { roles: [...staff.roles, 'customer'] } },
  { path: '/customers', component: () => import('./views/CustomersView.vue'), meta: staff },
  { path: '/customers/:id', component: () => import('./views/CustomerDetailView.vue'), meta: staff },
  { path: '/sites/:id', component: () => import('./views/SiteDetailView.vue'), meta: staff },
  { path: '/master', redirect: '/master/pest-types' },
  { path: '/master/:resource', component: () => import('./views/MasterView.vue'), meta: staff },
  { path: '/users', component: () => import('./views/UsersView.vue'), meta: admins },
  { path: '/system', component: () => import('./views/SystemView.vue'), meta: superAdmin },
  { path: '/portal', component: () => import('./views/PortalHomeView.vue'), meta: customer },
  { path: '/portal/recommendations', component: () => import('./views/PortalRecommendationsView.vue'), meta: customer },
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

const router = createRouter({ history: createWebHistory(import.meta.env.BASE_URL), routes })

router.beforeEach(async (to) => {
  const auth = useAuth()
  if (!auth.user) await auth.load()
  if (to.meta.public) return auth.user && to.path === '/login' ? '/' : true
  if (!auth.user) return '/login'
  if (to.meta.roles && !to.meta.roles.includes(auth.user.role)) {
    return auth.user.role === 'customer' ? '/portal' : auth.user.role === 'technician' ? '/login' : '/dashboard'
  }
  return true
})

export default router
