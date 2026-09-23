# Protected reader deployment

This is a separate deployment template. It is not active on the public site. Never put private posts, attachments, reader emails, credentials, or private output in this public repository.

The Worker verifies Cloudflare Access JWTs before fetching any static asset. It checks issuer, audience, signature, expiration, required identity claims, hostname, and the approved-email list. All responses disable shared caching. Missing configuration denies access.

## Prepare a private source

Create a private repository outside the public site checkout with any of `_posts/`, `references/`, `presentations/`, and `assets/`. Everything in `references/` and `presentations/` inherits restricted access, including nested files and source downloads. Resource-only libraries do not need any posts. Each post uses the same public-site fields, except `visibility: restricted`. Use `published: false` for unfinished posts. The library uses one reader group for all content.

From the public site checkout:

```sh
READER_BASE_URL=https://readers.example.com bundle exec ruby scripts/build-private-library /absolute/path/to/private-content
```

Replace the example domain with the verified reader domain. The script builds private posts and resource indexes with shared templates into the private repository's `_site/`. Reference Markdown renders as pages with original source downloads. Presentations retain their layout; embedded image bytes are extracted into protected files in the build output, while originals remain unchanged. The build rejects files above the host's 25 MiB static-asset limit. It rejects a private source inside this public repository. Keep that output out of Git and public CI artifacts.

Copy `package.json`, `package-lock.json`, `worker.js`, and `wrangler.example.jsonc` into the private repository. Rename the configuration copy to `wrangler.jsonc`. Its `_site` path then points at the private build output. Run `npm ci` there. Do not use the public site's Wrangler configuration for this deployment.

## Configure before deploying real content

1. Verify ownership of the reader hostname and current hosting routes.
2. Create a Cloudflare Access self-hosted application covering the entire hostname. Enable the chosen sign-in method, allow only approved email addresses, and select a session lifetime. Do not add an Everyone or Bypass policy.
3. Set `ACCESS_TEAM_DOMAIN`, `ACCESS_AUD`, and `READER_HOSTNAME` in the private configuration. Add the verified custom-domain route.
4. Set `APPROVED_EMAILS` as a Worker secret containing a JSON array of the same approved emails. Keep the Access policy and Worker list aligned. The second check lets list removal reject otherwise-valid sessions.
5. Retain `assets.run_worker_first: true`, `workers_dev: false`, and `preview_urls: false`. Check for older Worker versions, alternate domains, origin URLs, GitHub Pages copies, and any other deployment that could serve the private assets.
6. Deploy a harmless test post first. Check approved, unapproved, anonymous, expired, revoked, and forged credentials against direct HTML, PDF/image, and search paths. Confirm the sign-in return URL and sign-out flow through the real Access service.
7. Move the selected posts and their assets into private storage only after those checks pass. Remove public copies and review history/caches; restriction cannot undo prior disclosure.
8. Set the public `_config.yml` `reader_library_url` to the verified protected origin only after live access checks pass. That enables the footer sign-in link.

To revoke someone, remove them from both the Access allowlist and the Worker secret, then revoke their active Access sessions. Confirm a fresh request to both a post and an attachment is denied.

## Local verification

```sh
npm ci
npm test
```

Tests use locally signed tokens and mock asset storage. They verify the Worker boundary, not real Cloudflare sign-in, account configuration, or deployed routing.

Sources: [Cloudflare Access on Workers](https://developers.cloudflare.com/workers/configuration/cloudflare-access/), [run the Worker before static assets](https://developers.cloudflare.com/workers/static-assets/routing/worker-script/), [validate Access JWTs](https://developers.cloudflare.com/cloudflare-one/access-controls/applications/http-apps/authorization-cookie/validating-json/).
