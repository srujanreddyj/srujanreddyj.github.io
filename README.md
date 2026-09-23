# Systems in Practice

Jekyll source for Srujan Jabbireddy's writing, guides, and case studies.

## Build and check

```sh
bundle install
./scripts/build
bundle exec ruby scripts/check_site
ruby tests/content_policy.rb
```

Use `./scripts/build` in deployment pipelines. It validates public metadata and generates topic pages before Jekyll runs. The topic HTML source files are committed so ordinary Jekyll previews also work; their metadata comes from `_data/topics.yml`.

`./scripts/server` validates metadata, updates topic pages, then starts the local preview. Browser behavior checks live in `tests/browser.cjs`; run them against the preview with Playwright installed and `SITE_URL` set to its origin. `PLAYWRIGHT_MODULE` can point to an existing Playwright installation.

The GitHub workflow checks the build and reader-access code. It does not deploy. GitHub reports this repository is public and Pages currently uses legacy branch builds. Before using validation as a deployment gate, switch Pages to GitHub Actions and publish only the validated build. This implementation does not change that account setting. Cloudflare's checked-in build command already uses `./scripts/build`.

## Publish public writing

Post front matter must include these fields:

```yaml
layout: post
title: A descriptive title
visibility: public
published: false
content_type: article
topics: [data-platforms]
tags: [iceberg]
summary: One or two sentences describing the post.
featured: false
```

Set `published: true` when ready. Valid formats are `article`, `note`, and `guide`. Topic IDs live in `_data/topics.yml`; the first topic is primary. Guides have their own index and are also searchable in Writing. `featured: true` selects an article for the homepage, which shows up to three in date order. Homepage recent writing excludes guides.

Existing `categories: learnings` values remain to preserve article URLs. Use `topics` for reader-facing subject organization. The former `hidden_home` and `study_guide` fields have been replaced by `content_type`; they were never access controls.

## Restricted posts

Never commit restricted posts or assets here. `visibility: restricted` causes the public validation step to fail. Use a private source repository outside this checkout and the [reader deployment](deployment/readers/README.md).

The reader Worker and private build path are implemented, but sign-in requires a configured Cloudflare Access application, verified hostname, audience ID, approved-email list, and live access checks. Leave `reader_library_url` empty until those checks pass. A blank value keeps the public sign-in link hidden.

All files under `references/` and `presentations/` are restricted. They have been moved out of this public working tree into a separate local private library. These paths are ignored, excluded from public builds, and rejected by validation if reintroduced. Previously pushed copies still exist in Git history and on GitHub until the removal is published and historical exposure is addressed. Drafts in this public repository are also readable as source.
