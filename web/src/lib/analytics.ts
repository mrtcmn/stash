import posthog from 'posthog-js'

// Same PostHog project as the app (Analytics.swift). Project keys are public by design.
const KEY = 'phc_Bik6QbJiEZmpXCnwfuSw9UReCqb5Y7KfYtbzAZjZfEEP'

// Link targets that count as events; the event's location comes from the closest data-where.
const LINK_EVENTS: [string, string][] = [
  ['/releases/latest/download/Stash.dmg', 'download_clicked'],
  ['chromewebstore.google.com', 'extension_clicked'],
  ['/releases', 'changelog_clicked'],
]

export function initAnalytics() {
  if (import.meta.env.DEV) return
  posthog.init(KEY, {
    api_host: 'https://eu.i.posthog.com',
    // No cookies or local storage, so the site needs no consent banner; every visit is a new visitor.
    persistence: 'memory',
    person_profiles: 'identified_only',
    autocapture: false,
    disable_session_recording: true,
  })
  // Like the app: no location lookup, so the privacy page can list everything an event holds.
  posthog.register({ $geoip_disable: true })
  document.addEventListener('click', (e) => {
    const a = (e.target as Element).closest('a')
    const event = a && LINK_EVENTS.find(([part]) => a.href.includes(part))?.[1]
    if (event) track(event, { location: a.closest<HTMLElement>('[data-where]')?.dataset.where })
  })
}

export const track = (event: string, properties?: Record<string, unknown>) => {
  if (posthog.__loaded) posthog.capture(event, properties, { send_instantly: true })
}
