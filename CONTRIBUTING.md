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
