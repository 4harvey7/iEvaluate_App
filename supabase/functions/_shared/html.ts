// supabase/functions/_shared/html.ts
//
// Escaping for values put into HTML email bodies. Any value that came from a
// request body, a user or the database goes through escapeHtml before it is
// interpolated, so text like <b> or <script> shows as text instead of markup.
// Used by send-intervention-email and update-system-settings.

/** Escape a value for safe interpolation into HTML text or a quoted attribute. */
export function escapeHtml(value: unknown): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

/** Escape, then keep line breaks readable. */
export function escapeMultiline(value: unknown): string {
  return escapeHtml(value).replace(/\r\n|\r|\n/g, '<br>')
}
