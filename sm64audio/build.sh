#!/bin/bash
# build.sh: rebuild sm64audio.exe (sm64audio.c + libsm64's audio code)
cd /x/mashup-work/sm64audio
L=X:/mashup-work/dl_libsm64/src/libsm64-master/src
/x/mashup-work/llvm/llvm-mingw-20261006-ucrt-x86_64/bin/clang.exe -O2 -fno-strict-aliasing -w -DGBI_FLOATS -DVERSION_US -DNO_SEGMENTED_MEMORY -I$L -I$L/decomp/include sm64audio.c $L/load_audio_data.c $L/play_sound.c $L/debug_print.c $L/decomp/audio/*.c $L/decomp/pc/mixer.c $L/decomp/pc/ultra_reimplementation.c $L/decomp/pc/alBnkfNew.c $L/decomp/tools/convUtils.c $L/decomp/tools/utils.c -o sm64audio_new.exe && mv -f sm64audio_new.exe sm64audio.exe && echo built
