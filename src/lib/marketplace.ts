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
  logo_url?: string | null
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

export type Profile = { id: string; display_name: string | null; role: Role; bio?: string | null; avatar_url?: string | null; location?: string | null }
export type PublicProfile = {
  id: string
  display_name: string | null
  avatar_url: string | null
  bio: string | null
  location: string | null
  role: Role
  company_name: string | null
  website: string | null
  contact_email: string | null
  projects_posted: number
  projects_sold: number
  projects_bought: number
  posted_projects: Array<Pick<Project, 'id' | 'title' | 'summary' | 'status' | 'created_at'>>
  sold_projects: Array<Pick<Project, 'id' | 'title' | 'summary' | 'status' | 'created_at'>>
  bought_projects: Array<Pick<Project, 'id' | 'title' | 'summary' | 'status' | 'created_at'>>
}
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
export type Message = { id: string; inquiry_id: string; sender_id: string; body: string; attachments?: unknown[]; delivered_at?: string | null; read_at?: string | null; created_at: string }
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

export async function getPublicProfile(userId: string): Promise<PublicProfile> {
  const { data, error } = await getSupabase().rpc('get_public_profile', { p_profile_id: userId })
  fail(error)
  const profile = data as PublicProfile | null
  if (!profile) throw new Error('Profile not found.')
  return profile
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
  // Browse is available only after authentication, and the marketplace
  // workspace intentionally lets signed-in users discover every project,
  // including projects that are still drafts or in review.
  let query = getSupabase().from('projects').select('*', { count: 'exact' }).order('created_at', { ascending: false }).range(from, from + params.pageSize - 1)
  if (params.search.trim()) {
    const search = params.search.trim().replace(/[,()]/g, ' ')
    query = query.or(`title.ilike.%${search}%,summary.ilike.%${search}%,description.ilike.%${search}%`)
  }
  if (params.industry) query = query.eq('industry', params.industry)
  const { data, error, count } = await query
  fail(error)
  return { projects: await hydrateProjectLogos((data ?? []) as Project[]), total: count ?? 0 }
}

async function hydrateProjectLogos(projects: Project[]) {
  if (!projects.length) return projects
  const db = getSupabase()
  const { data, error } = await db.from('project_assets').select('project_id, storage_path').eq('asset_type', 'logo').in('project_id', projects.map((project) => project.id))
  fail(error)
  const urls = await Promise.all((data ?? []).map(async (asset: { project_id: string; storage_path: string }) => {
    const signed = await db.storage.from('project-public-assets').createSignedUrl(asset.storage_path, 60 * 60)
    fail(signed.error)
    return [asset.project_id, signed.data?.signedUrl ?? null] as const
  }))
  const byProject = new Map(urls)
  return projects.map((project) => ({ ...project, logo_url: byProject.get(project.id) ?? null }))
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

export async function deleteProject(projectId: string, sellerId: string) {
  const { error } = await getSupabase().from('projects').delete().eq('id', projectId).eq('seller_id', sellerId)
  fail(error)
}

export async function listOwnProjects(sellerId: string) {
  const { data, error } = await getSupabase().from('projects').select('*').eq('seller_id', sellerId).order('created_at', { ascending: false })
  fail(error)
  return hydrateProjectLogos((data ?? []) as Project[])
}

export async function uploadProjectLogo(projectId: string, file: File) {
  const webp = await convertImageToWebp(file)
  const path = `${projectId}/logo.webp`
  const db = getSupabase()
  const upload = await db.storage.from('project-public-assets').upload(path, webp, { contentType: 'image/webp', upsert: true })
  fail(upload.error)
  const asset = await db.from('project_assets').upsert({ project_id: projectId, storage_path: path, asset_type: 'logo', file_name: 'logo.webp', mime_type: 'image/webp', size_bytes: webp.size, visibility: 'public', sort_order: 0 }, { onConflict: 'project_id,storage_path' }).select('*').single()
  fail(asset.error)
  const signed = await db.storage.from('project-public-assets').createSignedUrl(path, 60 * 60)
  fail(signed.error)
  return signed.data?.signedUrl ?? null
}

async function convertImageToWebp(file: File): Promise<File> {
  if (!file.type.startsWith('image/')) throw new Error('Choose an image file for the project logo.')
  if (file.size > 8 * 1024 * 1024) throw new Error('Project logos must be smaller than 8 MB.')
  const bitmap = await createImageBitmap(file)
  const maxDimension = 720
  const scale = Math.min(1, maxDimension / Math.max(bitmap.width, bitmap.height))
  const canvas = document.createElement('canvas')
  canvas.width = Math.max(1, Math.round(bitmap.width * scale))
  canvas.height = Math.max(1, Math.round(bitmap.height * scale))
  const context = canvas.getContext('2d')
  if (!context) throw new Error('Your browser could not prepare the logo image.')
  context.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
  bitmap.close()
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/webp', 0.82))
  if (!blob) throw new Error('Your browser could not convert the logo to WebP.')
  return new File([blob], 'logo.webp', { type: 'image/webp', lastModified: Date.now() })
}

export async function listModerationProjects() {
  const { data, error } = await getSupabase().from('projects').select('*').in('status', ['draft', 'in_review', 'paused']).order('created_at', { ascending: false })
  fail(error)
  return (data ?? []) as Project[]
}

export async function moderateProject(id: string, status: ProjectStatus) { const { error } = await getSupabase().from('projects').update({ status }).eq('id', id); fail(error) }

export async function saveProject(buyerId: string, projectId: string) { const { error } = await getSupabase().from('saved_projects').upsert({ buyer_id: buyerId, project_id: projectId }); fail(error) }
export async function removeSavedProject(buyerId: string, projectId: string) { const { error } = await getSupabase().from('saved_projects').delete().eq('buyer_id', buyerId).eq('project_id', projectId); fail(error) }
export async function listSavedProjects(buyerId: string) { const { data, error } = await getSupabase().from('saved_projects').select('project_id, projects(*)').eq('buyer_id', buyerId); fail(error); return hydrateProjectLogos((data ?? []).map((row: any) => row.projects).filter(Boolean) as Project[]) }

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
export async function markMessagesDelivered(inquiryId: string, userId: string) {
  const { error } = await getSupabase().from('inquiry_messages').update({ delivered_at: new Date().toISOString() }).eq('inquiry_id', inquiryId).neq('sender_id', userId).is('delivered_at', null)
  fail(error)
}
export async function markMessagesSeen(inquiryId: string, userId: string) {
  const { error } = await getSupabase().from('inquiry_messages').update({ delivered_at: new Date().toISOString(), read_at: new Date().toISOString() }).eq('inquiry_id', inquiryId).neq('sender_id', userId)
  fail(error)
}

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
