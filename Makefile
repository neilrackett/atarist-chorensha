# Cho Ren Sha 68k: the Atari ST port by default, and the other targets on
# request. make runs on the host: build_st.sh calls the ST tools through
# stcmd (atarist-toolkit-docker, Docker running), one tool per call.
#
#   make             binaries/st/SZ2_ST.TOS (with measurements) and
#                    SZ2_DBG.TOS (with symbols), and the check that sz2.s
#                    leaves the X68000, Falcon and Amiga objects unchanged
#   make release     binaries/st/SZ2_REL.TOS: to play
#   make headless    binaries/st/SZ2_HL.TOS: the game logic, no rendering
#   make stream      binaries/st/SZ2_STS.TOS: its text also on md-devops'
#                    debug stream (tests/st/hw/run_on_st.sh)
#   make dist        dist/CHORENSH/: the release (SZ2.TOS), SZ2.CFG and the
#                    game's data, a folder to copy to an ST
#   make test        in Hatari: the attract demo's checkpoints on an ST, an
#                    STE and a Mega STE, in crop and at full height, and the
#                    pixel oracle
#   make others      the X68000, Falcon and Amiga builds (build_mac.sh on
#                    macOS, build.sh elsewhere)
#   make clean       removes what the builds and tests make (tmp/tos, the TOS
#                    images the tests run, is kept)

ST = binaries/st
DIST = dist/CHORENSH
REFERENCE = tests/amiga/reference/attract-6000.txt

ST_SOURCES = build_st.sh sources/sz2.s \
	$(wildcard sources/st/*.s sources/st/*.i sources/st/*.c) \
	$(wildcard lib/stdl/src/*.c lib/stdl/src/*.h lib/stdl/include/stdl/*.h) \
	$(wildcard lib/xpad/src/*)

# build_st.sh rebuilds the shared objects in binaries/st every time: one
# build at a time.
.NOTPARALLEL:

st: $(ST)/SZ2_ST.TOS
release: $(ST)/SZ2_REL.TOS
headless: $(ST)/SZ2_HL.TOS
stream: $(ST)/SZ2_STS.TOS

$(ST)/SZ2_ST.TOS: $(ST_SOURCES)
	./build_st.sh

$(ST)/SZ2_REL.TOS: $(ST_SOURCES)
	RELEASE=1 CHECK=0 ./build_st.sh

$(ST)/SZ2_HL.TOS: $(ST_SOURCES)
	HEADLESS=1 CHECK=0 ./build_st.sh

$(ST)/SZ2_STS.TOS: $(ST_SOURCES)
	STREAM=1 CHECK=0 ./build_st.sh

# The data as the program finds it beside itself: BGM_DAT, ETC_DAT and
# XSP_DAT from the Amiga port's set, PCM_DAT from the Falcon's with the
# ST's YM effects added (each machine loads only what it plays).
dist: $(ST)/SZ2_REL.TOS
	mkdir -p $(DIST)
	cp $(ST)/SZ2_REL.TOS $(DIST)/SZ2.TOS
	@# The settings' template, but never over settings in use.
	@test -f $(DIST)/SZ2.CFG || cp $(ST)/SZ2.CFG $(DIST)/SZ2.CFG
	for data in BGM_DAT ETC_DAT XSP_DAT; do \
		rm -rf $(DIST)/$$data; cp -R binaries/amiga/$$data $(DIST)/; \
	done
	rm -rf $(DIST)/PCM_DAT
	cp -R binaries/atari/PCM_DAT $(DIST)/
	cp $(ST)/PCM_DAT/SZ2_YM.BIN $(DIST)/PCM_DAT/
	find $(DIST) -name .DS_Store -delete

test: $(ST)/SZ2_ST.TOS
	@failed=0; \
	for machine in st ste megaste; do \
		MACHINE=$$machine FRAMES=6000 tests/st/run_hatari.sh test_$$machine \
			> /dev/null 2>&1; \
		python3 tests/amiga/checkpoints.py compare $(REFERENCE) \
			tmp/out/test_$${machine}_CHECKPTS.BIN > tmp/out/test_$$machine.txt 2>&1 \
			|| failed=1; \
		echo "$$machine, crop: $$(tail -1 tmp/out/test_$$machine.txt)"; \
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
	rm -f $(ST)/*.o $(ST)/*.TOS
	rm -f binaries/*.o binaries/sz2.x binaries/sz2.hex binaries/sz2.dif
	rm -f binaries/dsprite.cld binaries/dsprite.lst
	rm -f binaries/atari/*.o binaries/atari/*.lod binaries/atari/*.tos
	rm -f binaries/amiga/sz2_dbg binaries/amiga/sz2_profile
	rm -f binaries/amiga/vram_bench binaries/amiga/hardware_test.zip
	rm -rf binaries/amiga/hardware_test binaries/amiga/release
	rm -rf dist
	[ ! -d tmp ] || find tmp -mindepth 1 -maxdepth 1 ! -name tos -exec rm -rf {} +

.PHONY: st release headless stream dist test others clean
