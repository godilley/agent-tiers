# Contributing

This public repo is a **curated mirror** of a private working repo: each commit here is a
reviewed, leak-scanned snapshot, published as a whole. That shapes what contributions can land:

- **Issues: very welcome.** Bug reports, portability failures (a shell or OS where a selfcheck
  breaks), unclear docs, guard false positives - all genuinely useful, and the fastest way to
  change the kit.
- **Pull requests: can't merge directly.** There is no shared history for a PR to merge into -
  changes land via the next curated release. If you've written a fix, open an issue with the
  patch or a link to your branch; if it's adopted you'll be credited in the changelog entry.

Security-relevant findings (a guard bypass, a leak in shipped content): please use a private
report (GitHub's "Report a vulnerability" if enabled, or the contact on the profile) rather
than a public issue, so a fix can ship before the gap is advertised.

## Bumping the companion plugin pins (maintainers)

The kit's marketplace lists two third-party companion plugins, each pinned to a commit in `.claude-plugin/marketplace.json`
(entries `caveman` and `ponytail`, field `.source.sha`). Bump one when upstream ships something
worth passing on.

1. Find the new upstream commit: `git ls-remote https://github.com/<owner>/<repo> HEAD`, or a release tag.
2. Read the upstream diff between the old and new sha. Hooks first: they run on every user's machine.
3. Check the license and the plugin name are unchanged.
4. Edit only the `sha` value, then `jq . .claude-plugin/marketplace.json` to confirm it still parses.
5. Install from a throwaway `CLAUDE_CONFIG_DIR` and check `plugins/installed_plugins.json` records
   the same `gitCommitSha` as the pin:
   `jq -r '.plugins[] | select(.name=="caveman" or .name=="ponytail") | .source.sha' .claude-plugin/marketplace.json`
