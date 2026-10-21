import { type User } from '@supabase/supabase-js'
import { getSupabase } from './supabase'

export type Role = 'buyer' | 'seller' | 'verifier' | 'support' | 'moderator' | 'admin'
export type ProjectStatus = 'draft' | 'in_review' | 'published' | 'paused' | 'sold' | 'archived'

export type Project = {
  id: string
  seller_id: string
  title: string
  slug: string
  summary: string | null
  description: string | null
  status: ProjectStatus
  asking_price: number | null
  currency: string
  revenue: number | null
  annual_growth: number | null
  location: string | null
  industry: string | null
  is_featured: boolean
  published_at: string | null
  created_at: string
  updated_at?: string
}

export type ProjectInput = {
  title: string
  slug?: string
  summary?: string | null
  description?: string | null
  status?: ProjectStatus
  asking_price?: number | null
  currency?: string
  revenue?: number | null
  annual_growth?: number | null
  location?: string | null
  industry?: string | null
}

export type Profile = { id: string; display_name: string | null; role: Role; bio?: string | null }
export type BuyerRequest = {
  id: string
  buyer_id: string
  title: string
  description: string | null
  budget_min: number | null
  budget_max: number | null
  target_industries: string[]
  status: string | null
  created_at: string
}
export type BuyerRequestInput = {
  title: string
  description: string
  budget_min: number | null
  budget_max: number | null
  target_industries: string[]
}
export type Inquiry = { id: string; project_id: string | null; buyer_id: string; seller_id: string; subject: string | null; status: string | null; created_at: string; project?: Pick<Project, 'title'> }
export type Message = { id: string; inquiry_id: string; sender_id: string; body: string; attachments?: unknown[]; created_at: string }
export type HandoverTask = { id: string; handover_record_id: string; title: string; description: string | null; assigned_to: string | null; status: 'todo' | 'in_progress' | 'blocked' | 'done' | 'cancelled'; due_at: string | null; completed_at: string | null; created_at: string }
export type HandoverRecord = { id: string; project_id: string; buyer_id: string; seller_id: string; status: 'planned' | 'in_progress' | 'completed' | 'cancelled' }

const fail = (error: { message?: string } | null) => { if (error) throw new Error(error.message || 'Supabase request failed.') }

export async function getSessionUser(): Promise<User | null> {
  // getSession() restores the persisted session locally. getUser() performs a
  // network round-trip and should not block the first paint on every reload.
  const { data, error } = await getSupabase().auth.getSession()
  if (error && error.message !== 'Auth session missing!') throw error
  return data.session?.user ?? null
}

export async function subscribeToAuth(callback: (user: User | null) => void) {
  const { data } = getSupabase().auth.onAuthStateChange((_event, session) => callback(session?.user ?? null))
  return data.subscription
}

export async function signUp(email: string, password: string, displayName: string) {
  const { data, error } = await getSupabase().auth.signUp({ email, password, options: { data: { display_name: displayName } } })
  fail(error)
  if (data.user && !data.session) return 'Check your email to confirm your account.'
  return 'Account created.'
}
export async function signIn(email: string, password: string) { const { error } = await getSupabase().auth.signInWithPassword({ email, password }); fail(error) }
export async function signOut() { const { error } = await getSupabase().auth.signOut(); fail(error) }
export async function resetPassword(email: string) { const { error } = await getSupabase().auth.resetPasswordForEmail(email, { redirectTo: window.location.origin }); fail(error) }

export async function getProfile(userId: string): Promise<Profile> {
  const { data, error } = await getSupabase().from('profiles').select('*').eq('id', userId).maybeSingle()
  fail(error)
  if (data) return data as Profile
  const created = await getSupabase().from('profiles').upsert({ id: userId, role: 'buyer' }).select('*').single()
  fail(created.error)
  return created.data as Profile
}

export async function updateProfile(userId: string, changes: Partial<Profile>) {
  // Do not use upsert here. Supabase evaluates an upsert as an INSERT as well,
  // which makes a valid existing profile hit the self-insert RLS policy when a
  // buyer switches to seller. The auth trigger owns profile creation; role
  // changes must update the existing row only.
  const { data, error } = await getSupabase().from('profiles').update(changes).eq('id', userId).select('*').single()
  fail(error)
  return data as Profile
}

export async function listProjects(params: { viewerId: string; search: string; industry: string; page: number; pageSize: number }) {
  const from = (params.page - 1) * params.pageSize
  // Public users see published projects. An authenticated seller can also see
  // their own drafts/in-review listings, while those records remain private to
  // everyone else under the database RLS policy.
  let query = getSupabase().from('projects').select('*', { count: 'exact' }).or(`status.eq.published,seller_id.eq.${params.viewerId}`).order('created_at', { ascending: false }).range(from, from + params.pageSize - 1)
  if (params.search.trim()) {
    const search = params.search.trim().replace(/[,()]/g, ' ')
    query = query.or(`title.ilike.%${search}%,summary.ilike.%${search}%,description.ilike.%${search}%`)
  }
  if (params.industry) query = query.eq('industry', params.industry)
  const { data, error, count } = await query
  fail(error)
  return { projects: (data ?? []) as Project[], total: count ?? 0 }
}

function slugify(value: string) {
  return value.toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || `project-${Date.now()}`
}

export async function createProjectDraft(sellerId: string, input: ProjectInput) {
  const payload = { ...input, seller_id: sellerId, slug: input.slug || `${slugify(input.title)}-${crypto.randomUUID().slice(0, 8)}`, status: input.status || 'draft' }
  const { data, error } = await getSupabase().from('projects').insert(payload).select('*').single()
  if (error?.code === '42501') throw new Error('Switch to the seller workspace before creating a project. The database correctly blocks buyer accounts from creating seller listings.')
  fail(error)
  return data as Project
}

export async function updateProject(projectId: string, sellerId: string, input: ProjectInput) {
  const { data, error } = await getSupabase().from('projects').update(input).eq('id', projectId).eq('seller_id', sellerId).select('*').single()
  fail(error)
  return data as Project
}

export async function listOwnProjects(sellerId: string) {
  const { data, error } = await getSupabase().from('projects').select('*').eq('seller_id', sellerId).order('created_at', { ascending: false })
  fail(error)
  return (data ?? []) as Project[]
}

export async function listModerationProjects() {
  const { data, error } = await getSupabase().from('projects').select('*').in('status', ['draft', 'in_review', 'paused']).order('created_at', { ascending: false })
  fail(error)
  return (data ?? []) as Project[]
}

export async function moderateProject(id: string, status: ProjectStatus) { const { error } = await getSupabase().from('projects').update({ status }).eq('id', id); fail(error) }

export async function saveProject(buyerId: string, projectId: string) { const { error } = await getSupabase().from('saved_projects').upsert({ buyer_id: buyerId, project_id: projectId }); fail(error) }
export async function removeSavedProject(buyerId: string, projectId: string) { const { error } = await getSupabase().from('saved_projects').delete().eq('buyer_id', buyerId).eq('project_id', projectId); fail(error) }
export async function listSavedProjects(buyerId: string) { const { data, error } = await getSupabase().from('saved_projects').select('project_id, projects(*)').eq('buyer_id', buyerId); fail(error); return (data ?? []).map((row: any) => row.projects).filter(Boolean) as Project[] }

export async function createBuyerRequest(buyerId: string, input: BuyerRequestInput) {
  const { data, error } = await getSupabase().from('buyer_requests').insert({ ...input, buyer_id: buyerId, status: 'open' }).select('*').single()
  fail(error)
  return data as BuyerRequest
}
export async function listBuyerRequests(buyerId: string) { const { data, error } = await getSupabase().from('buyer_requests').select('*').eq('buyer_id', buyerId).order('created_at', { ascending: false }); fail(error); return (data ?? []) as BuyerRequest[] }
export async function listMatches(buyerId: string) {
  const requests = await listBuyerRequests(buyerId)
  if (!requests.length) return []
  const { data, error } = await getSupabase().from('buyer_request_matches').select('*, project:projects(*)').in('buyer_request_id', requests.map((request) => request.id)).order('created_at', { ascending: false })
  fail(error)
  return (data ?? []).map((row: any) => row.project).filter(Boolean) as Project[]
}

export async function createInquiry(buyerId: string, project: Project, body: string) {
  if (buyerId === project.seller_id) throw new Error('You cannot inquire about your own project.')
  const db = getSupabase()
  const inquiry = await db.from('inquiries').insert({ buyer_id: buyerId, seller_id: project.seller_id, project_id: project.id, subject: `Question about ${project.title}`, status: 'open' }).select('*').single()
  fail(inquiry.error)
  const message = await db.from('inquiry_messages').insert({ inquiry_id: inquiry.data.id, sender_id: buyerId, body }).select('*').single()
  fail(message.error)
  return inquiry.data as Inquiry
}
export async function listInquiries(userId: string) { const { data, error } = await getSupabase().from('inquiries').select('*, project:projects(title)').or(`buyer_id.eq.${userId},seller_id.eq.${userId}`).order('created_at', { ascending: false }); fail(error); return (data ?? []) as Inquiry[] }
export async function listMessages(inquiryId: string) { const { data, error } = await getSupabase().from('inquiry_messages').select('*').eq('inquiry_id', inquiryId).order('created_at', { ascending: true }); fail(error); return (data ?? []) as Message[] }
export async function sendMessage(inquiryId: string, senderId: string, body: string) { const { data, error } = await getSupabase().from('inquiry_messages').insert({ inquiry_id: inquiryId, sender_id: senderId, body }).select('*').single(); fail(error); return data as Message }

export async function getOrCreateHandoverRecord(projectId: string, buyerId: string, sellerId: string) {
  if (buyerId === sellerId) throw new Error('A handover requires a buyer and a seller.')
  const db = getSupabase()
  const existing = await db.from('handover_records').select('*').eq('project_id', projectId).eq('buyer_id', buyerId).maybeSingle()
  fail(existing.error)
  if (existing.data) return existing.data as HandoverRecord
  const created = await db.from('handover_records').insert({ project_id: projectId, buyer_id: buyerId, seller_id: sellerId, status: 'planned' }).select('*').single()
  fail(created.error)
  return created.data as HandoverRecord
}
export async function listHandoverTasks(recordId: string) { const { data, error } = await getSupabase().from('handover_tasks').select('*').eq('handover_record_id', recordId).order('created_at', { ascending: true }); fail(error); return (data ?? []) as HandoverTask[] }
export async function toggleHandoverTask(id: string, status: HandoverTask['status']) { const { error } = await getSupabase().from('handover_tasks').update({ status, completed_at: status === 'done' ? new Date().toISOString() : null }).eq('id', id); fail(error) }
