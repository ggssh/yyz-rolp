#
# Copyright (c) 1999, 2013, Oracle and/or its affiliates. All rights reserved.
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
#
# This code is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License version 2 only, as
# published by the Free Software Foundation.
#
# This code is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# version 2 for more details (a copy is included in the LICENSE file that
# accompanied this code).
#
# You should have received a copy of the GNU General Public License version
# 2 along with this work; if not, write to the Free Software Foundation,
# Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
#
# Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
# or visit www.oracle.com if you need additional information or have any
# questions.
#
#

# Rules to build JVM and related libraries, included from vm.make in the build
# directory.

# Common build rules.
MAKEFILES_DIR=$(GAMMADIR)/make/$(Platform_os_family)/makefiles
include $(MAKEFILES_DIR)/rules.make
include $(GAMMADIR)/make/altsrc.make

default: build

#----------------------------------------------------------------------
# Defs

GENERATED     = ../generated
DEP_DIR       = $(GENERATED)/dependencies

# reads the generated files defining the set of .o's and the .o .h dependencies
-include $(DEP_DIR)/*.d

# read machine-specific adjustments (%%% should do this via buildtree.make?)
ifeq ($(findstring true, $(JVM_VARIANT_ZERO) $(JVM_VARIANT_ZEROSHARK)), true)
  include $(MAKEFILES_DIR)/zeroshark.make
else
  include $(MAKEFILES_DIR)/$(BUILDARCH).make
  -include $(HS_ALT_MAKE)/$(Platform_os_family)/makefiles/$(BUILDARCH).make
endif

# set VPATH so make knows where to look for source files
# Src_Dirs_V is everything in src/share/vm/*, plus the right os/*/vm and cpu/*/vm
# The adfiles directory contains ad_<arch>.[ch]pp.
# The jvmtifiles directory contains jvmti*.[ch]pp
Src_Dirs_V += $(GENERATED)/adfiles $(GENERATED)/jvmtifiles $(GENERATED)/tracefiles
VPATH += $(Src_Dirs_V:%=%:)

# set INCLUDES for C preprocessor.
Src_Dirs_I += $(GENERATED)
# The order is important for the precompiled headers to work.
INCLUDES += $(PRECOMPILED_HEADER_DIR:%=-I%) $(Src_Dirs_I:%=-I%)

# SYMFLAG is used by {jsig,saproc}.make
ifeq ($(ENABLE_FULL_DEBUG_SYMBOLS),1)
  # always build with debug info when we can create .debuginfo files
  SYMFLAG = -g
else
  ifeq (${VERSION}, debug)
    SYMFLAG = -g
  else
    SYMFLAG =
  endif
endif


# <NG2C sysdefs>
## Enables n-generational profiler
SYSDEFS += -DNG2C_PROF
## Allows the target gen to be updated.
#SYSDEFS += -DNG2C_PROF_ALLOC
## Allows the context to be expanded.
SYSDEFS += -DNG2C_PROF_CONTEXT


#SYSDEFS += -DDISABLE_NG2C_PROF_VMOP
#SYSDEFS += -DDISABLE_NG2C_PROF_SURVIVORS
#SYSDEFS += -DDISABLE_NG2C_PROF_C2
#SYSDEFS += -DDISABLE_NG2C_PROF_C2_TAGGING
#SYSDEFS += -DDISABLE_NG2C_PROF_C2_TLAB
#SYSDEFS += -DDISABLE_NG2C_PROF_C2_COUNTERS
## Disables context tracking (method calls patching)
#SYSDEFS += -DDISABLE_NG2C_PROF_C2_CONTEXT

#SYSDEFS += -DFORCE_SLOWPATH_C2
#SYSDEFS += -DFORCE_SLOWPATH_INTR
#SYSDEFS += -DFORCE_NG2C_HR_VERIFY

# This flag should be on because disabling it introduces some race condition
# on the number of active tlabs per HR. This is specially easy to blow if
# contexts are enabled. Turning this on seems not to lead to significant
# performanace degradation.
SYSDEFS += -DDISABLE_NG2C_PROF_BOT_UPDATES

# Used only to debug mark oop ng2c install.
#SYSDEFS += -DDEBUG_NG2C_PROF

#SYSDEFS += -DDEBUG_NG2C_PROF_ALLOCS_TABLE
#SYSDEFS += -DDEBUG_NG2C_PROF_C2
## Prints jit patches to track context.
#SYSDEFS += -DDEBUG_NG2C_PROF_C2_CONTEXT
## Prints the re-calculation of the context.
#SYSDEFS += -DDEBUG_NG2C_PROF_CALCULATE_CONTEXT
SYSDEFS += -DDEBUG_NG2C_PROF_VMOP
SYSDEFS += -DDEBUG_NG2C_PROF_VMOP_UPDATE
## Prints the building up of the static analysis map
#SYSDEFS += -DDEBUG_NG2C_PROF_SANALYSIS
#SYSDEFS += -DPRINT_NG2C_PROF_SANALYSIS

# SYSDEFS += -DDEBUG_REM_SET

#SYSDEFS += -DDEBUG_SURVIVORS
#SYSDEFS += -DDEBUG_C2
#SYSDEFS += -DDEBUG_C2_MARR
# </NG2C sysdefs>

# HOTSPOT_RELEASE_VERSION and HOTSPOT_BUILD_VERSION are defined
# in $(GAMMADIR)/make/defs.make
ifeq ($(HOTSPOT_BUILD_VERSION),)
  BUILD_VERSION = -DHOTSPOT_RELEASE_VERSION="\"$(HOTSPOT_RELEASE_VERSION)\""
else
  BUILD_VERSION = -DHOTSPOT_RELEASE_VERSION="\"$(HOTSPOT_RELEASE_VERSION)-$(HOTSPOT_BUILD_VERSION)\""
endif

# The following variables are defined in the generated flags.make file.
BUILD_VERSION = -DHOTSPOT_RELEASE_VERSION="\"$(HS_BUILD_VER)\""
JRE_VERSION   = -DJRE_RELEASE_VERSION="\"$(JRE_RELEASE_VER)\""
HS_LIB_ARCH   = -DHOTSPOT_LIB_ARCH=\"$(LIBARCH)\"
BUILD_TARGET  = -DHOTSPOT_BUILD_TARGET="\"$(TARGET)\""
BUILD_USER    = -DHOTSPOT_BUILD_USER="\"$(HOTSPOT_BUILD_USER)\""
VM_DISTRO     = -DHOTSPOT_VM_DISTRO="\"$(HOTSPOT_VM_DISTRO)\""

CXXFLAGS =           \
  ${SYSDEFS}         \
  ${INCLUDES}        \
  ${BUILD_VERSION}   \
  ${BUILD_TARGET}    \
  ${BUILD_USER}      \
  ${HS_LIB_ARCH}     \
  ${VM_DISTRO}

# This is VERY important! The version define must only be supplied to vm_version.o
# If not, ccache will not re-use the cache at all, since the version string might contain
# a time and date.
CXXFLAGS/vm_version.o += ${JRE_VERSION}

CXXFLAGS/BYFILE = $(CXXFLAGS/$@)

# File specific flags
CXXFLAGS += $(CXXFLAGS/BYFILE)

# Large File Support
ifneq ($(LP64), 1)
CXXFLAGS/ostream.o += -D_FILE_OFFSET_BITS=64
endif # ifneq ($(LP64), 1)

# CFLAGS_WARN holds compiler options to suppress/enable warnings.
CFLAGS += $(CFLAGS_WARN/BYFILE)

# Do not use C++ exception handling
CFLAGS += $(CFLAGS/NOEX)

# Extra flags from gnumake's invocation or environment
CFLAGS += $(EXTRA_CFLAGS)
LFLAGS += $(EXTRA_CFLAGS)

# Don't set excutable bit on stack segment
# the same could be done by separate execstack command
LFLAGS += -Xlinker -z -Xlinker noexecstack

LIBS += -lm -ldl -lpthread

# By default, link the *.o into the library, not the executable.
LINK_INTO$(LINK_INTO) = LIBJVM

JDK_LIBDIR = $(JAVA_HOME)/jre/lib/$(LIBARCH)

#----------------------------------------------------------------------
# jvm_db & dtrace
include $(MAKEFILES_DIR)/dtrace.make

#----------------------------------------------------------------------
# JVM

JVM      = jvm
LIBJVM   = lib$(JVM).so

LIBJVM_DEBUGINFO   = lib$(JVM).debuginfo
LIBJVM_DIZ         = lib$(JVM).diz

SPECIAL_PATHS:=adlc c1 gc_implementation opto shark libadt

SOURCE_PATHS=\
  $(shell find $(HS_COMMON_SRC)/share/vm/* -type d \! \
      \( -name DUMMY $(foreach dir,$(SPECIAL_PATHS),-o -name $(dir)) \))
SOURCE_PATHS+=$(HS_COMMON_SRC)/os/$(Platform_os_family)/vm
SOURCE_PATHS+=$(HS_COMMON_SRC)/os/posix/vm
SOURCE_PATHS+=$(HS_COMMON_SRC)/cpu/$(Platform_arch)/vm
SOURCE_PATHS+=$(HS_COMMON_SRC)/os_cpu/$(Platform_os_arch)/vm

CORE_PATHS=$(foreach path,$(SOURCE_PATHS),$(call altsrc,$(path)) $(path))
CORE_PATHS+=$(GENERATED)/jvmtifiles $(GENERATED)/tracefiles

ifneq ($(INCLUDE_TRACE), false)
CORE_PATHS+=$(shell if [ -d $(HS_ALT_SRC)/share/vm/jfr ]; then \
  find $(HS_ALT_SRC)/share/vm/jfr -type d; \
  fi)
endif

COMPILER1_PATHS := $(call altsrc,$(HS_COMMON_SRC)/share/vm/c1)
COMPILER1_PATHS += $(HS_COMMON_SRC)/share/vm/c1

COMPILER2_PATHS := $(call altsrc,$(HS_COMMON_SRC)/share/vm/opto)
COMPILER2_PATHS += $(call altsrc,$(HS_COMMON_SRC)/share/vm/libadt)
COMPILER2_PATHS += $(HS_COMMON_SRC)/share/vm/opto
COMPILER2_PATHS += $(HS_COMMON_SRC)/share/vm/libadt
COMPILER2_PATHS += $(GENERATED)/adfiles

SHARK_PATHS := $(GAMMADIR)/src/share/vm/shark

# Include dirs per type.
Src_Dirs/CORE      := $(CORE_PATHS)
Src_Dirs/COMPILER1 := $(CORE_PATHS) $(COMPILER1_PATHS)
Src_Dirs/COMPILER2 := $(CORE_PATHS) $(COMPILER2_PATHS)
Src_Dirs/TIERED    := $(CORE_PATHS) $(COMPILER1_PATHS) $(COMPILER2_PATHS)
Src_Dirs/ZERO      := $(CORE_PATHS)
Src_Dirs/SHARK     := $(CORE_PATHS) $(SHARK_PATHS)
Src_Dirs := $(Src_Dirs/$(TYPE))

COMPILER2_SPECIFIC_FILES := opto libadt bcEscapeAnalyzer.cpp c2_\* runtime_\*
COMPILER1_SPECIFIC_FILES := c1_\*
SHARK_SPECIFIC_FILES     := shark
ZERO_SPECIFIC_FILES      := zero

# Always exclude these.
Src_Files_EXCLUDE += jsig.c jvmtiEnvRecommended.cpp jvmtiEnvStub.cpp

# Exclude per type.
Src_Files_EXCLUDE/CORE      := $(COMPILER1_SPECIFIC_FILES) $(COMPILER2_SPECIFIC_FILES) $(ZERO_SPECIFIC_FILES) $(SHARK_SPECIFIC_FILES) ciTypeFlow.cpp
Src_Files_EXCLUDE/COMPILER1 := $(COMPILER2_SPECIFIC_FILES) $(ZERO_SPECIFIC_FILES) $(SHARK_SPECIFIC_FILES) ciTypeFlow.cpp
Src_Files_EXCLUDE/COMPILER2 := $(COMPILER1_SPECIFIC_FILES) $(ZERO_SPECIFIC_FILES) $(SHARK_SPECIFIC_FILES)
Src_Files_EXCLUDE/TIERED    := $(ZERO_SPECIFIC_FILES) $(SHARK_SPECIFIC_FILES)
Src_Files_EXCLUDE/ZERO      := $(COMPILER1_SPECIFIC_FILES) $(COMPILER2_SPECIFIC_FILES) $(SHARK_SPECIFIC_FILES) ciTypeFlow.cpp
Src_Files_EXCLUDE/SHARK     := $(COMPILER1_SPECIFIC_FILES) $(COMPILER2_SPECIFIC_FILES) $(ZERO_SPECIFIC_FILES)

Src_Files_EXCLUDE +=  $(Src_Files_EXCLUDE/$(TYPE))

# Special handling of arch model.
ifeq ($(Platform_arch_model), x86_32)
Src_Files_EXCLUDE += \*x86_64\*
endif
ifeq ($(Platform_arch_model), x86_64)
Src_Files_EXCLUDE += \*x86_32\*
endif

# Alternate vm.make
# This has to be included here to allow changes to the source
# directories and excluded files before they are expanded
# by the definition of Src_Files.
-include $(HS_ALT_MAKE)/$(Platform_os_family)/makefiles/vm.make

# Locate all source files in the given directory, excluding files in Src_Files_EXCLUDE.
define findsrc
	$(notdir $(shell find $(1)/. ! -name . -prune \
		-a \( -name \*.c -o -name \*.cpp -o -name \*.s \) \
		-a ! \( -name DUMMY $(addprefix -o -name ,$(Src_Files_EXCLUDE)) \)))
endef

Src_Files := $(foreach e,$(Src_Dirs),$(call findsrc,$(e)))

Obj_Files = $(sort $(addsuffix .o,$(basename $(Src_Files))))

JVM_OBJ_FILES = $(Obj_Files)

vm_version.o: $(filter-out vm_version.o,$(JVM_OBJ_FILES))

mapfile : $(MAPFILE) vm.def
	rm -f $@
	awk '{ if ($$0 ~ "INSERT VTABLE SYMBOLS HERE")	\
                 { system ("cat vm.def"); }		\
               else					\
                 { print $$0 }				\
             }' > $@ < $(MAPFILE)

mapfile_reorder : mapfile $(REORDERFILE)
	rm -f $@
	cat $^ > $@

vm.def: $(Res_Files) $(Obj_Files)
	sh $(GAMMADIR)/make/linux/makefiles/build_vm_def.sh *.o > $@

ifeq ($(JVM_VARIANT_ZEROSHARK), true)
  STATIC_CXX = false
else
  ifeq ($(ZERO_LIBARCH), ppc64)
    STATIC_CXX = false
  else
    STATIC_CXX = true
  endif
endif

ifeq ($(LINK_INTO),AOUT)
  LIBJVM.o                 =
  LIBJVM_MAPFILE           =
  LIBS_VM                  = $(LIBS)
else
  LIBJVM.o                 = $(JVM_OBJ_FILES)
  LIBJVM_MAPFILE$(LDNOMAP) = mapfile_reorder
  LFLAGS_VM$(LDNOMAP)      += $(MAPFLAG:FILENAME=$(LIBJVM_MAPFILE))
  LFLAGS_VM                += $(SONAMEFLAG:SONAME=$(LIBJVM))

  # JVM is statically linked with libgcc[_s] and libstdc++; this is needed to
  # get around library dependency and compatibility issues. Must use gcc not
  # g++ to link.
  ifeq ($(STATIC_CXX), true)
    LFLAGS_VM              += $(STATIC_LIBGCC)
    LIBS_VM                += $(STATIC_STDCXX)
  else
    LIBS_VM                += -lstdc++
  endif

  LIBS_VM                  += $(LIBS)
endif
ifeq ($(JVM_VARIANT_ZERO), true)
  LIBS_VM += $(LIBFFI_LIBS)
endif
ifeq ($(JVM_VARIANT_ZEROSHARK), true)
  LIBS_VM   += $(LIBFFI_LIBS) $(LLVM_LIBS)
  LFLAGS_VM += $(LLVM_LDFLAGS)
endif

LINK_VM = $(LINK_LIB.CC)

# rule for building precompiled header
$(PRECOMPILED_HEADER):
	$(QUIETLY) echo Generating precompiled header $@
	$(QUIETLY) mkdir -p $(PRECOMPILED_HEADER_DIR)
	$(QUIETLY) $(COMPILE.CXX) $(DEPFLAGS) -x c++-header $(PRECOMPILED_HEADER_SRC) -o $@ $(COMPILE_DONE)

# making the library:

ifneq ($(JVM_BASE_ADDR),)
# By default shared library is linked at base address == 0. Modify the
# linker script if JVM prefers a different base location. It can also be
# implemented with 'prelink -r'. But 'prelink' is not (yet) available on
# our build platform (AS-2.1).
LD_SCRIPT = libjvm.so.lds
$(LD_SCRIPT): $(LIBJVM_MAPFILE)
	$(QUIETLY) {                                                \
	  rm -rf $@;                                                \
	  $(LINK_VM) -Wl,--verbose $(LFLAGS_VM) 2>&1             |  \
	    sed -e '/^======/,/^======/!d'                          \
		-e '/^======/d'                                     \
		-e 's/0\( + SIZEOF_HEADERS\)/$(JVM_BASE_ADDR)\1/'   \
		> $@;                                               \
	}
LD_SCRIPT_FLAG = -Wl,-T,$(LD_SCRIPT)
endif

# With more recent Redhat releases (or the cutting edge version Fedora), if
# SELinux is configured to be enabled, the runtime linker will fail to apply
# the text relocation to libjvm.so considering that it is built as a non-PIC
# DSO. To workaround that, we run chcon to libjvm.so after it is built. See
# details in bug 6538311.
$(LIBJVM): $(LIBJVM.o) $(LIBJVM_MAPFILE) $(LD_SCRIPT)
	$(QUIETLY) {                                                    \
	    echo Linking vm...;                                         \
	    $(LINK_LIB.CXX/PRE_HOOK)                                     \
	    $(LINK_VM) $(LD_SCRIPT_FLAG)                                \
		       $(LFLAGS_VM) -o $@ $(sort $(LIBJVM.o)) $(LIBS_VM);       \
	    $(LINK_LIB.CXX/POST_HOOK)                                    \
	    rm -f $@.1; ln -s $@ $@.1;                                  \
            if [ \"$(CROSS_COMPILE_ARCH)\" = \"\" ] ; then                    \
	      if [ -x /usr/sbin/selinuxenabled ] ; then                 \
	        /usr/sbin/selinuxenabled;                               \
                if [ $$? = 0 ] ; then					\
		  /usr/bin/chcon -t textrel_shlib_t $@;                 \
		  if [ $$? != 0 ]; then                                 \
		    echo "ERROR: Cannot chcon $@";			\
		  fi							\
	        fi							\
	      fi                                                        \
            fi 								\
	}

ifeq ($(ENABLE_FULL_DEBUG_SYMBOLS),1)
	$(QUIETLY) $(OBJCOPY) --only-keep-debug $@ $(LIBJVM_DEBUGINFO)
	$(QUIETLY) $(OBJCOPY) --add-gnu-debuglink=$(LIBJVM_DEBUGINFO) $@
  ifeq ($(STRIP_POLICY),all_strip)
	$(QUIETLY) $(STRIP) $@
  else
    ifeq ($(STRIP_POLICY),min_strip)
	$(QUIETLY) $(STRIP) -g $@
    # implied else here is no stripping at all
    endif
  endif
  ifeq ($(ZIP_DEBUGINFO_FILES),1)
	$(ZIPEXE) -q -y $(LIBJVM_DIZ) $(LIBJVM_DEBUGINFO)
	$(RM) $(LIBJVM_DEBUGINFO)
  endif
endif

DEST_SUBDIR        = $(JDK_LIBDIR)/$(VM_SUBDIR)
DEST_JVM           = $(DEST_SUBDIR)/$(LIBJVM)
DEST_JVM_DEBUGINFO = $(DEST_SUBDIR)/$(LIBJVM_DEBUGINFO)
DEST_JVM_DIZ       = $(DEST_SUBDIR)/$(LIBJVM_DIZ)

install_jvm: $(LIBJVM)
	@echo "Copying $(LIBJVM) to $(DEST_JVM)"
	$(QUIETLY) test -f $(LIBJVM_DEBUGINFO) && \
	    cp -f $(LIBJVM_DEBUGINFO) $(DEST_JVM_DEBUGINFO)
	$(QUIETLY) test -f $(LIBJVM_DIZ) && \
	    cp -f $(LIBJVM_DIZ) $(DEST_JVM_DIZ)
	$(QUIETLY) cp -f $(LIBJVM) $(DEST_JVM) && echo "Done"

#----------------------------------------------------------------------
# Other files

# Signal interposition library
include $(MAKEFILES_DIR)/jsig.make

# Serviceability agent
include $(MAKEFILES_DIR)/saproc.make

#----------------------------------------------------------------------

build: $(LIBJVM) $(LAUNCHER) $(LIBJSIG) $(LIBJVM_DB) $(BUILDLIBSAPROC) dtraceCheck

install: install_jvm install_jsig install_saproc

.PHONY: default build install install_jvm $(HS_ALT_MAKE)/$(Platform_os_family)/makefiles/$(BUILDARCH).make $(HS_ALT_MAKE)/$(Platform_os_family)/makefiles/vm.make