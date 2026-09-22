// Frozen-state gate for the video: load a state dumped from MAME into VRAM,
// run rtl/theglob_video.sv for two frames with a dot enable every 16 clocks
// (88 MHz / 5.5 MHz), capture the pens of the second frame, and diff them
// against tools/render_model.py's pens for the same state.
//
//   obj_video/Vtb_video_top <state.bin> <pens.bin> [out.pens]
//
// Pens, not colours, so two pens that resolve to one colour cannot hide a
// difference.  Also checks the raster: 272 x 236 visible, 352 x 258 total.
#include "Vtb_video_top.h"
#include "verilated.h"
#include <cstdio>
#include <vector>

static Vtb_video_top *dut;
static long clk_n = 0;
static void tick() {
    dut->cen_pix = (clk_n % 16) == 0;
    dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval();
    clk_n++;
}

static std::vector<uint8_t> slurp(const char *p) {
    std::vector<uint8_t> v; FILE *f = fopen(p, "rb");
    if (!f) { fprintf(stderr, "cannot open %s\n", p); exit(2); }
    int c; while ((c = fgetc(f)) != EOF) v.push_back(uint8_t(c));
    fclose(f); return v;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) { fprintf(stderr, "usage: %s state.bin pens.bin [out.pens]\n", argv[0]); return 2; }
    const int W = 272, H = 236;
    auto st = slurp(argv[1]);
    auto want = slurp(argv[2]);
    if (st.size() < 16 + 32768 || std::string((char *)st.data(), 4) != "TGST" || want.size() != size_t(W * H)) {
        fprintf(stderr, "bad inputs\n"); return 2;
    }
    uint32_t frame = st[8] | st[9] << 8 | st[10] << 16 | st[11] << 24;
    dut = new Vtb_video_top;
    dut->palbank = st[12] & 1;
    dut->rst = 1;
    for (int a = 0; a < 32768; a++) {
        dut->load_we = 1; dut->load_addr = a; dut->load_data = st[16 + a]; tick();
    }
    dut->load_we = 0;
    for (int i = 0; i < 32; i++) tick();
    dut->rst = 0;

    // two frames: the first settles, the second is captured
    std::vector<uint8_t> got;
    int frames = 0, lines = 0, de_lines = 0, de_run = 0, max_run = 0, dots = 0, dots_line = 0;
    bool prev_de = false, prev_hb = true;
    long vbs = 0;
    while (frames < 2) {
        tick();
        if (!dut->cen_pix) continue;
        // outputs registered on this enable are visible after it
        dots++;
        if (dut->vblank_start) { vbs++; frames++; if (frames == 1) { got.clear(); lines = 0; de_lines = 0; } }
        if (frames == 1) {
            if (dut->de) { got.push_back(dut->pen); de_run++; }
            if (!dut->de && prev_de) { if (de_run > max_run) max_run = de_run; de_run = 0; de_lines++; }
            if (dut->hblank && !prev_hb) { lines++; dots_line = dots; dots = 0; }
        }
        prev_de = dut->de; prev_hb = dut->hblank;
    }
    long bad = 0; int fx = -1, fy = -1;
    if (got.size() == want.size())
        for (size_t i = 0; i < got.size(); i++)
            if (got[i] != want[i]) { if (!bad) { fx = i % W; fy = i / W; } bad++; }
    printf("frame %6u  visible %d x %d (want %d x %d), %d lines/frame, %d dots/line  ",
           frame, max_run, de_lines, W, H, lines, dots_line);
    if (got.size() != want.size()) { printf("FAIL  %zu pens captured, want %zu\n", got.size(), want.size()); return 1; }
    if (argc > 3) { FILE *f = fopen(argv[3], "wb"); fwrite(got.data(), 1, got.size(), f); fclose(f); }
    if (bad || max_run != W || de_lines != H || lines != 258 || dots_line != 352) {
        printf("FAIL  %ld pens differ (first at %d,%d)\n", bad, fx, fy); return 1;
    }
    printf("PASS  0 pens differ\n");
    delete dut;
    return 0;
}
