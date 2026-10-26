import { getSupabase } from './supabase'

export const sponsorMetricPeriods = [
  { key: 'day', label: 'Today' },
  { key: 'week', label: '7 days' },
  { key: 'month', label: '30 days' },
  { key: 'threeMonths', label: '3 months' },
  { key: 'sixMonths', label: '6 months' },
  { key: 'year', label: '1 year' },
  { key: 'lifetime', label: 'Lifetime' },
] as const

export type SponsorMetricPeriod = typeof sponsorMetricPeriods[number]['key']
export type SponsorMetricSeries = Partial<Record<SponsorMetricPeriod, number>>

export type SponsorMetrics = {
  slug: string
  revenue?: SponsorMetricSeries
  raised?: number | null
  customers?: number | null
  activeSubscriptions?: number | null
  updatedAt?: string | null
  currency?: string
  source?: string | null
}

export type SponsorMetricsBySlug = Record<string, SponsorMetrics>

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value)
}

function normalizeMetric(slug: string, value: unknown): SponsorMetrics | null {
  if (!isRecord(value)) return null
  const revenue = isRecord(value.revenue) ? value.revenue as SponsorMetricSeries : undefined
  return {
    slug,
    revenue,
    raised: typeof value.raised === 'number' ? value.raised : null,
    customers: typeof value.customers === 'number' ? value.customers : null,
    activeSubscriptions: typeof value.activeSubscriptions === 'number' ? value.activeSubscriptions : null,
    updatedAt: typeof value.updatedAt === 'string' ? value.updatedAt : null,
    currency: typeof value.currency === 'string' ? value.currency : 'USD',
    source: typeof value.source === 'string' ? value.source : null,
  }
}

function normalizeStoredMetric(value: Record<string, unknown>): SponsorMetrics | null {
  const slug = typeof value.slug === 'string' ? value.slug : null
  if (!slug) return null
  return normalizeMetric(slug, {
    ...value,
    revenue: value.revenue,
    raised: typeof value.raised_cents === 'number' ? value.raised_cents : null,
    activeSubscriptions: typeof value.active_subscriptions === 'number' ? value.active_subscriptions : null,
    updatedAt: value.updated_at,
  })
}

export async function listStoredSponsorMetrics(slugs?: string[]): Promise<SponsorMetricsBySlug> {
  const query = getSupabase().from('sponsor_metrics').select('*')
  const result = slugs?.length ? await query.in('slug', slugs) : await query
  if (result.error) throw result.error
  return Object.fromEntries((result.data || [])
    .map((row) => normalizeStoredMetric(row as Record<string, unknown>))
    .filter((metric): metric is SponsorMetrics => Boolean(metric))
    .map((metric) => [metric.slug, metric]))
}

export async function updateStoredSponsorMetric(slug: string, metric: SponsorMetrics): Promise<SponsorMetrics> {
  const result = await getSupabase().from('sponsor_metrics').upsert({
    slug,
    revenue: metric.revenue || {},
    raised_cents: metric.raised ?? null,
    customers: metric.customers ?? null,
    active_subscriptions: metric.activeSubscriptions ?? null,
    currency: metric.currency || 'USD',
    source: metric.source || 'manual',
    updated_at: new Date().toISOString(),
  }).select('*').single()
  if (result.error) throw result.error
  const normalized = normalizeStoredMetric(result.data as Record<string, unknown>)
  if (!normalized) throw new Error('Sponsor metric response was invalid.')
  return normalized
}

export function subscribeToSponsorMetrics(onChange: () => void) {
  const channel = getSupabase().channel('sponsor-metrics-live')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'sponsor_metrics' }, onChange)
    .subscribe()
  return () => { void channel.unsubscribe() }
}

export async function fetchSponsorMetrics(slugs: string[]): Promise<SponsorMetricsBySlug> {
  const endpoint = import.meta.env.VITE_SPONSOR_METRICS_URL?.trim()
  if (slugs.length === 0) return {}

  if (!endpoint) return listStoredSponsorMetrics(slugs)

  try {
    const url = new URL(endpoint, window.location.origin)
    url.searchParams.set('slugs', slugs.join(','))
    const response = await fetch(url, { headers: { Accept: 'application/json' } })
    if (!response.ok) throw new Error(`Sponsor metrics request failed (${response.status}).`)

    const payload: unknown = await response.json()
    const records = isRecord(payload) && isRecord(payload.sponsors) ? payload.sponsors : payload
    if (!isRecord(records)) return {}

    return Object.fromEntries(Object.entries(records)
      .map(([slug, value]) => [slug, normalizeMetric(slug, value)] as const)
      .filter((entry): entry is readonly [string, SponsorMetrics] => Boolean(entry[1])))
  } catch (error) {
    const fallback = await listStoredSponsorMetrics(slugs)
    if (Object.keys(fallback).length > 0) return fallback
    throw error
  }
}
