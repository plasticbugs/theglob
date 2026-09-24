Put theglob.rom (The Glob) and/or suprglob.rom (Super Glob) here.

Build it from your own MAME `theglob` romset with the builder in the release
zip, which needs nothing but Python 3:

    python3 mra_build.py theglob.mra theglob.zip

theglob is a clone of suprglob, and its colour PROM (82s123.u66) belongs to
the parent.  A merged or non-merged theglob.zip carries it; a split one does
not, and then the builder says "82s123.u66 is missing" -- name the parent too:

    python3 mra_build.py theglob.mra theglob.zip suprglob.zip

Super Glob is its own image, from its own set:

    python3 mra_build.py suprglob.mra suprglob.zip

A merged suprglob.zip carries The Glob too; it builds both.

It reads the zip (or a directory of loose files) directly, checks every ROM's
CRC32, and verifies the finished image against a known md5, so
a wrong or damaged romset is reported rather than quietly built into
something that half works.

Already using pupdate or the standard `mra` tool? Point it at theglob.mra;
it is an ordinary MRA file.
