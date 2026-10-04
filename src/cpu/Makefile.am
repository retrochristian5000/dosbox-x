AM_CPPFLAGS = -I$(top_srcdir)/include -I$(top_srcdir)/src

# Header-only CPU core directories do not need recursive Automake Makefiles.
# Keep the headers in the parent target so they remain part of distribution
# archives without adding recursive make hops.
noinst_HEADERS = \
	core_full/ea_lookup.h core_full/load.h core_full/loadwrite.h \
	core_full/op.h core_full/optable.h core_full/save.h \
	core_full/string.h core_full/support.h \
	core_normal/helpers.h core_normal/prefix_none.h core_normal/prefix_66.h \
	core_normal/prefix_0f.h core_normal/support.h core_normal/table_ea.h \
	core_normal/prefix_66_0f.h core_normal/string.h \
	core_normal/prefix_0f_mmx.h core_normal/table_ea_8086.h \
	core_dyn_x86/cache.h core_dyn_x86/helpers.h core_dyn_x86/decoder.h \
	core_dyn_x86/risc_x86.h core_dyn_x86/risc_x64.h core_dyn_x86/string.h \
	core_dyn_x86/dyn_fpu.h core_dyn_x86/dyn_fpu_dh.h \
	core_dynrec/cache.h core_dynrec/decoder.h core_dynrec/decoder_basic.h \
	core_dynrec/decoder_opcodes.h core_dynrec/dyn_fpu.h core_dynrec/operators.h \
	core_dynrec/risc_x64.h core_dynrec/risc_x86.h core_dynrec/risc_mipsel32.h \
	core_dynrec/risc_armv4le.h core_dynrec/risc_armv4le-common.h \
	core_dynrec/risc_armv4le-o3.h core_dynrec/risc_armv4le-thumb.h \
	core_dynrec/risc_armv4le-thumb-iw.h core_dynrec/risc_armv4le-thumb-niw.h \
	core_dynrec/risc_armv8le.h

noinst_LIBRARIES = libcpu.a
libcpu_a_SOURCES = callback.cpp cpu.cpp flags.cpp modrm.cpp modrm.h instructions.h	\
		   paging.cpp lazyflags.h core_normal.cpp core_normal_8086.cpp core_normal_286.cpp core_prefetch.cpp \
		   core_dyn_x86.cpp core_dynrec.cpp mmx.cpp core_prefetch_286.cpp core_prefetch_8086.cpp

if !EMSCRIPTEN
libcpu_a_SOURCES += core_full.cpp core_simple.cpp
endif

