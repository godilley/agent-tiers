# Docs style: the one pattern every human-facing page follows

Scope: `README.md` and `docs/*.md`, as each page is migrated (2026-10-21: README, usage, work-shapes, levels, plan-wave, glossary; the reference pages follow). Not `docs/prompts/`, templates, skills or cards. Tools: `scripts/docs-nav.sh`
(the tab bar) and `scripts/docs-lint.sh` (links, the four markdown traps). Every rule below was settled by
rendering variants on GitHub and picking (the record is in the maintainer's notes, not here), so change a rule by rendering, not by taste.

## Page skeleton, top to bottom

1. `<a name="top"></a>`, a centred `<h1>`, one italic tagline at normal size.
2. The six-tab nav bar from `docs-nav.sh` (current page bold and unlinked), wrapped in `<div align="center">`
   with blank lines inside the div, then `<hr>`. The generator's default width (108) fits the repo home page's
   README box; the div centres the same bar in the wider file view. One width on every page. Day-to-day pages
   share one bar (README, Why delegate, Work shapes, Levels, Plan waves, Glossary); reference pages will share
   another (README, Install, Hooks, What ships, Extending, Glossary) once migrated. Never hand-edit a bar; regenerate it.
3. One-line `[!NOTE]` saying what the page is. Notices stay one line.
4. One glance table (rules below). Its first column links to the sections.
5. One-line `[!TIP]` for the one term the page leans on.
6. Sections, each: blank line, `---`, a pinned `<a name="...">`, a centred `<h3>` with the emoji on both
   sides and the weight spacer, a centred `<sub>` subtext, the body.

A section heading, exactly:

```html
<h3 align="center"><img align="left" src="assets/spacer.svg" width="30" height="30" alt="">⏳ Title ⏳<a href="#top"><img align="right" src="assets/nav-up.svg" alt=""></a></h3>
<p align="center"><sub>One line under it. <b>One bold phrase</b> in some subtexts, never all.</sub></p>
```

The left spacer balances the right-floated back-to-top icon; without it the title sits off-centre. From
`README.md` the asset paths start `docs/assets/`.

## Tables

- Three columns when a real line exists: the name (emoji, bold, linked to its section), the gist (bold
  phrase, `<br>`, `<i>&rsaquo; fragment</i>` under six words), and "As it looks" (one real line in a code
  span, `<br>`, a `<sub><i>` caption). Two columns otherwise, same gist cell.
- In a glance table every header cell is `Text<br><img src="assets/spacer.svg" width="N" height="1">`: the
  break keeps every header two lines with the text on top; the code column gets `width="1"`. In a small
  example table only the first header carries a spacer, sized so its column never wraps.
- The first column never wraps: its spacer is at least the widest first cell. The last column of a
  two-column table fills the remaining width (about 650px beside a 200px first column).
- No number column, no empty header row (GitHub renders it as a blank bar), no `|` inside a code span
  without `\|`, no `<kbd>` inside a cell.
- A real line is short, under 55 characters as a guide, because long lines squeeze the first two columns
  until they wrap. Trimmed is marked `[...]`; a reworded line is a summary and its caption says so.

## Body

- `####` subheads break a section into two or three groups; under each, `<kbd>Lead-in</kbd> text` lines
  joined by `<br>`.
- A caveat is a `[!WARNING]`; a prerequisite is `[!IMPORTANT]`. One of each per section at most.
- A guard story is a diff block in the e form: the denied line, a plain context line with the reason, the
  line that ran instead. Never a trailing `#` comment on a coloured line.

```diff
- grep -r "pattern" src/
  skips files it deems binary, says nothing
+ rg "pattern" src/
```

- Real examples sit in the open under `#### Real example`, as a small table with named headers, an
  elapsed-time timeline (`0h00`, `0h32`), or a trimmed capture in a code block; never a paragraph of numbers. A fold (`<details>`) is only for
  an aside the page does not need; `<summary>` text is bold with `<b>`, not `**`.
- Screenshots are never folded.
- No clocks, no UTC stamps. Plan row ids only inside a real line or an example about rows.

## Words

- Say "helper" for a sub-agent and "main session" for the Lead on day-to-day pages; the tier names
  appear where the glossary defines them. Hook ids stay in backticks.
- Numbers come from a real session and say so once ("one maintainer's log over two months"); they rank
  what is common, they are not a promise.
- Plain words. No em or en dashes, no curly quotes, ASCII except emoji in headings and table names.

## Before pushing a page

```sh
sh scripts/docs-nav.sh <current> <label>=<link> ...   # regenerate the bar
sh scripts/docs-lint.sh                                # links, setext trap, summary bold, icon headings
```

Then render it on GitHub (a throwaway branch) and look at the tables at full width: the first column
unwrapped, every header the same height, the bar filling the body.
