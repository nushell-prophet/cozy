---
task-name: verify-vendor-failfast
status: draft
created: 2026-05-11
updated: 2026-05-11
---

# Verify vendor.nu fail-fast on HTTP errors and GH_TOKEN honoring

## Task from user (original)

create the necessary number of todos for checking the introduced functionality after 288a2c950544afee20c81a329b3a356a45c92fd2 (the tip of source/master)

## Task description (extended version)

`f624b24 fix(vendor): fail-fast on HTTP errors and honor GH_TOKEN`
introduced two behaviors in `toolkit/vendor.nu`:

1. `curl -fsSL` (was `-sL`) — `-f` makes curl exit non-zero on 4xx/5xx so
   a JSON rate-limit error body never reaches `tar xz` as "not in gzip
   format" (previous failure mode masked the real cause).
2. New `gh-curl-args` helper reads `$env.GH_TOKEN` (or `$env.GITHUB_TOKEN`)
   and adds `-H "Authorization: bearer …"`, bumping the anonymous 60
   req/hr GitHub API limit to 5000.

Goal: confirm both behaviors actually fire under the conditions they
target.

## Requirements

- [ ] Without a token, `vendor.nu` succeeds on first invocation against fresh API state
- [ ] Forced 4xx (e.g. mangled `vendor.yml` github path → 404) makes `vendor.nu` exit non-zero with the curl error visible — NOT a downstream `tar: not in gzip format` confusion
- [ ] `vendor.nu` does NOT swallow stderr — error is printed
- [ ] With `GH_TOKEN=<valid-token>` set, the curl invocation includes the `Authorization: bearer …` header (verify via `curl -v` trace or by exhausting anonymous limit first)
- [ ] With `GITHUB_TOKEN` set instead of `GH_TOKEN`, same header appears (fallback works)
- [ ] With both unset, no Authorization header is sent
- [ ] `vendor check` subcommand also uses `gh-curl-args` for the `nushell-prophet/repos` listing (not just `fetch-tarball`)
- [ ] An invalid `GH_TOKEN` (e.g. `bearer foo`) produces a clear 401 error from curl, not a silent `tar` failure

## Implementation plan

- [ ] Step 1: baseline — `nu toolkit/vendor.nu` against a clean `vendor/` succeeds
- [ ] Step 2: introduce synthetic failure — temporarily edit `toolkit/vendor.yml` to point one entry at a nonexistent repo; expect fail-fast
- [ ] Step 3: revert, then export `GH_TOKEN=<token>`; run with `curl -v` shimmed (alias `curl` to `curl -v 2>&1 | tee /tmp/curl-trace`) and confirm `Authorization` header present
- [ ] Step 4: `unset GH_TOKEN; export GITHUB_TOKEN=<token>`; rerun and confirm header still present (fallback)
- [ ] Step 5: `export GH_TOKEN=bogus`; expect a clean 401 message, not a gzip parse error

## Affected files

- Existing files: `toolkit/vendor.nu`, `toolkit/vendor.yml`
- New files: none
