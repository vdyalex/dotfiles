#set page(
  margin: .5in,
  header: none,
  footer: none,
  numbering: none,
)
#set text(
  font: "Helvetica",
  size: 10pt,
  fill: rgb("#1f2328"),
  weight: 400,
)
#set par(
  leading: 1.15em,
  spacing: 2.65em,
  linebreaks: "optimized",
)

// GitHub-style Links with custom underline
#show link: it => {
  underline(
    stroke: (thickness: .65pt, paint: rgb("#0969da")),
    offset: 2pt,
    text(fill: rgb("#0969da"), it),
  )
}

// GitHub-style Headings (Bold, specific sizes)
#show heading: it => {
  let size = if it.level == 1 {
    1.375em
  } else if it.level == 2 {
    1.25em
  } else if it.level == 3 {
    1.125em
  } else if (it.level == 4) {
    1em
  } else if it.level == 5 {
    .875em
  } else {
    .85em
  }

  let above = if it.level == 1 {
    0em
  } else {
    1.5em
  }

  let stroke = if it.level <= 2 {
    (bottom: .5pt + rgb("#d1d9e0b3"))
  } else {
    none
  }

  block(
    above: above,
    below: 1em,
    width: 100%,
    stroke: stroke,
    pad(bottom: .7em, [
      #text(weight: 600, size: size, it.body)
    ]),
  )
}

// GitHub-style Code Blocks (Gray background, monospaced)
// 1. Styling for fenced code blocks (Multi-line)
#show raw.where(block: true): set block(
  fill: rgb("#818b981f"),
  inset: 10pt,
  radius: 6pt,
  width: 100%,
)
#show raw.where(block: true): set text(font: "Menlo", size: .85em)

// 2. Styling for inline code (Single-line backticks)
#show raw.where(block: false): box.with(
  fill: rgb("#818b981f"),
  inset: (x: 3pt, y: 0pt),
  outset: (y: 3pt),
  radius: 3pt,
)
#show raw.where(block: false): set text(font: "Menlo", size: .85em)

// GitHub-style Blockquotes (Vertical bar)
#show quote: it => {
  set block(
    inset: (left: 10pt),
    stroke: (
      left: 4pt + rgb("#dfe2e5"),
    ),
  )
  it
}

$body$
