---
name: gnuplot
description: >
  Render a Nushell table as an ASCII chart in the terminal using gnuplot's dumb terminal.
  Use when the user asks to "plot", "chart", "graph", or "visualize" tabular data they have in
  a Nushell pipeline or variable, or asks for a line chart, scatter plot, bar chart, or histogram
  of nu data shown as text in the terminal (no image file). Trigger on "plot this table",
  "show a chart of", "graph these numbers", "ascii chart", "gnuplot".
version: 0.1.0
---

# Plot Nushell tables with gnuplot (ASCII)

Turn a Nushell table into a text chart drawn in the terminal. Output is gnuplot's `dumb`
terminal — characters, no image file. Good for eyeballing data and iterating in the loop.

Requires `gnuplot` on PATH (`gnuplot --version`). If missing, install it (`brew install gnuplot`).

## The mechanism

Four steps. **Always go through a temp data file** — do not inline data with `'-'`/`e`.

1. Get the data into a Nushell table with numeric y-column(s).
2. Write it as headerless TSV to a temp file:
   `$data | to tsv --noheaders | save -f /tmp/plot.dat`
3. Build a **plain** gnuplot script string (not `$"..."` interpolation) that reads that path.
4. Pipe it to gnuplot and read stdout:
   `$script | gnuplot | complete | get stdout`

```nushell
let data = [[x y]; [1 2] [2 4] [3 9] [4 16] [5 25]]
$data | to tsv --noheaders | save -f /tmp/plot.dat
"set terminal dumb size 72,22
set title 'y = x^2'
plot '/tmp/plot.dat' using 1:2 with linespoints title 'y'
" | gnuplot | complete | get stdout
```

**Why a temp file, not inline `'-'` data:** the data block stays out of the script string, so
there is nothing to escape, and the same file can be referenced multiple times for multi-series
plots. Inline data forces `$"..."` interpolation (which then needs `\(` `\)` escaping for
`xtic(1)` etc.) and forces you to repeat the whole data block once per plotted series.

## Recipes

A worked gallery of 17+ chart types with real rendered output — bars (clustered/stacked),
histogram, impulses, steps, filled curves, error bars, candlesticks, smoothing, log axes,
time series, multiplot, functions, and nu-pipeline→chart examples — is in
[references/gallery.md](references/gallery.md). The essentials:

All read `/tmp/plot.dat` written as in step 2. Column numbers in `using` are **1-based**;
`using 0:N` uses the row index (pseudo-column 0) as x — used for categorical x-axes.

### Line / linespoints
```nushell
"set terminal dumb size 72,22
plot '/tmp/plot.dat' using 1:2 with lines title 'y'
" | gnuplot | complete | get stdout
```

### Multiple series (shared x, columns 2 and 3)
`''` reuses the previously named file. `set key outside` keeps the legend off the plot.
```nushell
"set terminal dumb size 72,18
set key outside
plot '/tmp/plot.dat' using 1:2 with lines title 'a', \
     ''             using 1:3 with lines title 'b'
" | gnuplot | complete | get stdout
```

### Scatter
```nushell
"set terminal dumb size 72,18
plot '/tmp/plot.dat' using 1:2 with points pt 7 title 'a'
" | gnuplot | complete | get stdout
```

### Bar chart with categorical labels (column 1 = label, column 2 = value)
```nushell
"set terminal dumb size 72,18
set style fill solid
set yrange [0:*]
plot '/tmp/plot.dat' using 2:xtic(1) with boxes title 'sales'
" | gnuplot | complete | get stdout
```

### Histogram of one numeric column (bin a single column)
```nushell
"set terminal dumb size 72,18
binwidth = 5
bin(x) = binwidth * floor(x / binwidth)
set boxwidth binwidth
set style fill solid
plot '/tmp/plot.dat' using (bin($1)):(1.0) smooth freq with boxes notitle
" | gnuplot | complete | get stdout
```

## Gotchas

| Problem | Fix |
|---|---|
| Header row plotted as a data point | `to tsv --noheaders` (not plain `to tsv`) |
| `(` / `)` errors in the script | Don't use `$"..."` interpolation — keep the script a plain `"..."` string so `xtic(1)`, `bin($1)` pass through literally |
| Categorical x labels (months, names) | `using 2:xtic(1)` (bars) or `using 0:2:xtic(1)` (lines) — column 1 supplies tic labels |
| `$1`, `$2` (gnuplot column refs) | Pass through literally in a plain `"..."` string — Nushell only interpolates in `$"..."`. Keep the script plain and write `$1` as-is |
| Nulls / non-numeric y values | Filter in Nushell first (`where ($it.y | describe) == int`, or `compact`) before writing the file |
| Plot too wide/narrow for terminal | Tune `set terminal dumb size W,H` (W ≈ 70–100, H ≈ 18–30) |
| Legend overlapping the curve | `set key outside` or `set key off` |
