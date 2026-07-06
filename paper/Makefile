# Build the ICAIL paper (English + Japanese).
#
# The final `qpdf --linearize` step is REQUIRED, not cosmetic: the LaTeX build
# emits a duplicate /ToUnicode key in a couple of font dictionaries, which
# poppler tolerates but stricter viewers (GitHub's in-browser viewer, Acrobat,
# strict PDF.js) can refuse to render. qpdf rewrites the file, normalises the
# duplicate, and produces a Fast-Web-View (linearized) PDF. --warning-exit-0
# keeps that warning from failing the build.
#
# Usage:  make        (both)        make en        make ja        make clean

EN = l4-icail
JA = l4-icail-ja
QPDF = qpdf --linearize --warning-exit-0 --replace-input

all: en ja

en: $(EN).pdf
$(EN).pdf: $(EN).tex $(EN).bib
	pdflatex -interaction=nonstopmode $(EN).tex
	bibtex $(EN)
	pdflatex -interaction=nonstopmode $(EN).tex
	pdflatex -interaction=nonstopmode $(EN).tex
	$(QPDF) $(EN).pdf

ja: $(JA).pdf
$(JA).pdf: $(JA).tex $(EN).bib
	lualatex --interaction=nonstopmode $(JA).tex
	bibtex $(JA)
	lualatex --interaction=nonstopmode $(JA).tex
	lualatex --interaction=nonstopmode $(JA).tex
	$(QPDF) $(JA).pdf

clean:
	rm -f $(EN).aux $(EN).bbl $(EN).blg $(EN).log $(EN).out \
	      $(JA).aux $(JA).bbl $(JA).blg $(JA).log $(JA).out

.PHONY: all en ja clean
