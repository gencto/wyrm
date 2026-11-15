# site — wyrm.gencto.uk

The project's public pages, plain static files with no build step:

- `index.html` — home page
- `wiki.html` — the wiki (tree, keys, links, dataflow blocks, sites, Studio)
- `install.html` — the install picker: a way to run WYRM, links, a site name → `wyrmd.json5`,
  `compose.yaml` and the commands, built in the browser by `assets/dc.js` from the page's
  `<template id="view">`
- `img/` — Studio screenshots and dataflow block pictures

Look at it locally with `python3 -m http.server -d site 8000`. Published by GitHub Pages from
`packaging/site/pages-workflow.yml` (copy it to `.github/workflows/site.yml`); `CNAME` holds the domain.
What the pages say about the broker follows `CLAUDE.md` and `docs/`: change them together.
