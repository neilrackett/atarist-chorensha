# Cho Ren Sha 68k: the Atari ST port by default, and the other targets on
# request. make runs on the host: build_st.sh calls the ST tools through
# stcmd (atarist-toolkit-docker, Docker running), one tool per call.
#
#   make, make release
#                    binaries/st/SZ2.TOS, to play, and a copy of it in
#                    dist/CHORENSH/ with SZ2.CFG and the game's data: a clean
#                    folder to copy to an ST
#   make debug       binaries/st/SZ2_ST.TOS (with measurements) and
#                    SZ2_DBG.TOS (with symbols), and the check that sz2.s
#                    leaves the X68000, Falcon and Amiga objects unchanged
#   make headless    binaries/st/SZ2_HL.TOS: the game logic, no rendering
#   make devops      binaries/st/SZ2_DEV.TOS: its text also on md-devops'
#                    debug stream (tests/st/hw/run_on_st.sh)
#   make check-data  that binaries/st's data is the other ports' (see below)
#   make test        check-data, then in Hatari: the attract demo's
#                    checkpoints and its song on an ST, an STE and a Mega
#                    STE, ESC out of the menus, the checkpoints at full
#                    height, and the pixel oracle
#   make others      the X68000, Falcon and Amiga builds (build_mac.sh on
#                    macOS, build.sh elsewhere)
#   make clean       removes what the builds and tests make (tmp/tos, the TOS
#                    images the tests run, is kept)
#
# binaries/st holds the game's data beside the programs, so they run from
# there (as binaries/amiga and binaries/atari do): copies of the Amiga
# port's BGM_DAT, ETC_DAT (its attract demo replay, which the ST's
# checkpoint reference was recorded with) and XSP_DAT, and of the Falcon's
# PCM_DAT (its .sam samples), with the ST's own SZ2_YM.BIN added, and the
# ST's own MUSIC_DAT (tools/music/make_st_music.py).

ST = binaries/st
DIST = dist/CHORENSH
REFERENCE = tests/amiga/reference/attract-6000.txt

ST_SOURCES = build_st.sh sources/sz2.s \
	$(wildcard sources/st/*.s sources/st/*.i sources/st/*.c) \
	$(wildcard lib/stdl/src/*.c lib/stdl/src/*.h lib/stdl/include/stdl/*.h) \
	$(wildcard lib/xpad/src/*)

# build_st.sh rebuilds the shared objects (binaries/st_*.o) every time: one
# build at a time.
.NOTPARALLEL:

.DEFAULT_GOAL := release

debug: $(ST)/SZ2_ST.TOS
headless: $(ST)/SZ2_HL.TOS
devops: $(ST)/SZ2_DEV.TOS

$(ST)/SZ2_ST.TOS: $(ST_SOURCES)
	./build_st.sh

$(ST)/SZ2.TOS: $(ST_SOURCES)
	RELEASE=1 CHECK=0 ./build_st.sh

$(ST)/SZ2_HL.TOS: $(ST_SOURCES)
	HEADLESS=1 CHECK=0 ./build_st.sh

$(ST)/SZ2_DEV.TOS: $(ST_SOURCES)
	DEVOPS=1 CHECK=0 ./build_st.sh

release: $(ST)/SZ2.TOS
	mkdir -p $(DIST)
	cp $(ST)/SZ2.TOS $(DIST)/
	@# The settings' template, but never over settings in use.
	@test -f $(DIST)/SZ2.CFG || cp $(ST)/SZ2.CFG $(DIST)/SZ2.CFG
	for data in BGM_DAT ETC_DAT MUSIC_DAT PCM_DAT XSP_DAT; do \
		rm -rf $(DIST)/$$data; cp -R $(ST)/$$data $(DIST)/; \
	done
	find $(DIST) -name .DS_Store -delete

check-data:
	@for data in BGM_DAT ETC_DAT XSP_DAT; do \
		diff -rq -x .DS_Store binaries/amiga/$$data $(ST)/$$data || exit 1; \
	done
	@diff -rq -x .DS_Store -x SZ2_YM.BIN binaries/atari/PCM_DAT $(ST)/PCM_DAT
	@echo "binaries/st: the Amiga port's BGM_DAT, ETC_DAT and XSP_DAT, the Falcon's PCM_DAT."

test: check-data $(ST)/SZ2_ST.TOS
	@failed=0; \
	for machine in st ste megaste; do \
		MACHINE=$$machine FRAMES=6000 tests/st/run_hatari.sh test_$$machine \
			> /dev/null 2>&1; \
		python3 tests/amiga/checkpoints.py compare $(REFERENCE) \
			tmp/out/test_$${machine}_CHECKPTS.BIN > tmp/out/test_$$machine.txt 2>&1 \
			|| failed=1; \
		echo "$$machine, crop: $$(tail -1 tmp/out/test_$$machine.txt)"; \
		songs=$$(grep -a 'Songs played' tmp/out/test_$$machine.log); \
		echo "$$machine, music: $${songs:-no song played}"; \
		case "$$songs" in "Songs played: 0"*|*"not loaded: "[1-9]*|"") failed=1;; esac; \
	done; \
	exit $$failed
	@failed=0; \
	for menu in config kakusi; do \
		MACHINE=ste FRAMES=2000 INPUT=tests/st/input/esc_$$menu.txt \
			tests/st/run_hatari.sh esc_$$menu > /dev/null 2>&1; \
		result="$$(grep -a 'Exit:' tmp/out/esc_$$menu.log | tr -d '\r') $$(grep -a -o 'Frames: [0-9]*' tmp/out/esc_$$menu.log)"; \
		echo "ESC out of $$menu, then quit: $$result"; \
		[ "$$result" = "Exit: game. Frames: 1100" ] || failed=1; \
	done; \
	exit $$failed
	tests/st/overscan_test.sh
	tests/st/oracle.sh

others:
ifeq ($(shell uname),Darwin)
	./build_mac.sh
else
	./build.sh
endif

clean:
	rm -f $(ST)/*.TOS $(ST)/*.o
	rm -f binaries/*.o binaries/sz2.x binaries/sz2.hex binaries/sz2.dif
	rm -f binaries/dsprite.cld binaries/dsprite.lst
	rm -f binaries/atari/*.o binaries/atari/*.lod binaries/atari/*.tos
	rm -f binaries/amiga/sz2_dbg binaries/amiga/sz2_profile
	rm -f binaries/amiga/vram_bench binaries/amiga/hardware_test.zip
	rm -rf binaries/amiga/hardware_test binaries/amiga/release
	rm -rf dist
	[ ! -d tmp ] || find tmp -mindepth 1 -maxdepth 1 ! -name tos -exec rm -rf {} +

.PHONY: debug release headless devops check-data test others clean
