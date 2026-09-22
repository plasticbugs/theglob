// Pocket memory gate: push an image through theglob_mem's download port at the
// APF loader's rate, then read every byte back through the core's ports and
// compare, and check the whole-image checksum the bring-up panel shows.
//
//   obj_mem/Vtb_mem_top [rom] [-gap N] [-hold N] [-quick]
//
// With no rom a pseudo-random image is used, which is a harder test than a
// real one and needs nothing the repo may not hold.
//
// -gap   clocks between download bytes.  The loader delivers one per 8.
// -hold  clocks the write strobe is held high.  The Pocket holds it for 4 with
//        address and data stable; anything that counts or sums on the
//        strobe's level rather than its edge fails here (METHODOLOGY 5.8).
// Unless -hold is given, the checksum is also re-run at holds 1, 4 and 7.
//
// The layout constants must match target/pocket/theglob_mem.sv.
#include "Vtb_mem_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

static Vtb_mem_top *dut;
static void tick() { dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval(); }

static const uint32_t PROM_B = 0x7800, IMG = 0x7820;

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int gap = 8, hold = 4; bool hold_given = false; std::string path;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "-gap" && i + 1 < argc) gap = atoi(argv[++i]);
        else if (a == "-hold" && i + 1 < argc) { hold = atoi(argv[++i]); hold_given = true; }
        else if (a == "-quick") ;               // the image is small; always whole
        else if (a[0] != '+' && a[0] != '-') path = a;
    }
    std::vector<uint8_t> rom(IMG);
    if (!path.empty()) {
        FILE *f = fopen(path.c_str(), "rb");
        if (!f || fread(rom.data(), 1, IMG, f) != IMG) { fprintf(stderr, "cannot read %u bytes from %s\n", IMG, path.c_str()); return 2; }
        fclose(f);
    } else {
        uint32_t x = 0x2545F491;
        for (auto &b : rom) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; b = uint8_t(x >> 11); }
    }
    uint16_t want_sum = 0;
    for (auto b : rom) want_sum += b;

    std::vector<int> holds = hold_given ? std::vector<int>{hold} : std::vector<int>{4, 1, 7};
    long bad = 0;
    for (int h : holds) {
        if (h >= gap) h = gap - 1;
        if (h < 1) h = 1;
        dut = new Vtb_mem_top;
        dut->dl_we = 0; dut->clr = 1;
        for (int i = 0; i < 16; i++) tick();
        dut->clr = 0;
        printf("downloading %u bytes, one per %d clocks, strobe held %d...\n", IMG, gap, h);
        for (uint32_t a = 0; a < IMG; a++) {
            dut->dl_addr = a; dut->dl_data = rom[a]; dut->dl_we = 1;
            for (int i = 0; i < h; i++) tick();
            dut->dl_we = 0;
            for (int i = h; i < gap; i++) tick();
        }
        for (int i = 0; i < 16; i++) tick();

        long wrong = 0;
        auto fail = [&](const char *port, uint32_t idx, unsigned got, unsigned want) {
            if (wrong < 12) printf("  %-5s [%04X] got %02X want %02X\n", port, idx, got, want);
            wrong++;
        };
        for (uint32_t a = 0; a < PROM_B; a++) {
            dut->rom_addr = a; tick();
            if (dut->rom_q != rom[a]) fail("rom", a, dut->rom_q, rom[a]);
        }
        for (uint32_t a = 0; a < 32; a++) {
            dut->prom_addr = a; tick();
            if (dut->prom_q != rom[PROM_B + a]) fail("prom", a, dut->prom_q, rom[PROM_B + a]);
        }
        printf("  %u bytes read back, %ld wrong; checksum %04X want %04X, count %u want %u\n",
               IMG, wrong, dut->dl_sum, want_sum, dut->dl_count, IMG);
        if (dut->dl_sum != want_sum || dut->dl_count != IMG) { printf("  checksum or count wrong\n"); wrong++; }
        bad += wrong;
        delete dut;
    }
    if (bad) { printf("FAIL  what came back is not what was sent\n"); return 1; }
    printf("PASS  every byte reads back, and the checksum counts each byte once\n");
    return 0;
}
