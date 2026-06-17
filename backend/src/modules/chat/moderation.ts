/**
 * Text-only chat moderation. Per spec the chat must auto-block phone numbers, emails,
 * profanity, abuse/harassment, spam and scam attempts. This is a deterministic first
 * layer; a model-based classifier can be layered on top later via the same interface.
 */
export interface ModerationResult {
  allowed: boolean;
  reason?: string;
  /** message with detected PII/contact info masked, when partial-allow is desired */
  sanitized: string;
}

// Kenyan + international phone shapes, incl. spaced/dotted obfuscation.
const PHONE_RE = /(\+?\d[\s().-]?){9,}/g;
const EMAIL_RE = /[a-z0-9._%+-]+\s*(@|\(at\)|\sat\s)\s*[a-z0-9.-]+\s*(\.|\(dot\)|\sdot\s)\s*[a-z]{2,}/gi;
// "zero seven nine..." style spelled-out numbers (common evasion)
const SPELLED_NUMBERS_RE = /\b(zero|one|two|three|four|five|six|seven|eight|nine)(\s+(zero|one|two|three|four|five|six|seven|eight|nine)){6,}/gi;
const URL_RE = /\b(?:https?:\/\/|www\.)\S+/gi;

const PROFANITY = ['fuck', 'shit', 'bitch', 'asshole', 'bastard', 'dick', 'cunt', 'slut', 'whore'];
const SCAM = ['send money', 'mpesa me', 'pay me directly', 'cash app', 'western union', 'gift card', 'paybill', 'till number', 'whatsapp me', 'call me on'];

function hasProfanity(text: string): boolean {
  const t = text.toLowerCase();
  return PROFANITY.some((w) => new RegExp(`\\b${w}\\b`, 'i').test(t));
}
function hasScam(text: string): boolean {
  const t = text.toLowerCase();
  return SCAM.some((p) => t.includes(p));
}

export function moderateMessage(raw: string): ModerationResult {
  const text = raw.trim();
  if (!text) return { allowed: false, reason: 'empty', sanitized: '' };
  if (text.length > 1000) return { allowed: false, reason: 'too_long', sanitized: '' };

  if (PHONE_RE.test(text) || SPELLED_NUMBERS_RE.test(text)) {
    return { allowed: false, reason: 'phone_number_blocked', sanitized: mask(text) };
  }
  if (EMAIL_RE.test(text)) {
    return { allowed: false, reason: 'email_blocked', sanitized: mask(text) };
  }
  if (URL_RE.test(text)) {
    return { allowed: false, reason: 'link_blocked', sanitized: mask(text) };
  }
  if (hasProfanity(text)) {
    return { allowed: false, reason: 'profanity_blocked', sanitized: mask(text) };
  }
  if (hasScam(text)) {
    return { allowed: false, reason: 'scam_blocked', sanitized: mask(text) };
  }
  return { allowed: true, sanitized: text };
}

function mask(text: string): string {
  return text
    .replace(PHONE_RE, '[blocked]')
    .replace(EMAIL_RE, '[blocked]')
    .replace(URL_RE, '[blocked]')
    .replace(SPELLED_NUMBERS_RE, '[blocked]');
}
