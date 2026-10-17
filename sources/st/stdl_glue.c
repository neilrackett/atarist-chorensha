/*
 * STDL's border overscan (lib/stdl/src/overscan.c, compiled unchanged) in
 * the Atari ST port: the few parts of STDL it reaches for, supplied here
 * for a program that owns the machine itself (machine.s, display.s).
 *
 * The port keeps its own screens and flips them itself: overscan.c is
 * given the first screen page as its "ST RAM" page (so its pointers name
 * a page the port shows), is never asked to flip (single-buffered as far
 * as it knows), and display.s keeps the variables its interrupts compare
 * the video counter against up to date with the port's flips. No palette
 * staging: the port sets its colours in the VBL, before the picture,
 * which starts at line 34 with the top border open.
 *
 * Called from the port (68000 assembly, C calling convention): see
 * port_overscan_open and port_overscan_close below.
 */

#include <stdint.h>
#include <stddef.h>
#include "stdl_internal.h"
#include <stdl/stdl_overscan.h>

stdl_state_t stdl;
STDL_Surface stdl_screen;
void (*stdl_shutdown_overscan)(void);
int (*stdl_ovsc_flip)(void);
uint16_t (*stdl_blit_policy)(uint16_t nlines, uint32_t cpl);
uint8_t stdl_vbl_hz = 50;
int stdl_sync_want = -1;
uint8_t stdl_timerb_owner;
int stdl_megaste_mode;

static const char *last_error = "";
static uint8_t *overscan_page;

void STDL_SetError(const char *msg)
{
    last_error = msg;
}

/* The port's VBL handler counts frames in TOS's frame counter while the
 * borders are open (it replaces TOS's handler, which would). */
void STDL_WaitVBL(void)
{
    uint32_t frame = STDL_FRCLOCK;

    while (STDL_FRCLOCK == frame) {
    }
}

void *memset(void *s, int c, size_t n)
{
    uint8_t *p = s;

    while (n--) {
        *p++ = (uint8_t)c;
    }
    return s;
}

/* overscan.c's tall page: the port's first screen page, cleared by it. */
void *stdl_stram_alloc(uint32_t bytes)
{
    (void)bytes;
    return overscan_page;
}

void stdl_stram_free(void *p)
{
    (void)p;
}

void stdl_palette_apply_hw(void)
{
}

int stdl_pal_stage_on(int who)
{
    (void)who;
    return 0;
}

void stdl_pal_stage_off(int who)
{
    (void)who;
}

/*
 * page: the port's first screen page (256-aligned, 274 lines);
 * tos_screen: the screen TOS drew on (restored as its logical and
 * physical screen when the borders close); mch: the _MCH cookie (0 if
 * none). Opens the top border, then the bottom one: returns the visible
 * lines (273), or 0 if they did not open (STDL's message in *error).
 * Supervisor mode, the port's interrupts running.
 */
int port_overscan_open(uint8_t *page, uint8_t *tos_screen, uint32_t mch,
                       const char **error)
{
    int lines;

    overscan_page = page;
    stdl.initialised = 1;
    stdl.video_set = 1;
    stdl.mach.mch_cookie = mch;
    stdl.mach.has_blitter = 0;      /* the port's copy uses the CPU here */
    stdl.page[0] = tos_screen;
    stdl.doublebuf = 0;
    stdl.old_sync = -1;

    lines = STDL_OpenTopBorder() ? STDL_OpenBottomBorder() : 0;
    if (lines != STDL_OVERSCAN_BOTH_H) {
        STDL_CloseBottomBorder();
        STDL_CloseTopBorder();
        *error = last_error;
        return 0;
    }
    return lines;
}

/* Closes both borders (the port's interrupts running): STDL puts back the
 * vectors it borrowed, the timers, the sync rate and TOS's screen. */
void port_overscan_close(void)
{
    STDL_CloseBottomBorder();
    STDL_CloseTopBorder();
}

uint32_t port_overscan_misses(void)
{
    return STDL_OverscanMisses();
}
