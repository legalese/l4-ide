#!/usr/bin/env bash
# Render posts to A4 PDFs with a wide right margin for annotation.
#
#   blog/mkpdf.sh                       # posts 1, 2, 3
#   blog/mkpdf.sh blog/posts/05-*.md    # named posts
#
# Output: blog/build/<name>.pdf  (blog/build is gitignored)
#
# Geometry, as Meng set it on 2026-09-15: A4, left 0.75in, right 2.5in,
# top and bottom 1in. The text block is 5.02in — about 70 characters at
# 11pt Palatino, and the 2.5in right margin is for writing in.
#
# The one non-obvious step is the footnotes. The posts carry their notes
# as Markdown reference footnotes under "### Notes", and several run well
# past a page (note 2 of post 1 is ~1,500 words). Pandoc would hoist each
# to the bottom of the page where its marker falls, which LaTeX cannot
# lay out. So refs become superscripts and definitions become numbered
# paragraphs, leaving the notes where the author put them: at the back.
set -euo pipefail

cd "$(dirname "$0")/.."
OUT=blog/build; TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$OUT"


posts=("$@")
[ ${#posts[@]} -eq 0 ] && posts=(blog/posts/01-*.md blog/posts/02-*.md blog/posts/03-*.md)

for src in "${posts[@]}"; do
  n=$(basename "$src" .md)
  python3 - "$src" "$TMP/$n.md" <<'PY'
import io,re,sys
s=io.open(sys.argv[1],encoding='utf-8').read()
s=re.sub(r'^\[\^(\d+)\]:[ \t]*', r'**\1.** ', s, flags=re.M)   # definitions -> numbered paras
s=re.sub(r'\[\^(\d+)\]', r'^\1^', s)                            # references  -> superscripts

# A path or command in inline code is one unbreakable box to TeX, so a long
# one juts through the right margin (e.g. post 4's
# `git show 40a87269^:jl4/.../regcf.l4`). Insert a zero-width space after the
# separators; the header maps it to \allowbreak, which costs nothing when the
# span already fits. Fenced blocks are left alone -- fvextra wraps those.
def breakable(m):
    span = m.group(1)
    # Leave URLs alone: pandoc renders a zero-width space as \hspace{0pt},
    # which recurses fatally inside \url{} (post 3's knuthweb.pdf link).
    # Short spans do not need help either.
    if '://' in span or len(span) < 28:
        return m.group(0)
    return '`' + re.sub(r'([/:_])(?=.{6})', lambda g: g.group(1) + '\u200b', span) + '`'
out, infence = [], False
for line in s.split('\n'):
    if line.lstrip().startswith('```'): infence = not infence
    out.append(line if infence else re.sub(r'`([^`\n]+)`', breakable, line))
s='\n'.join(out)
io.open(sys.argv[2],'w',encoding='utf-8').write(s)
PY
  # blog index number for the footer: the filename prefix (01, 09, S1 ...)
  idx=${n%%-*}
cat > "$TMP/$n-head.tex" <<'TEX'
\usepackage{microtype}
\usepackage[htt]{hyphenat}
\usepackage{newunicodechar}
% Glyphs Palatino lacks. A missing one prints as NOTHING, with only a
% [WARNING] in the log, so each is mapped rather than left to chance and
% the build below refuses to ship a PDF with any unmapped one left.
\newunicodechar{→}{\ensuremath{\rightarrow}}
\newunicodechar{⊛}{\ensuremath{\circledast}}
\usepackage{fvextra}
% L4 samples run to 144 characters; wrap them inside the text block
% rather than letting them bleed through the right margin.
\RecustomVerbatimEnvironment{verbatim}{Verbatim}{%
  breaklines=true, fontsize=\small, xleftmargin=1.2em,
  breaksymbolleft=\raisebox{.7ex}{\tiny\ensuremath{\hookrightarrow}}}
\DefineVerbatimEnvironment{Highlighting}{Verbatim}{breaklines=true,fontsize=\small,commandchars=\\\{\}}
\sloppy
\emergencystretch=4em
\setlength{\parskip}{0pt}
\setlength{\parindent}{1.2em}
\usepackage{fancyhdr}
\pagestyle{fancy}\fancyhf{}
\renewcommand{\headrulewidth}{0pt}
\fancyfoot[L]{\small @@IDX@@}
\fancyfoot[R]{\small\thepage}
TEX

  sed -i '' "s/@@IDX@@/$idx/" "$TMP/$n-head.tex"

  # run from blog/posts so the posts' ../assets/ image paths resolve
  ( cd blog/posts && pandoc "$TMP/$n.md" --pdf-engine=xelatex -s -o "../../$OUT/$n.pdf" \
      -V geometry:a4paper,left=0.75in,right=2.5in,top=1in,bottom=1in \
      -V mainfont="Palatino" -V fontsize=11pt -V linestretch=1.15 \
      -V colorlinks=true -V linkcolor=black -V urlcolor=black \
      -H "$TMP/$n-head.tex" ) >"$TMP/$n.log" 2>&1 || { cat "$TMP/$n.log"; exit 1; }

  # A glyph the font lacks is dropped from the page in silence — the only
  # sign is this warning, and the PDF still builds. Refuse to ship one.
  if grep -q 'Missing character' "$TMP/$n.log"; then
    echo "ERROR: $n has characters no font in the document can print;" >&2
    echo "they would come out BLANK on the page. Add a \\newunicodechar" >&2
    echo "mapping for each to the header above, then rebuild:" >&2
    grep 'Missing character' "$TMP/$n.log" | sed 's/.*is no /  /; s/ in font.*//' | sort -u >&2
    rm -f "$OUT/$n.pdf"; exit 1
  fi
  grep -v '^\[WARNING\] \[makeStrict\]' "$TMP/$n.log" | grep '^\[WARNING\]' || true
  printf '%-34s %3s pages  %s\n' "$n" \
    "$(pdfinfo "$OUT/$n.pdf" | awk '/^Pages/{print $2}')" "$OUT/$n.pdf"
done
