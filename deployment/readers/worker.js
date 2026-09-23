import { createRemoteJWKSet, jwtVerify } from 'jose';

const keySets = new Map();
const privateHeaders = {
  'Cache-Control': 'private, no-store',
  'X-Robots-Tag': 'noindex, nofollow, noarchive',
  'Referrer-Policy': 'no-referrer',
  'X-Content-Type-Options': 'nosniff',
};
const deny = (status, message) => new Response(message, {
  status, headers: { ...privateHeaders, 'Content-Type': 'text/plain; charset=utf-8' },
});

// Access performs sign-in at the edge. Verify its signed assertion here as well,
// before ASSETS.fetch, so an alternate route cannot bypass authorization.
export function createReaderWorker(resolveKeys = issuer => {
  if (!keySets.has(issuer)) keySets.set(issuer, createRemoteJWKSet(new URL(`${issuer}/cdn-cgi/access/certs`)));
  return keySets.get(issuer);
}) {
  return {
    async fetch(request, env) {
      const team = env.ACCESS_TEAM_DOMAIN;
      if (!/^[a-z0-9-]+\.cloudflareaccess\.com$/.test(team || '') || !env.ACCESS_AUD || !env.READER_HOSTNAME) {
        return deny(503, 'Reader library is not configured.');
      }
      const url = new URL(request.url);
      if (url.hostname !== env.READER_HOSTNAME || url.protocol !== 'https:') return deny(403, 'Access denied.');
      const token = request.headers.get('Cf-Access-Jwt-Assertion');
      if (!token) return deny(401, 'Sign in through the reader library to continue.');
      let emails;
      try {
        emails = JSON.parse(env.APPROVED_EMAILS || '[]');
        if (!Array.isArray(emails) || !emails.every(email => typeof email === 'string')) throw new Error('Invalid allowlist');
      } catch (_) { return deny(503, 'Reader library is not configured.'); }
      try {
        const issuer = `https://${team}`;
        const { payload } = await jwtVerify(token, resolveKeys(issuer), {
          issuer, audience: env.ACCESS_AUD, algorithms: ['RS256'],
          requiredClaims: ['exp', 'iat', 'sub', 'email'],
        });
        if (typeof payload.email !== 'string' || !emails.map(email => email.trim().toLowerCase()).includes(payload.email.toLowerCase())) {
          return deny(403, 'Your account does not have access to this library.');
        }
      } catch (_) { return deny(401, 'Your session is invalid or expired. Please sign in again.'); }
      if (!['GET', 'HEAD'].includes(request.method)) return deny(405, 'Method not allowed.');
      const asset = await env.ASSETS.fetch(request);
      const response = new Response(asset.body, asset);
      Object.entries(privateHeaders).forEach(([key, value]) => response.headers.set(key, value));
      return response;
    },
  };
}
export default createReaderWorker();
