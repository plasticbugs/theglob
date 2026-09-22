// rtl/lowpass.sv against tools/lowpass_model.py, sample for sample.
//   obj_lp/Vlowpass <in.raw> <out.raw> <mode>      little-endian int16
#include "Vlowpass.h"
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
    auto *d = new Vlowpass;
    auto tick = [&] { d->clk = 0; d->eval(); d->clk = 1; d->eval(); };
    d->ce = 0; d->reset = 1; d->mode = atoi(argv[3]);
    for (int i = 0; i < 4; i++) tick();
    d->reset = 0;
    std::vector<int16_t> out;
    for (auto s : in) {
        d->in = s; d->ce = 1; tick(); d->ce = 0;
        for (int i = 0; i < 8; i++) { if (d->out_tick) out.push_back((int16_t)d->out); tick(); }
    }
    f = fopen(argv[2], "wb"); fwrite(out.data(), 2, out.size(), f); fclose(f);
    delete d; return 0;
}
