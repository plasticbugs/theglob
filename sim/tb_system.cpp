// Driver for sim/tb_system_top.sv: the whole machine through the Pocket's
// memory glue.  Loads the ROM image the way the Pocket's loader does, runs
// frames, drives the controls by the same script as tools/dump_state.lua, and
// writes what the core drew, what it played and what it wrote.
//
//   obj_system/Vtb_system_top <rom> [-frames N] [-snap a,b,c] [-o DIR]
//       [-coin F] [-start F] [-play] [-service] [-dsw HEX]
//       [-trace FILE [-times]] [-wav FILE] [-fast] [-gap N] [-hold N] [-pause a-b]
//
// Frame N here is MAME's frame N: both count vblank starts from power-on, and
// the controls change at the start of vblank of the frame the script names,
// as the dumper's frame-done callback changes them.  So a PNG for frame N is
// comparable with a MAME state for frame N (tools/compare_system.py).
//
// -trace writes every CPU write, in order, as "M aaaa dd" (memory) or
// "O aa dd" (I/O), with "F n" as each vblank begins: the format
// tools/trace_writes.lua writes from MAME.
// -times appends each write's time in CPU cycles since reset (the Z80 at
// 2.75 MHz, one per 32 clocks), which TIMES=1 gives the MAME trace too.
// -fast writes the image at a byte a clock instead of the loader's rate
// (one byte per 8 clocks, strobe held 4: METHODOLOGY 5.8 and 5.16).
#include "Vtb_system_top.h"
#include "verilated.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <set>
#include <string>
#include <vector>

static const int W = 272, H = 236;
static const uint32_t IMG = 0x7820;         // must match theglob_mem.sv's layout
static const double CLK = 88e6;

static Vtb_system_top *dut;
static uint64_t clk_n = 0;
static void tick() { dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval(); clk_n++; }

static void write_png(const std::string &path, const std::vector<uint8_t> &rgb);
static void write_wav(const std::string &path, const std::vector<int16_t> &s, int rate);

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int frames = 10, gap = 8, hold = 4, coin = -1, start = -1, pause_a = -1, pause_b = -1;
    unsigned dsw = 0x00;
    bool play = false, service = false, fast = false, times = false;
    std::string rom, out = ".", trace_path, wav_path;
    std::set<int> snaps;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        auto next = [&] { return std::string(argv[++i]); };
        if (a == "-frames") frames = atoi(next().c_str());
        else if (a == "-gap") gap = atoi(next().c_str());
        else if (a == "-hold") hold = atoi(next().c_str());
        else if (a == "-o") out = next();
        else if (a == "-coin") coin = atoi(next().c_str());
        else if (a == "-start") start = atoi(next().c_str());
        else if (a == "-play") play = true;
        else if (a == "-service") service = true;
        else if (a == "-fast") fast = true;
        else if (a == "-times") times = true;
        else if (a == "-dsw") dsw = strtoul(next().c_str(), nullptr, 16);
        else if (a == "-trace") trace_path = next();
        else if (a == "-wav") wav_path = next();
        else if (a == "-pause") { std::string s = next(); sscanf(s.c_str(), "%d-%d", &pause_a, &pause_b); }
        else if (a == "-snap") {
            std::string s = next();
            for (size_t p = 0; p < s.size();) {
                size_t c = s.find(',', p); if (c == std::string::npos) c = s.size();
                snaps.insert(atoi(s.substr(p, c - p).c_str())); p = c + 1;
            }
        } else if (a[0] != '+' && a[0] != '-') rom = a;
    }
    if (fast) { gap = 1; hold = 1; }
    if (hold >= gap && gap > 1) hold = gap - 1;
    if (snaps.empty()) snaps.insert(frames);

    std::vector<uint8_t> image(IMG);
    if (rom.empty()) { fprintf(stderr, "a ROM image is needed: .build/theglob.rom\n"); return 2; }
    {
        FILE *f = fopen(rom.c_str(), "rb");
        if (!f || fread(image.data(), 1, IMG, f) != IMG) {
            fprintf(stderr, "cannot read %u bytes from %s\n", IMG, rom.c_str()); return 2;
        }
        fclose(f);
    }
    uint16_t want_sum = 0;
    for (auto b : image) want_sum += b;

    dut = new Vtb_system_top;
    dut->reset = 1; dut->pause = 0; dut->dl_we = 0;
    dut->dsw = dsw; dut->inputs = 0xff;
    dut->start1_n = dut->start2_n = 1; dut->service_n = service ? 0 : 1; dut->coin = 0;
    for (int i = 0; i < 16; i++) tick();

    for (uint32_t a = 0; a < IMG; a++) {
        dut->dl_addr = a; dut->dl_data = image[a]; dut->dl_we = 1;
        for (int i = 0; i < hold; i++) tick();
        dut->dl_we = 0;
        for (int i = hold; i < gap; i++) tick();
        if (gap == 1) tick();               // a strobe needs a low clock between bytes
    }
    for (int i = 0; i < 64; i++) tick();
    printf("image in at one byte per %d clocks, strobe %d: checksum %04X (want %04X), %u bytes\n",
           gap, hold, dut->dl_sum, want_sum, dut->dl_count);
    if (dut->dl_sum != want_sum || dut->dl_count != IMG) { printf("FAIL  the image did not arrive intact\n"); return 1; }
    dut->reset = 0;
    const uint64_t clk_run = clk_n;

    FILE *trace = trace_path.empty() ? nullptr : fopen(trace_path.c_str(), "w");
    // M1LOG=file: the first 4000 opcode fetches, with the T-states since the one before
    FILE *m1log = getenv("M1LOG") ? fopen(getenv("M1LOG"), "w") : nullptr;
    int m1n = 0;
    std::vector<int16_t> audio;
    double next_sample = 0, per_sample = CLK / 48000.0;

    std::vector<uint8_t> frame(W * H * 3, 0);
    int px = 0, frame_no = 0, kicks = 0;
    long writes = 0;
    // vblank comes out of reset high; count only a rise seen after it fell,
    // or the first clock is a spurious frame 1 and every number after is one
    // ahead of MAME's
    bool prev_vb = true;
    uint32_t lcg = 12345;
    int held = -1;
    uint8_t inputs = 0xff;
    bool fault_reported = false;
    while (frame_no < frames) {
        // a dot enable on this edge registers a new pixel, with its own de
        bool edge = dut->pix_ce;
        tick();
        if (dut->watchdog_kick) kicks++;
        if (dut->wr && trace) {
            char ts[32] = "";
            if (times) snprintf(ts, sizeof ts, " %llu", (unsigned long long)((clk_n - clk_run) / 32));
            if (dut->wr_io) fprintf(trace, "O %02x %02x%s\n", dut->wr_addr & 0xff, dut->wr_data, ts);
            else            fprintf(trace, "M %04x %02x%s\n", dut->wr_addr, dut->wr_data, ts);
        }
        if (dut->m1 && dut->pc == 0x0038 && trace) fprintf(trace, "I\n");
        if (m1log && dut->m1 && m1n < 4000) {   // T-states between opcode fetches
            static uint64_t last = 0;
            fprintf(m1log, "%04x %llu\n", dut->pc, (unsigned long long)((clk_n - last) / 32));
            last = clk_n; m1n++;
        }
        if (dut->wr) writes++;
        if (dut->f_hit && !fault_reported) {
            fault_reported = true;
            printf("FAULT CAPTURE at frame %d: kind %02x, pc0 %04x, pc1 %04x\n",
                   frame_no + 1, dut->f_kind, dut->f_pc0, dut->f_pc1);
        }
        if (!wav_path.empty() && clk_n >= next_sample) { audio.push_back(dut->snd); next_sample += per_sample; }
        if (edge && dut->de && px < W * H) {
            frame[3 * px + 0] = (dut->rgb >> 16) & 0xff;
            frame[3 * px + 1] = (dut->rgb >> 8) & 0xff;
            frame[3 * px + 2] = dut->rgb & 0xff;
            px++;
        }
        if (dut->vblank && !prev_vb) {
            frame_no++;                     // MAME's frame-done count
            if (trace) fprintf(trace, "F %d\n", frame_no);
            if (snaps.count(frame_no)) {
                char p[512]; snprintf(p, sizeof p, "%s/frame_%05d.png", out.c_str(), frame_no);
                write_png(p, frame);
            }
            px = 0;
            // the controls, exactly as tools/dump_state.lua drives them
            dut->coin = (coin >= 0 && frame_no >= coin && frame_no < coin + 4);
            dut->start1_n = !(start >= 0 && frame_no >= start && frame_no < start + 4);
            if (play && start >= 0 && frame_no > start + 30 && frame_no % 20 == 0) {
                lcg = (uint32_t)(((uint64_t)lcg * 1103515245u + 12345u) & 0x7fffffffu);
                held = (lcg >> 16) % 4;                 // up, down, left, right
                static const uint8_t dir_bit[4] = {4, 5, 1, 0};
                inputs = 0xff & ~(1u << dir_bit[held]);
                if (((lcg >> 8) & 3) == 0) inputs &= ~0x04;    // button 1
                if (((lcg >> 10) & 7) == 0) inputs &= ~0x08;   // button 2
            }
            dut->inputs = inputs;
            dut->pause = (frame_no >= pause_a && frame_no < pause_b);
        }
        prev_vb = dut->vblank;
    }
    if (trace) fclose(trace);
    if (!wav_path.empty()) write_wav(wav_path, audio, 48000);
    printf("%d frames, %ld CPU writes, %d watchdog kicks, halted %d, fault capture %s (%d events)\n",
           frames, writes, kicks, (int)dut->halted, dut->f_hit ? "HIT" : "quiet", dut->f_n);
    delete dut;
    return 0;
}

// --- a minimal PNG writer, so the bench needs nothing installed -------------
static void be32(std::vector<uint8_t> &v, uint32_t x) {
    v.push_back(x >> 24); v.push_back(x >> 16); v.push_back(x >> 8); v.push_back(x);
}
static uint32_t crc32_of(const uint8_t *d, size_t n) {
    static uint32_t tbl[256]; static bool init = false;
    if (!init) { for (uint32_t i = 0; i < 256; i++) { uint32_t c = i;
        for (int k = 0; k < 8; k++) c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1; tbl[i] = c; } init = true; }
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; i++) c = tbl[(c ^ d[i]) & 0xFF] ^ (c >> 8);
    return c ^ 0xFFFFFFFFu;
}
static void chunk(std::vector<uint8_t> &o, const char *tag, const std::vector<uint8_t> &data) {
    be32(o, (uint32_t)data.size());
    std::vector<uint8_t> td(tag, tag + 4);
    td.insert(td.end(), data.begin(), data.end());
    o.insert(o.end(), td.begin(), td.end());
    be32(o, crc32_of(td.data(), td.size()));
}
static void write_png(const std::string &path, const std::vector<uint8_t> &rgb) {
    std::vector<uint8_t> raw;
    for (int y = 0; y < H; y++) {
        raw.push_back(0);
        raw.insert(raw.end(), rgb.begin() + 3 * y * W, rgb.begin() + 3 * (y + 1) * W);
    }
    // stored (uncompressed) deflate blocks: no zlib dependency
    std::vector<uint8_t> z{0x78, 0x01};
    uint32_t a = 1, b = 0;
    for (uint8_t c : raw) { a = (a + c) % 65521; b = (b + a) % 65521; }
    for (size_t i = 0; i < raw.size(); i += 65535) {
        uint16_t n = (uint16_t)std::min<size_t>(65535, raw.size() - i);
        z.push_back(i + n >= raw.size() ? 1 : 0);
        z.push_back(n & 0xff); z.push_back(n >> 8);
        z.push_back(~n & 0xff); z.push_back((~n >> 8) & 0xff);
        z.insert(z.end(), raw.begin() + i, raw.begin() + i + n);
    }
    be32(z, (b << 16) | a);
    std::vector<uint8_t> o{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}, ihdr;
    be32(ihdr, W); be32(ihdr, H);
    ihdr.push_back(8); ihdr.push_back(2); ihdr.push_back(0); ihdr.push_back(0); ihdr.push_back(0);
    chunk(o, "IHDR", ihdr); chunk(o, "IDAT", z); chunk(o, "IEND", {});
    FILE *f = fopen(path.c_str(), "wb");
    if (f) { fwrite(o.data(), 1, o.size(), f); fclose(f); }
}

static void write_wav(const std::string &path, const std::vector<int16_t> &s, int rate) {
    FILE *f = fopen(path.c_str(), "wb");
    if (!f) return;
    auto u32 = [&](uint32_t v) { fwrite(&v, 4, 1, f); };
    auto u16 = [&](uint16_t v) { fwrite(&v, 2, 1, f); };
    uint32_t bytes = (uint32_t)s.size() * 2;
    fwrite("RIFF", 1, 4, f); u32(36 + bytes); fwrite("WAVEfmt ", 1, 8, f);
    u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16);
    fwrite("data", 1, 4, f); u32(bytes);
    fwrite(s.data(), 2, s.size(), f);
    fclose(f);
}
