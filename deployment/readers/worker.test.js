import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, SignJWT, createLocalJWKSet, exportJWK } from 'jose';
import { createReaderWorker } from './worker.js';

const { publicKey, privateKey } = await generateKeyPair('RS256');
const jwk = await exportJWK(publicKey);
jwk.kid = 'test';
const worker = createReaderWorker(() => createLocalJWKSet({ keys: [jwk] }));
const issuer = 'https://test-team.cloudflareaccess.com';
const env = {
  ACCESS_TEAM_DOMAIN: 'test-team.cloudflareaccess.com', ACCESS_AUD: 'readers',
  READER_HOSTNAME: 'readers.example.com', APPROVED_EMAILS: '["reader@example.com"]',
};
const signed = (claims = {}, key = privateKey) => new SignJWT({ email: 'reader@example.com', ...claims })
  .setProtectedHeader({ alg: 'RS256', kid: 'test' }).setSubject('reader')
  .setIssuedAt().setIssuer(issuer).setAudience('readers').setExpirationTime('5m').sign(key);
async function request(token, overrides = {}, path = '/assets/private.pdf', host = 'readers.example.com') {
  let calls = 0;
  const response = await worker.fetch(new Request(`https://${host}${path}`, {
    headers: token ? { 'Cf-Access-Jwt-Assertion': token } : {},
  }), { ...env, ASSETS: { fetch: async () => { calls++; return new Response('PRIVATE SENTINEL'); } }, ...overrides });
  return { response, calls };
}
test('anonymous requests never reach HTML or attachment storage', async () => {
  for (const path of ['/', '/article/', '/assets/private.pdf', '/search.json']) {
    const { response, calls } = await request(null, {}, path);
    assert.equal(response.status, 401); assert.equal(calls, 0);
  }
});
test('approved token serves an attachment without shared caching', async () => {
  const { response, calls } = await request(await signed());
  assert.equal(response.status, 200); assert.equal(calls, 1);
  assert.equal(await response.text(), 'PRIVATE SENTINEL');
  assert.equal(response.headers.get('cache-control'), 'private, no-store');
});
test('unapproved and revoked readers do not reach storage', async () => {
  for (const token of [await signed({ email: 'other@example.com' }), await signed()]) {
    const { response, calls } = await request(token, { APPROVED_EMAILS: '[]' });
    assert.equal(response.status, 403); assert.equal(calls, 0);
  }
});
test('expired, wrong audience, forged tokens and alternate hosts fail closed', async () => {
  const expired = await new SignJWT({ email: 'reader@example.com' }).setProtectedHeader({ alg: 'RS256', kid: 'test' }).setSubject('reader').setIssuedAt().setIssuer(issuer).setAudience('readers').setExpirationTime(1).sign(privateKey);
  const wrongAudience = await new SignJWT({ email: 'reader@example.com' }).setProtectedHeader({ alg: 'RS256', kid: 'test' }).setSubject('reader').setIssuedAt().setIssuer(issuer).setAudience('other').setExpirationTime('5m').sign(privateKey);
  const other = await generateKeyPair('RS256');
  for (const token of [expired, wrongAudience, await signed({}, other.privateKey), 'invalid']) {
    const { response, calls } = await request(token);
    assert.equal(response.status, 401); assert.equal(calls, 0);
  }
  const { response, calls } = await request(await signed(), {}, '/', 'preview.workers.dev');
  assert.equal(response.status, 403); assert.equal(calls, 0);
});
test('missing configuration denies access', async () => {
  const { response, calls } = await request(await signed(), { ACCESS_AUD: '' });
  assert.equal(response.status, 503); assert.equal(calls, 0);
});
