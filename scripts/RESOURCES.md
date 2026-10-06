# Maintain the Resources directory

Obsidian is the human-editable source. Google Drive syncs the vault between your devices. Git commits publish the generated directory. The website and CI never read Drive or Obsidian.

## Publish changes

1. Add or edit entries in `3-Resources/Articles-Blogs/Engineering AI Agents and Career Resource Collection.md` in your vault. Let Drive finish syncing before importing.
2. From this repository, run:

   ```sh
   export OBSIDIAN_VAULT="/path/to/your/vault"
   ./scripts/publish_resources_check
   # Or select the source file directly:
   ./scripts/publish_resources_check --source "/path/to/collection.md"
   ```

   This syncs `_data/resources.json`, runs parser tests, validates all site metadata, builds Jekyll, and checks the built pages. Install the repository's Ruby dependencies with `bundle install` first.
3. Review `git diff -- _data/resources.json`. Check that the titles, summaries, notes, and linked sources are suitable for the public website. Notes imported here are public, including references to other note names.
4. Resolve errors and review warnings. To validate an already-generated file without the vault:

   ```sh
   ruby scripts/validate_resources
   ruby tests/resources.rb
   ./scripts/build
   bundle exec ruby scripts/check_site
   ./scripts/server
   # Open http://localhost:4000/resources/
   ```

5. Commit and push through the existing publishing workflow:

   ```sh
   git add _data/resources.json
   git commit -m "Update reading resources"
   git push
   ```

Do not edit the generated JSON by hand. A sync replaces it from the complete source collection, including removing resources deleted from that collection. No timestamp or file modification time is generated, so unchanged input produces unchanged output. A failed parse or validation leaves the previous file intact. Sync itself never commits or pushes.

## Entry format

```markdown
## AI Engineering and Developer Practice

- **[Example guide](https://example.org/guide)** — A short, factual description.
  Status: `to-read` · Topics: `AI agents`, `automation`
  Purpose: `reference` · Type: `guide` · Added: `2026-10-06`
  Notes: Optional context you are willing to publish.
```

Use one list entry per URL. Put metadata on indented lines as shown. The parser accepts the current collection's bold Markdown link and dash format. Malformed link entries and unknown metadata fail with a line number. Plain Topic Index and Related notes sections are navigation, not additional resources; maintain resource metadata on the entries themselves.

- Required: title, HTTP(S) URL, status, and at least one controlled topic label.
- Status: `to-read`, `reading`, `read`, `deprioritized`.
- Purpose: `learning`, `reference`, `interview-prep`, `career`, `leadership`, `finance`, `unspecified`.
- Type: `book`, `guide`, `repository`, `directory`, `article`, `documentation`, `unspecified`.
- Topic labels: `TOPICS` in `scripts/resources.rb` is the controlled vocabulary, seeded from the source's per-entry topics. Add a label there when introducing a new topic. The page builds its filter options from the data; no page edits are needed.
- `source_collection` records the collection's vault-relative logical name, even when `--source` selects another local copy. This importer handles one complete collection, not incremental files from multiple collections.
- `added_at` uses the explicit `Added` date in `YYYY-MM-DD` form. Missing dates stay `null`; filesystem dates would invent history.
- Optional notes remain plain text. An Obsidian cross-reference without a description moves to notes and leaves the summary blank. The page labels the missing summary rather than inventing one.

When explicit purpose or type is absent, the importer uses limited rules from the section, title, summary, and URL: learning/career/finance sections; interview and leadership topics; titles saying Open Book or Guide; summaries saying directory/list of; documentation paths; GitHub repositories. Explicit metadata wins. It leaves other types or purposes `unspecified` and reports them for review. It never fetches linked pages or generates descriptions.

## Duplicate policy and validation

The canonical key is the URL. Normalize host and scheme case, default ports, and an empty path to `/`. Preserve path case, trailing slashes, query parameters, and fragments because they can identify different documents. Redirect aliases or tracking variants need manual consolidation; the sync does not make network requests.

Duplicate normalized URLs fail the sync and name both entries. Consolidate them into one entry with multiple topics. Conflicting statuses and summaries must be resolved in Obsidian, not silently chosen by the importer. Validation also rejects unsupported enum values, missing titles/topics, unknown topics, non-HTTP URLs, credentials in URLs, and malformed dates.

The default view groups each resource once by purpose. Topic filters match any of its labels. Search and filters work in the browser without a server and store their state in the page URL. With JavaScript disabled, all resources remain readable. These reading statuses describe this collection, not access permissions.

## Initial source cleanup

The initial import contains 11 unique resources. None has an added date. Breakscale and The Accidental CTO have only a link to another Obsidian note instead of a summary. Type needs review for Trust Outcomes, Not Agents; AI Company Hiring Challenges Hub; Breakscale; and From Zero to Option Hero. Set explicit Type metadata after reviewing those sources.

The hand-written Topic Index also lists The Art of Debugging under ML engineering, while its entry does not. The importer preserves per-entry topic metadata. Add ML engineering to that entry if the index reflects your intended classification.
