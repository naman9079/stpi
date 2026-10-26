import { createClient } from 'npm:@supabase/supabase-js@2'

declare const Deno: {
  env: { get(name: string): string | undefined }
  serve(handler: (request: Request) => Promise<Response>): void
}

type MetricRow = {
  slug: string
  revenue: Record<string, number | null>
  raised_cents: number | null
  customers: number | null
  active_subscriptions: number | null
  currency: string
  source: string
  updated_at: string
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, 'Content-Type': 'application/json' },
})

function env(name: string) {
  return Deno.env.get(name)?.trim() || ''
}

function errorMessage(status: number, body: unknown) {
  const detail = typeof body === 'object' && body !== null && 'error' in body
    ? String((body as { error?: unknown }).error || '')
    : ''
  return detail || `TrustMRR API returned ${status}.`
}

function periodDelta(snapshots: Array<{ total_revenue_cents: number | null; captured_at: string }>, days: number) {
  if (snapshots.length < 2) return null
  const latest = snapshots[snapshots.length - 1]
  const cutoff = Date.now() - days * 24 * 60 * 60 * 1000
  const before = snapshots.filter((snapshot) => new Date(snapshot.captured_at).getTime() <= cutoff).at(-1) || snapshots[0]
  if (!before || latest.total_revenue_cents == null || before.total_revenue_cents == null) return null
  return Math.max(0, latest.total_revenue_cents - before.total_revenue_cents)
}

async function syncTrustMrr(slug: string, admin: ReturnType<typeof createClient>) {
  const key = env('TRUSTMRR_API_KEY')
  if (!key) throw new Error('TRUSTMRR_API_KEY is not configured in Supabase Edge Function secrets.')
  const response = await fetch(`https://trustmrr.com/api/v1/startups/${encodeURIComponent(slug)}`, {
    headers: { Authorization: `Bearer ${key}`, Accept: 'application/json' },
  })
  const payload = await response.json()
  if (!response.ok) throw new Error(`${slug}: ${errorMessage(response.status, payload)}`)
  const data = payload?.data
  if (!data?.slug || !data?.revenue) throw new Error(`${slug}: TrustMRR returned no startup data.`)

  const snapshot = {
    slug,
    total_revenue_cents: typeof data.revenue.total === 'number' ? data.revenue.total : null,
    mrr_cents: typeof data.revenue.mrr === 'number' ? data.revenue.mrr : null,
    customers: typeof data.customers === 'number' ? data.customers : null,
    active_subscriptions: typeof data.activeSubscriptions === 'number' ? data.activeSubscriptions : null,
  }
  const inserted = await admin.from('sponsor_metric_snapshots').insert(snapshot)
  if (inserted.error) console.error('snapshot insert failed', inserted.error.message)

  const since = new Date(Date.now() - 366 * 24 * 60 * 60 * 1000).toISOString()
  const history = await admin.from('sponsor_metric_snapshots')
    .select('total_revenue_cents,captured_at')
    .eq('slug', slug)
    .gte('captured_at', since)
    .order('captured_at', { ascending: true })
  const snapshots = (history.data || []) as Array<{ total_revenue_cents: number | null; captured_at: string }>
  const revenue = {
    day: periodDelta(snapshots, 1),
    week: periodDelta(snapshots, 7),
    month: typeof data.revenue.last30Days === 'number' ? data.revenue.last30Days : periodDelta(snapshots, 30),
    threeMonths: periodDelta(snapshots, 90),
    sixMonths: periodDelta(snapshots, 180),
    year: periodDelta(snapshots, 365),
    lifetime: typeof data.revenue.total === 'number' ? data.revenue.total : null,
  }
  const current: MetricRow = {
    slug,
    revenue,
    raised_cents: null,
    customers: snapshot.customers,
    active_subscriptions: snapshot.active_subscriptions,
    currency: 'USD',
    source: 'trustmrr',
    updated_at: new Date().toISOString(),
  }
  const existing = await admin.from('sponsor_metrics').select('raised_cents').eq('slug', slug).maybeSingle()
  current.raised_cents = existing.data?.raised_cents ?? null
  const saved = await admin.from('sponsor_metrics').upsert(current)
  if (saved.error) console.error('metric upsert failed', saved.error.message)
  return current
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'GET') return json({ error: 'GET required' }, 405)

  const supabaseUrl = env('SUPABASE_URL')
  const serviceRoleKey = env('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceRoleKey) return json({ error: 'Supabase service configuration is missing.' }, 500)
  const admin = createClient(supabaseUrl, serviceRoleKey)
  const requested = new URL(request.url).searchParams.get('slugs')?.split(',').map((slug) => slug.trim()).filter(Boolean) || []
  const configured = env('TRUSTMRR_STARTUP_SLUGS').split(',').map((slug: string) => slug.trim()).filter(Boolean)
  const slugs = configured.length ? configured : requested.length ? requested : ['matiks', 'trustmrr']

  const errors: string[] = []
  for (const slug of slugs) {
    try { await syncTrustMrr(slug, admin) } catch (error) { errors.push(error instanceof Error ? error.message : String(error)) }
  }
  const rows = await admin.from('sponsor_metrics').select('*').in('slug', slugs)
  if (rows.error) return json({ error: rows.error.message }, 500)
  if ((rows.data || []).length === 0 && errors.length > 0) return json({ error: errors.join(' ') }, 502)
  return json({ startups: Object.fromEntries((rows.data || []).map((row: any) => [row.slug, {
    slug: row.slug,
    revenue: row.revenue,
    raised: row.raised_cents,
    customers: row.customers,
    activeSubscriptions: row.active_subscriptions,
    currency: row.currency,
    source: row.source,
    updatedAt: row.updated_at,
  }])), errors: errors.length ? errors : undefined })
})
