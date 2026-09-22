// rtl/theglob_reverb.sv against tools/reverb_model.py, sample for sample.
//   obj_reverb/Vtheglob_reverb <in.raw> <out.raw> <mode>
// in/out: little-endian int16.  One ce every 16 clocks (the module needs 9).
#include "Vtheglob_reverb.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <vector>
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 4) return 2;
    FILE *f = fopen(argv[1], "rb"); std::vector<int16_t> in; int16_t v;
    while (fread(&v, 2, 1, f) == 1) in.push_back(v);
    fclose(f);
    auto *d = new Vtheglob_reverb;
    auto tick = [&] { d->clk = 0; d->eval(); d->clk = 1; d->eval(); };
    d->mode = atoi(argv[3]); d->ce = 0; d->reset = 1;
    for (int i = 0; i < 8; i++) tick();
    d->reset = 0;
    std::vector<int16_t> out;
    for (auto s : in) {
        d->in = s; d->ce = 1; tick(); d->ce = 0;
        for (int i = 0; i < 15; i++) { tick(); if (d->out_tick) out.push_back((int16_t)d->out); }
    }
    f = fopen(argv[2], "wb"); fwrite(out.data(), 2, out.size(), f); fclose(f);
    delete d; return 0;
}
