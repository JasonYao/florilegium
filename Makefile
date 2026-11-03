LUALATEX = $(RUN) lualatex -interaction=nonstopmode -halt-on-error
SEEDS   ?= 1 2 3 4 5 6
# RUN=tools/in-docker builds inside the florilegium-tex image (see tools/Dockerfile)
RUN     ?=
LUA      = florilegium-ink.lua florilegium-flora.lua florilegium.lua florilegium-initial.lua florilegium-figures.lua florilegium-theme-geometric.lua florilegium-theme-math.lua
GS      ?= gs
SEED    ?= 7

all: florilegium.pdf florilegium-grow.pdf showcase.pdf spread.pdf

# authored composition (florilegium-authored.lua), one pass, about a second a page
florilegium.pdf: florilegium.tex florilegium.sty florilegium-authored.lua florilegium-grow.lua $(LUA) text-methods.tex text-sharing.tex
	$(LUALATEX) florilegium.tex

# grown composition (florilegium-grow.lua), one pass: the end of the text is measured with \pagetotal
florilegium-grow.pdf: florilegium-grow.tex florilegium.sty florilegium-grow.lua $(LUA) text-methods.tex text-growth.tex text-sharing.tex
	$(LUALATEX) florilegium-grow.tex

# initials, flowers at the headings, visitors and the seasons; two passes, because
# the option aging reads the page count of the first one
showcase.pdf: showcase.tex florilegium.sty florilegium-grow.lua $(LUA)
	$(LUALATEX) showcase.tex
	$(LUALATEX) showcase.tex

# a two-sided document: the garden follows the outer margin, mirrored on the
# right-hand pages; its last page is grown from the math theme
spread.pdf: spread.tex florilegium.sty florilegium-grow.lua $(LUA)
	$(LUALATEX) spread.tex

# one of every primitive, drawn with \florilegiumdraw; the same for the math theme
specimen.pdf: specimen.tex florilegium.sty $(LUA)
	$(LUALATEX) specimen.tex
specimen-geometric.pdf: specimen-geometric.tex florilegium.sty $(LUA)
	$(LUALATEX) specimen-geometric.tex

# \florilegiumornament: single primitives in the text (issue #4)
ornaments.pdf: ornaments.tex florilegium.sty $(LUA)
	$(LUALATEX) ornaments.tex

# rectangular region subtraction and masked growth
regioncheck: tests/regions.tex florilegium.sty florilegium-grow.lua $(LUA)
	mkdir -p build
	$(LUALATEX) -output-directory=build tests/regions.tex

# the grown document with the geometric and the math theme, for gallery/geometric.png
# and gallery/math.png (its second page)
build/geometric.pdf build/math.pdf: build/%.pdf: florilegium-grow.tex florilegium.sty florilegium-grow.lua $(LUA) text-methods.tex text-growth.tex text-sharing.tex
	mkdir -p build
	$(LUALATEX) -jobname=build/$* "\PassOptionsToPackage{theme=$*}{florilegium}\input{florilegium-grow.tex}"

# one page for one seed:  make seed-7  ->  build/seed-7.pdf
seed-%: gallery.tex florilegium.sty florilegium-grow.lua $(LUA)
	mkdir -p build
	$(LUALATEX) -jobname=build/seed-$* "\def\florilegiumseed{$*}\input{gallery.tex}"

# contact sheets: seeds (+ gif), one seed in six inks, one seed through the seasons
# (needs python3 + Pillow + pdftoppm)
gallery: gallery.tex florilegium.sty florilegium-grow.lua $(LUA) tools/gallery.py
	python3 tools/gallery.py --seeds $(SEEDS) --run "$(RUN)"
	python3 tools/gallery.py --seed 6 --inks 2456C4 5B2A1F 2F6B4F 8E1B3A 4B3B8F 1D6E7A --run "$(RUN)"
	python3 tools/gallery.py --seed 6 --ages 0 0.33 0.67 1 --run "$(RUN)"
	python3 tools/gallery.py --seed 6 --themes flora geometric math --run "$(RUN)"
	python3 tools/gallery.py --seed 6 --options density=1 density=0.5 density=0.2 density=0.05 intensity=0.5 --run "$(RUN)"

# the growth of one seed:  make grow-7  ->  build/grow-7.gif and .mp4 (MP4 needs ffmpeg);
# EXPLAIN=1 also marks the free disc each branch grows to  ->  build/grow-7-explain.*
grow-%: animation.tex florilegium.sty florilegium-grow.lua $(LUA) tools/animate.py
	python3 tools/animate.py --seed $* --run "$(RUN)" $(if $(EXPLAIN),--explain)

# the README's animations (seed 6: all four visitors)
animation:
	$(MAKE) grow-6 RUN="$(RUN)"
	$(MAKE) grow-6 RUN="$(RUN)" EXPLAIN=1
	cp build/grow-6.gif gallery/growth.gif
	cp build/grow-6-explain.gif gallery/growth-explain.gif

# the PostScript port, run by Ghostscript:  make postscript [SEED=7]
#   -> build/postscript-7.pdf and gallery/preview-postscript.png (pdftoppm, Pillow)
postscript: postscript/florilegium.ps
	mkdir -p build gallery
	$(GS) -q -dSAFER -dBATCH -dNOPAUSE -dALLOWPSTRANSPARENCY -dSeed=$(SEED) \
	  -sDEVICE=pdfwrite -o build/postscript-$(SEED).pdf postscript/florilegium.ps
	pdftoppm -png -r 45 build/postscript-$(SEED).pdf build/postscript
	python3 -c "from PIL import Image; import glob; \
	  ims = [Image.open(f).convert('RGB') for f in sorted(glob.glob('build/postscript-[0-9].png'))]; w, h = ims[0].size; \
	  s = Image.new('RGB', (len(ims) * (w + 8) + 8, h + 16), (235, 235, 240)); \
	  [s.paste(im, (8 + i * (w + 8), 8)) for i, im in enumerate(ims)]; s.save('gallery/preview-postscript.png')"

# the PostScript port's tests (postscript/README.md), ~10 s:  make pscheck
pscheck:
	GS=$(GS) postscript/check.sh

preview: florilegium.pdf florilegium-grow.pdf showcase.pdf spread.pdf specimen-geometric.pdf ornaments.pdf build/geometric.pdf build/math.pdf
	mkdir -p gallery build
	pdftoppm -png -r 110 -singlefile ornaments.pdf gallery/ornaments
	pdftoppm -png -r 60 -f 2 -l 2 -singlefile build/geometric.pdf gallery/geometric
	pdftoppm -png -r 60 -f 2 -l 2 -singlefile build/math.pdf gallery/math
	pdftoppm -png -r 60 -f 1 -l 1 -singlefile florilegium.pdf gallery/preview-authored
	pdftoppm -png -r 60 -f 1 -l 1 -singlefile florilegium-grow.pdf gallery/preview-grown
	pdftoppm -png -r 50 -singlefile specimen-geometric.pdf gallery/specimen-geometric
	pdftoppm -png -r 50 -f 2 -l 3 spread.pdf build/spread
	python3 -c "from PIL import Image; \
	  a, b = Image.open('build/spread-2.png').convert('RGB'), Image.open('build/spread-3.png').convert('RGB'); \
	  s = Image.new('RGB', (a.width + b.width + 16, a.height + 16), (235, 235, 240)); \
	  s.paste(a, (8, 8)); s.paste(b, (8 + a.width, 8)); s.save('gallery/spread.png')"
	pdftoppm -png -r 45 showcase.pdf build/showcase
	python3 -c "from PIL import Image; import glob; \
	  ims = [Image.open(f).convert('RGB') for f in sorted(glob.glob('build/showcase-*.png'))]; w, h = ims[0].size; \
	  s = Image.new('RGB', (len(ims) * (w + 8) + 8, h + 16), (235, 235, 240)); \
	  [s.paste(im, (8 + i * (w + 8), 8)) for i, im in enumerate(ims)]; s.save('gallery/preview-showcase.png')"

# the same page as SVG, without TeX (florilegium-svg.lua; any Lua 5.3/5.4):  make svg [SEED=7]
#   -> build/svg-7.svg, the drawing on page 1 of florilegium-grow.tex with that seed
svg: florilegium-svg.lua florilegium-grow.lua florilegium-authored.lua $(LUA)
	mkdir -p build
	$(RUN) texlua florilegium-svg.lua --seed $(SEED) -o build/svg-$(SEED).svg

# the playground in web/, served from the repository: http://localhost:8000/web/
playground:
	python3 -m http.server 8000

clean:
	rm -rf build *.aux *.log *.out *.synctex.gz

.PHONY: all gallery animation preview postscript pscheck regioncheck svg playground clean
