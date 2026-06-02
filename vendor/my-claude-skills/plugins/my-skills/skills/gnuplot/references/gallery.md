# gnuplot ASCII gallery

Every chart below was rendered with gnuplot 6.0's `dumb` terminal from a Nushell table.
All snippets follow the skill's mechanism: write the table to a headerless TSV temp file, then
feed a plain-string gnuplot script to `gnuplot | complete | get stdout`. Color is available
(`set terminal dumb ... ansi256`, `lc rgb '…'`) but is omitted here so the output is copy-clean.

## Shared datasets

```nushell
[[x y]; [1 3] [2 7] [3 4] [4 9] [5 5] [6 8] [7 6]]                  | to tsv --noheaders | save -f /tmp/d.dat
[[month sales returns]; [Jan 100 40] [Feb 140 25] [Mar 90 60] [Apr 160 30] [May 130 45]] | to tsv --noheaders | save -f /tmp/m.dat
[[q a b]; [Q1 30 20] [Q2 45 25] [Q3 40 38] [Q4 55 30]]             | to tsv --noheaders | save -f /tmp/h.dat
[[x y e]; [1 3 0.6] [2 7 1.1] [3 4 0.8] [4 9 1.3] [5 5 0.7]]       | to tsv --noheaders | save -f /tmp/e.dat
[[v]; [3] [4] [6] [7] [8] [8] [12] [13] [14] [14] [15] [22] [23]]  | to tsv --noheaders | save -f /tmp/v.dat
[[date val]; ["2026-01-01" 10] ["2026-02-01" 14] ["2026-03-01" 9] ["2026-04-01" 18] ["2026-05-01" 15]] | to tsv --noheaders | save -f /tmp/t.dat
[[d o l h c]; [1 20 18 25 23] [2 23 21 28 22] [3 22 19 24 20] [4 20 17 23 21]] | to tsv --noheaders | save -f /tmp/f.dat
[[x y]; [1 10] [2 100] [3 1000] [4 10000] [5 100000]]             | to tsv --noheaders | save -f /tmp/lg.dat
```

---

## 1. Line / linespoints

```nushell
"set terminal dumb size 58,12
plot '/tmp/d.dat' u 1:2 w linespoints notitle" | gnuplot | complete | get stdout
```
```text
  9 +-------------------------------------------------+
  8 |-+     +        +      *+**     +       *A*    +-|
    |                      *    *          **   **    |
  7 |-+     A*           **      **      **       ***-|
  6 |-+   **  **        *          **  **           +*|
  5 |-+ **      **     *             A*             +-|
    |  *          **  *                               |
  4 |**     +       *A       +       +        +     +-|
  3 +-------------------------------------------------+
    1       2        3       4       5        6       7
```

## 2. Multiple series (categorical x, legend outside)

`using 0:N` puts the row index on x; `xtic(1)` labels it from column 1. `''` reuses the file.

```nushell
"set terminal dumb size 58,12
set key outside
plot '/tmp/m.dat' u 0:2:xtic(1) w lp t 'sales', '' u 0:3 w lp t 'returns'" | gnuplot | complete | get stdout
```
```text
  160 +--------------------------------+
  140 |-+   **A*       +    ** + ****+-|   sales ***A***
  120 |-****    ***       **         **| returns ###B###
  100 |*+          ***  **           +-|
      |               *A               |
   80 |-+                            +-|
   60 |-+            ##B###          +-|
   40 |###    +  ####  +   ####B#######|
   20 +--------------------------------+
     Jan     Feb      Mar     Apr     May
```

## 3. Scatter

```nushell
"set terminal dumb size 58,12
plot '/tmp/d.dat' u 1:2 w points pt 7 notitle" | gnuplot | complete | get stdout
```
```text
  9 +-------------------------------------------------+
  8 |-+     +        +       +       +        G     +-|
    |                                                 |
  7 |-+     G                                       +-|
  6 |-+                                             +-|
  5 |-+                              G              +-|
    |                                                 |
  4 |-+     +        G       +       +        +     +-|
  3 +-------------------------------------------------+
    1       2        3       4       5        6       7
```

## 4. Impulses (stem)

```nushell
"set terminal dumb size 58,12
plot '/tmp/d.dat' u 1:2 w impulses notitle" | gnuplot | complete | get stdout
```
```text
  9 +-------------------------------------------------+
  8 |-+     +        +       *       +        *     +-|
  7 |-+     *                *                *     +-|
  6 |-+     *                *                *     +-|
  5 |-+     *        *       *       *        *     +-|
  3 |-+     *        *       *       *        *     +-|
  2 |-+     *        *       *       *        *     +-|
  1 |-+     *        *       *       *        *     +-|
  0 +-------------------------------------------------+
    1       2        3       4       5        6       7
```

## 5. Step plot

```nushell
"set terminal dumb size 58,12
plot '/tmp/d.dat' u 1:2 w steps notitle" | gnuplot | complete | get stdout
```
```text
  9 +-------------------------------------------------+
  8 |-+     +        +       *       *        ********|
    |                        *       *        *       |
  7 |-+     **********       *       *        *     +-|
  6 |-+     *        *       *       *        *     +-|
  5 |-+     *        *       *       **********     +-|
    |       *        *       *                        |
  4 |-+     *        *********       +        +     +-|
  3 +-------------------------------------------------+
    1       2        3       4       5        6       7
```

## 6. Filled curve (function, no data file)

```nushell
"set terminal dumb size 58,12
set xrange [0:6.3]
plot sin(x) w filledcurves y=0 notitle" | gnuplot | complete | get stdout
```
```text
    1 +-------------------------------------------------+
  0.8 |-+   ##############    +       +       +       +-|
  0.6 |-+ ###################               sin *******-|
  0.2 |########################                       +-|
    0 |-+                       ########################|
 -0.2 |-+                         ####################+-|
 -0.4 |-+                           ################  +-|
 -0.8 |-+     +       +       +       +##########     +-|
   -1 +-------------------------------------------------+
      0       1       2       3       4       5       6
```

## 7. Bar chart (categorical)

```nushell
"set terminal dumb size 58,12
set style fill solid
set yrange [0:*]
plot '/tmp/m.dat' u 2:xtic(1) w boxes notitle" | gnuplot | complete | get stdout
```
```text
  160 +-----------------------------------------------+
  140 |-+   *************     +     *###########******|
  120 |-+   *###########*           *###########*#####|
  100 |******###########*************###########*#####|
   80 |#####*###########*###########*###########*#####|
   60 |#####*###########*###########*###########*#####|
   40 |#####*###########*###########*###########*#####|
   20 |#####*###########*###########*###########*#####|
    0 +-----------------------------------------------+
     Jan         Feb         Mar         Apr         May
```

## 8. Clustered bars (two values per category)

```nushell
"set terminal dumb size 58,12
set style data histogram
set style histogram clustered gap 1
set style fill solid
set yrange [0:*]
plot '/tmp/h.dat' u 2:xtic(1) t 'a', '' u 3 t 'b'" | gnuplot | complete | get stdout
```
```text
  60 +------------------------------------------------+
  50 |-+       +         +        +      ****       +-|
     |               *****               *##* ******* |
  40 |-+             *###*     ***#####  *##b #######-|
  30 |-+    ****     *###*     *#######  *######    +-|
  20 |-+    *######  *#######  *#######  *######    +-|
     |      *######  *#######  *#######  *######      |
  10 |-+    *######  *#######  *#######  *######    +-|
   0 +------------------------------------------------+
              Q1        Q2       Q3        Q4
```

## 9. Stacked bars

```nushell
"set terminal dumb size 58,12
set style data histogram
set style histogram rowstacked
set style fill solid
set yrange [0:*]
plot '/tmp/h.dat' u 2:xtic(1) t 'a', '' u 3 t 'b'" | gnuplot | complete | get stdout
```
```text
  90 +------------------------------------------------+
  80 |-+       +         +    ####################  +-|
  70 |-+            ##############################***-|
  60 |-+            #################################-|
  50 |-+  #######################################*  +-|
  30 |-+  ####################*########*#########*  +-|
  20 |-+  *#########*#########*########*#########*  +-|
  10 |-+  *#########*#########*########*#########*  +-|
   0 +------------------------------------------------+
              Q1        Q2       Q3        Q4
```

## 10. Histogram (bin one numeric column)

`smooth freq` sums the synthetic `(1.0)` weight per bin, so each bar is a count.

```nushell
"set terminal dumb size 58,12
binwidth = 5
bin(x) = binwidth * floor(x/binwidth)
set boxwidth binwidth
set style fill solid
plot '/tmp/v.dat' u (bin($1)):(1.0) smooth freq w boxes notitle" | gnuplot | complete | get stdout
```
```text
    4 +-----------------------------------------------+
  3.5 |-+     +   *#######*#######*   +       +     +-|
    3 |-+         *#######*#######*                 +-|
  2.5 |-+         *#######*#######*                 +-|
    2 |-+ *********#######*#######*       ********* +-|
  1.5 |-+ *#######*#######*#######*       *#######* +-|
    1 |-+ *#######*#######*#######*********#######* +-|
  0.5 |-+ *#######*#######*#######*#######*#######* +-|
    0 +-----------------------------------------------+
     -5       0       5       10      15      20      25
```

## 11. Error bars

```nushell
"set terminal dumb size 58,12
plot '/tmp/e.dat' u 1:2:3 w yerrorbars notitle" | gnuplot | complete | get stdout
```
```text
  11 +------------------------------------------------+
  10 |-+   +     +     +      +     +    ***    +   +-|
   9 |-+                                  A         +-|
   8 |-+        ***                      ***        +-|
   7 |-+         A                                  +-|
   5 |-+        ***                                 +*|
   4 |-+                     *A*                    +*|
   3 |*+   +     +     +     ***    +     +     +   +-|
   2 +------------------------------------------------+
     1    1.5    2    2.5     3    3.5    4    4.5    5
```

## 12. Candlestick (financial: x, open, low, high, close)

```nushell
"set terminal dumb size 58,12
set boxwidth 0.4
plot '/tmp/f.dat' u 1:2:3:4:5 w candlesticks notitle" | gnuplot | complete | get stdout
```
```text
  28 +------------------------------------------------+
  26 |-+     +       +*       +       +       +     +-|
     |*               *                               |
  24 |****        *********           *             +*|
  22 |-+ *        *********       *********         +*|
  20 |****            *           *********        ***|*
     |*                               *              *|
  18 |*+     +       +        +       +       +     +*|
  16 +------------------------------------------------+
     1      1.5      2       2.5      3      3.5      4
```

## 13. Smoothing (raw points + spline)

```nushell
"set terminal dumb size 58,12
plot '/tmp/d.dat' u 1:2 w points pt 7 t 'raw', '' u 1:2 smooth csplines t 'csplines'" | gnuplot | complete | get stdout
```
```text
  10 +------------------------------------------------+
   9 |-+     +       +       ###      +       +     +-|
   8 |-+                   ##  ###        raw ##### +-|
   7 |-+   ###            ##     ##  cspline#########-|
     |   ###  ##         ##       ##      ##         #|
   6 |-+##      ##      #           ##  ###         +-|
   5 |-#         ###  ##             ####           +-|
   4 |#+     +     ####       +       +       +     +-|
   3 +------------------------------------------------+
     1       2       3        4       5       6       7
```

## 14. Log-scaled axis

```nushell
"set terminal dumb size 58,12
set logscale y
plot '/tmp/lg.dat' u 1:2 w linespoints notitle" | gnuplot | complete | get stdout
```
```text
  100000 +--------------------------------------------+
         |+    +    +     +     +    +     +  ****** +|
   10000 |-+                             **A**      +-|
         |+                        ******            +|
    1000 |-+                 ***A**                 +-|
         |+            ******                        +|
     100 |-+      **A**                             +-|
         |+ ******  +     +     +    +     +    +    +|
      10 +--------------------------------------------+
         1    1.5   2    2.5    3   3.5    4   4.5    5
```

## 15. Time series (date x-axis)

```nushell
"set terminal dumb size 58,12
set xdata time
set timefmt '%Y-%m-%d'
set format x '%b'
plot '/tmp/t.dat' u 1:2 w linespoints notitle" | gnuplot | complete | get stdout
```
```text
  18 +------------------------------------------------+
  17 |-+  +     +    +     +    +     **  ****   +  +-|
  16 |-+                             *        ****  +-|
  15 |-+                           **             **A-|
  14 |-+       **A*               *                 +-|
  12 |-+   ****    ***          **                  +-|
  11 |-****           **       *                    +-|
  10 |*+  +     +    +  ***+ ** +     +    +     +  +-|
   9 +------------------------------------------------+
    Jan  Jan   Jan  Feb   Feb  Mar   Mar  Apr   Apr  May
```

## 16. Multiplot (stacked subplots)

```nushell
"set terminal dumb size 58,22
set multiplot layout 2,1
unset key
plot '/tmp/d.dat' u 1:2 w lines
plot '/tmp/d.dat' u 1:2 w impulses
unset multiplot" | gnuplot | complete | get stdout
```
```text
  9 +-------------------------------------------------+
  8 |-+     +        +     **+**     +       ***    +-|
  7 |-+     **            *     *          **   ****+-|
  6 |-+   **  **         *       **      **         **|
    |   **      **     **          **  **             |
  5 |-+*          **  *              **             +-|
  4 |**     +       **       +       +        +     +-|
  3 +-------------------------------------------------+
    1       2        3       4       5        6       7
  9 +-------------------------------------------------+
  8 |-+     +        +       *       +        *     +-|
  7 |-+     *                *                *     +-|
  6 |-+     *                *                *     +-|
  5 |-+     *        *       *       *        *     +-|
  3 |-+     *        *       *       *        *     +-|
  2 |-+     *        *       *       *        *     +-|
  1 |-+     *        *       *       *        *     +-|
  0 +-------------------------------------------------+
    1       2        3       4       5        6       7
```

## 17. Pure functions (no data file)

```nushell
"set terminal dumb size 58,12
set xrange [-6.3:6.3]
set samples 200
plot sin(x) t 'sin', cos(x) t 'cos'" | gnuplot | complete | get stdout
```
```text
    1 +-----------------------------------------------+
  0.8 |+##*   **      +    ## + ##*   **     +     ##+|
  0.6 |-* ##    *         ##    *##     * sin ***##**-|
  0.2 |*+  ##    *       #     *   #     *cos #######-|
    0 |-+   ##    *     #     *     #     *    ##   +-|
 -0.2 |-+    #     *   #     *       #     *   #    +*|
 -0.4 |-+     #     * #    **         #     * #     *-|
 -0.8 |++      ##   ##*   **  +       +##   ##*   **++|
   -1 +-----------------------------------------------+
      -6      -4     -2       0       2      4       6
```

---

## Nushell integration

The point of the skill: the data comes from a Nushell pipeline, not a pre-made file.

### Aggregate raw rows, then chart the counts

```nushell
let events = [sale sale refund sale refund sale sale refund refund sale sale sale]
$events | wrap kind | group-by kind | items {|k v| {kind: $k, n: ($v | length)} }
| to tsv --noheaders | save -f /tmp/agg.dat
"set terminal dumb size 58,11
set style fill solid
set yrange [0:*]
plot '/tmp/agg.dat' u 2:xtic(1) w boxes notitle" | gnuplot | complete | get stdout
```
```text
  8 +-------------------------------------------------+
  7 |########################*                      +-|
  6 |########################*                      +-|
  5 |########################*************************|
  3 |########################*########################|
  2 |########################*########################|
  1 |########################*########################|
  0 +-------------------------------------------------+
  sale                                             refund
```

### Compute a series in Nushell, then plot it

```nushell
1..12 | each {|x| {x: $x, y: ($x * $x)} } | to tsv --noheaders | save -f /tmp/sq.dat
"set terminal dumb size 58,11
plot '/tmp/sq.dat' u 1:2 w linespoints notitle" | gnuplot | complete | get stdout
```
```text
  160 +-----------------------------------------------+
  140 |-+     +       +       +       +       +     **|
  120 |-+                                       **A*+-|
  100 |-+                               **A***A*    +-|
   60 |-+                           **A*            +-|
   40 |-+                   **A***A*                +-|
   20 |-+     +     **A***A*  +       +       +     +-|
    0 +-----------------------------------------------+
      0       2       4       6       8       10      12
```

---

## What does NOT work in the dumb terminal

- **Heatmaps / `with image`** — the dumb terminal cannot draw a pixel grid. `set view map` +
  `with image` produces an empty frame with an orphan colorbox. For a 2D field, fall back to a
  PNG terminal, or print the matrix as a Nushell table.
- **True color fidelity** — `ansi256` gives 256 colors, but the shape is still character cells.
