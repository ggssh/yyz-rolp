/*
 * Copyright (c) 2001, 2013, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 *
 */

#ifndef SHARE_VM_GC_INTERFACE_COLLECTEDHEAP_INLINE_HPP
#define SHARE_VM_GC_INTERFACE_COLLECTEDHEAP_INLINE_HPP

#include "gc_interface/allocTracer.hpp"
#include "gc_interface/collectedHeap.hpp"
#include "memory/threadLocalAllocBuffer.inline.hpp"
#include "memory/universe.hpp"
#include "oops/arrayOop.hpp"
#include "prims/jvmtiExport.hpp"
#include "runtime/sharedRuntime.hpp"
#include "runtime/thread.inline.hpp"
#include "services/lowMemoryDetector.hpp"
#include "utilities/copy.hpp"

// Inline allocation implementations.

void CollectedHeap::post_allocation_setup_common(KlassHandle klass,
                                                 HeapWord* obj) {
  post_allocation_setup_no_klass_install(klass, obj);
  post_allocation_install_obj_klass(klass, oop(obj));
}

void CollectedHeap::post_allocation_setup_no_klass_install(KlassHandle klass,
                                                           HeapWord* objPtr) {
  oop obj = (oop)objPtr;

  assert(obj != NULL, "NULL object pointer");
  if (UseBiasedLocking && (klass() != NULL)) {
#ifdef NG2C_PROF
    obj->set_mark(klass->prototype_header()->set_ng2c_prof(klass.as_hash()));
#else
    obj->set_mark(klass->prototype_header());
#endif
  } else {
    // May be bootstrapping
#ifdef NG2C_PROF
    obj->set_mark(markOopDesc::prototype()->set_ng2c_prof(klass.as_hash()));
#else
    obj->set_mark(markOopDesc::prototype());
#endif
  }

#ifdef DEBUG_NG2C_PROF
  markOop m = obj->mark();
  gclog_or_tty->print_cr("[ng2c-prof] post_allocation_setup_no_klass_install oop="INTPTR_FORMAT" mark="INTPTR_FORMAT" age=%d, as_hash="INTPTR_FORMAT,
                         obj, (intptr_t)m, m->age(), m->ng2c_prof());
#endif
}

void CollectedHeap::post_allocation_install_obj_klass(KlassHandle klass,
                                                   oop obj) {
  // These asserts are kind of complicated because of klassKlass
  // and the beginning of the world.
  assert(klass() != NULL || !Universe::is_fully_initialized(), "NULL klass");
  assert(klass() == NULL || klass()->is_klass(), "not a klass");
  assert(obj != NULL, "NULL object pointer");
  obj->set_klass(klass());
  assert(!Universe::is_fully_initialized() || obj->klass() != NULL,
         "missing klass");
}

// Support for jvmti and dtrace
inline void post_allocation_notify(KlassHandle klass, oop obj) {
  // support low memory notifications (no-op if not enabled)
  LowMemoryDetector::detect_low_memory_for_collected_pools();

  // support for JVMTI VMObjectAlloc event (no-op if not enabled)
  JvmtiExport::vm_object_alloc_event_collector(obj);

  if (DTraceAllocProbes) {
    // support for Dtrace object alloc event (no-op most of the time)
    if (klass() != NULL && klass()->name() != NULL) {
      SharedRuntime::dtrace_object_alloc(obj);
    }
  }
}

void CollectedHeap::post_allocation_setup_obj(KlassHandle klass,
                                              HeapWord* obj) {
  post_allocation_setup_common(klass, obj);
  assert(Universe::is_bootstrapping() ||
         !((oop)obj)->is_array(), "must not be an array");
  // notify jvmti and dtrace
  post_allocation_notify(klass, (oop)obj);
}

void CollectedHeap::post_allocation_setup_array(KlassHandle klass,
                                                HeapWord* obj,
                                                int length) {
  // Set array length before setting the _klass field
  // in post_allocation_setup_common() because the klass field
  // indicates that the object is parsable by concurrent GC.
  assert(length >= 0, "length should be non-negative");
  ((arrayOop)obj)->set_length(length);
  post_allocation_setup_common(klass, obj);
  assert(((oop)obj)->is_array(), "must be an array");
  // notify jvmti and dtrace (must be after length is set for dtrace)
  post_allocation_notify(klass, (oop)obj);
}

// <underscore> alloc in tlab if UseTLAB, otherwise, use mem_allocate from heap
HeapWord* CollectedHeap::common_mem_allocate_noinit(KlassHandle klass, size_t size, TRAPS) {

  // Clear unhandled oops for memory allocation.  Memory allocation might
  // not take out a lock if from tlab, so clear here.
  CHECK_UNHANDLED_OOPS_ONLY(THREAD->clear_unhandled_oops();)
  // <yyz>
  update_obj_malloc_count();
  update_obj_malloc_size(size * HeapWordSize);
  if (HAS_PENDING_EXCEPTION) {
    NOT_PRODUCT(guarantee(false, "Should not allocate with exception pending"));
    return NULL;  // caller does a CHECK_0 too
  }
  // if (klass.alloc_gen()) {
  //   gclog_or_tty->print_cr("<yyz> obj alloc, gen = %d, size = %zu", THREAD->alloc_gen(), size);
  // }

  HeapWord* result = NULL;
  // <underscore> UseTLAB is a runtime flag. It should always be on.
  if (UseTLAB) {
    result = allocate_from_tlab(klass, THREAD, size);
    if (result != NULL) {
      assert(!HAS_PENDING_EXCEPTION,
             "Unexpected exception, will result in uninitialized storage");
      return result;
    }
  }
  bool gc_overhead_limit_was_exceeded = false;

  // <underscore>
#if DEBUG_OBJ_ALLOC
  gclog_or_tty->print_cr("<underscore> CollectedHeap::common_mem_allocate_noinit (going to mem allocate) thread=%p, size="SIZE_FORMAT") ", THREAD, size);
#endif
  // </underscore>
#if DEBUG_LARGE_OBJ_ALLOC
   gclog_or_tty->print_cr(klass->external_name());
#endif
  // <underscore> Added gen and is_gen_alloc arguments.
  result = Universe::heap()->mem_allocate(size,
                                          &gc_overhead_limit_was_exceeded,
                                          klass.alloc_gen() ? true : false,
                                          THREAD->alloc_gen());
  if (result != NULL) {
    NOT_PRODUCT(Universe::heap()->
      check_for_non_bad_heap_word_value(result, size));
    assert(!HAS_PENDING_EXCEPTION,
           "Unexpected exception, will result in uninitialized storage");
    THREAD->incr_allocated_bytes(size * HeapWordSize);

    AllocTracer::send_allocation_outside_tlab_event(klass, size * HeapWordSize);

    return result;
  }


  if (!gc_overhead_limit_was_exceeded) {
    // -XX:+HeapDumpOnOutOfMemoryError and -XX:OnOutOfMemoryError support
    report_java_out_of_memory("Java heap space");

    if (JvmtiExport::should_post_resource_exhausted()) {
      JvmtiExport::post_resource_exhausted(
        JVMTI_RESOURCE_EXHAUSTED_OOM_ERROR | JVMTI_RESOURCE_EXHAUSTED_JAVA_HEAP,
        "Java heap space");
    }

    THROW_OOP_0(Universe::out_of_memory_error_java_heap());
  } else {
    // -XX:+HeapDumpOnOutOfMemoryError and -XX:OnOutOfMemoryError support
    report_java_out_of_memory("GC overhead limit exceeded");

    if (JvmtiExport::should_post_resource_exhausted()) {
      JvmtiExport::post_resource_exhausted(
        JVMTI_RESOURCE_EXHAUSTED_OOM_ERROR | JVMTI_RESOURCE_EXHAUSTED_JAVA_HEAP,
        "GC overhead limit exceeded");
    }

    THROW_OOP_0(Universe::out_of_memory_error_gc_overhead_limit());
  }
}

// <underscore> alloc, init
HeapWord* CollectedHeap::common_mem_allocate_init(KlassHandle klass, size_t size, TRAPS) {
  HeapWord* obj = common_mem_allocate_noinit(klass, size, CHECK_NULL);
  init_obj(obj, size);
  return obj;
}

// <underscore> allocation from tlab. Introduce if to select tlab?
HeapWord* CollectedHeap::allocate_from_tlab(KlassHandle klass, Thread* thread, size_t size) {
  assert(UseTLAB, "should use UseTLAB");

// <underscore>
#if DEBUG_OBJ_ALLOC
    gclog_or_tty->print_cr("<underscore> CollectedHeap::allocate_from_tlab(klass->alloc_gen=%d, thread_gen=%d, thread=%p, size="SIZE_FORMAT") ", klass.alloc_gen(), thread->alloc_gen(), thread, size);
#endif

  HeapWord* obj = klass.alloc_gen() ?
      thread->tlab_gen().allocate(size) : thread->tlab().allocate(size);
  if (obj != NULL) {

#if DEBUG_OBJ_ALLOC
    gclog_or_tty->print_cr("<underscore> CollectedHeap::allocate_from_tlab -> obj allocated at %p", obj);
#endif
// </undescore>
    return obj;
  }
  // Otherwise...
  return allocate_from_tlab_slow(klass, thread, size);
}

void CollectedHeap::init_obj(HeapWord* obj, size_t size) {
  assert(obj != NULL, "cannot initialize NULL object");
  const size_t hs = oopDesc::header_size();
  assert(size >= hs, "unexpected object size");
  ((oop)obj)->set_klass_gap(0);
  Copy::fill_to_aligned_words(obj + hs, size - hs);
}

// <underscore> Added gen parameter.
oop CollectedHeap::obj_allocate(KlassHandle klass, int gen, int size, TRAPS) {
  debug_only(check_for_valid_allocation_state());
  assert(!Universe::heap()->is_gc_active(), "Allocation during gc not allowed");
  assert(size >= 0, "int won't convert to size_t");

// <underscore>
#ifdef NG2C_PROF
  // Note: if NG2C_PROF is enabled, gen will contain a hash of the allocation site.
  // If gen is zero, it means that are probably coming from interpreted code.
  if (gen != 0) {
    unsigned int context        = mask_bits ((uintptr_t)THREAD->context(),  0xFFFF);
    unsigned int alloc_site_id  = mask_bits ((uintptr_t)gen,                0xFFFF);
    // Note: gen := 16 bit alloc site id followed by 16 bit context.
    unsigned int mark = (alloc_site_id << 16) | context;
    NGenerationArray * ngen = Universe::method_bci_hashtable()->get_entry(alloc_site_id);

    assert(ngen != NULL, "there should be an ngen array for each alloc site id");

    ngen->inc_number_allocs(context);
    // Deciding in which generation to allocate.
    klass.set_alloc_gen(ngen->target_gen(context));
    // Setting allocation site hash into handle (will be used to mark header).
    klass.set_as_hash(mark);
    // Setting up thread's current alloc gen (will be used by the slow path alloc).
    THREAD->set_alloc_gen(klass.alloc_gen());
  }
  // TODO - check thread for bit that requests for gen reconstruction.
#else
  klass.set_alloc_gen(gen);
#endif

#if DEBUG_SLOW_PATH_ALLOC
  gclog_or_tty->print_cr("[ng2c-slow-path-alloc] CollectedHeap::array_allocate -> size="SIZE_FORMAT" gen=%d hash="INTPTR_FORMAT,
          size, klass.alloc_gen(), klass.as_hash());
#endif
// </undescore>

  HeapWord* obj = common_mem_allocate_init(klass, size, CHECK_NULL);
  post_allocation_setup_obj(klass, obj);
  NOT_PRODUCT(Universe::heap()->check_for_bad_heap_word_value(obj, size));
  return (oop)obj;
}

// <underscore> Added gen parameter.
oop CollectedHeap::array_allocate(KlassHandle klass,
                                  int gen,
                                  int size,
                                  int length,
                                  TRAPS) {
  debug_only(check_for_valid_allocation_state());
  assert(!Universe::heap()->is_gc_active(), "Allocation during gc not allowed");
  assert(size >= 0, "int won't convert to size_t");

// <underscore>
#ifdef NG2C_PROF
  // Note: if NG2C_PROF is enabled, gen will contain a hash of the allocation site.
  // If gen is zero, it means that are probably coming from interpreted code.
  if (gen != 0) {
    unsigned int context        = mask_bits ((uintptr_t)THREAD->context(),  0xFFFF);
    unsigned int alloc_site_id  = mask_bits ((uintptr_t)gen,                0xFFFF);
    // Note: gen := 16 bit alloc site id followed by 16 bit context.
    unsigned int mark = (alloc_site_id << 16) | context;
    NGenerationArray * ngen = Universe::method_bci_hashtable()->get_entry(alloc_site_id);

    assert(ngen != NULL, "there should be an ngen array for each alloc site id");

    ngen->inc_number_allocs(context);
    // Deciding in which generation to allocate.
    klass.set_alloc_gen(ngen->target_gen(context));
    // Setting allocation site hash into handle (will be used to mark header).
    klass.set_as_hash(mark);
    // Setting up thread's current alloc gen (will be used by the slow path alloc).
    THREAD->set_alloc_gen(klass.alloc_gen());
  }
#else
  klass.set_alloc_gen(gen);
#endif

#if DEBUG_SLOW_PATH_ALLOC
  gclog_or_tty->print_cr("[ng2c-slow-path-alloc] CollectedHeap::array_allocate -> size="SIZE_FORMAT" gen=%d hash="INTPTR_FORMAT" length=%d",
          size, klass.alloc_gen(), klass.as_hash(), length);
#endif
// </undescore>

  HeapWord* obj = common_mem_allocate_init(klass, size, CHECK_NULL);
  post_allocation_setup_array(klass, obj, length);
  NOT_PRODUCT(Universe::heap()->check_for_bad_heap_word_value(obj, size));
  return (oop)obj;
}

// <underscore> Added gen parameter.
oop CollectedHeap::array_allocate_nozero(KlassHandle klass,
                                         int gen,
                                         int size,
                                         int length,
                                         TRAPS) {
  debug_only(check_for_valid_allocation_state());
  assert(!Universe::heap()->is_gc_active(), "Allocation during gc not allowed");
  assert(size >= 0, "int won't convert to size_t");

// <underscore>
#ifdef NG2C_PROF
  // Note: if NG2C_PROF is enabled, gen will contain a hash of the allocation site.
  // If gen is zero, it means that are probably coming from interpreted code.
  if (gen != 0) {
    unsigned int context        = mask_bits ((uintptr_t)THREAD->context(),  0xFFFF);
    unsigned int alloc_site_id  = mask_bits ((uintptr_t)gen,                0xFFFF);
    // Note: gen := 16 bit alloc site id followed by 16 bit context.
    unsigned int mark = (alloc_site_id << 16) | context;
    NGenerationArray * ngen = Universe::method_bci_hashtable()->get_entry(alloc_site_id);

    assert(ngen != NULL, "there should be an ngen array for each alloc site id");

    ngen->inc_number_allocs(context);
    // Deciding in which generation to allocate.
    klass.set_alloc_gen(ngen->target_gen(context));
    // Setting allocation site hash into handle (will be used to mark header).
    klass.set_as_hash(mark);
    // Setting up thread's current alloc gen (will be used by the slow path alloc).
    THREAD->set_alloc_gen(klass.alloc_gen());
  }
#else
  klass.set_alloc_gen(gen);
#endif

#if DEBUG_SLOW_PATH_ALLOC
  gclog_or_tty->print_cr("[ng2c-slow-path-alloc] CollectedHeap::array_allocate_nozero -> size="SIZE_FORMAT" gen=%d hash="INTPTR_FORMAT" length=%d",
          size, klass.alloc_gen(), klass.as_hash(), length);
#endif
// </undescore>

  HeapWord* obj = common_mem_allocate_noinit(klass, size, CHECK_NULL);
  ((oop)obj)->set_klass_gap(0);
  post_allocation_setup_array(klass, obj, length);
#ifndef PRODUCT
  const size_t hs = oopDesc::header_size()+1;
  Universe::heap()->check_for_non_bad_heap_word_value(obj+hs, size-hs);
#endif
  return (oop)obj;
}

inline void CollectedHeap::oop_iterate_no_header(OopClosure* cl) {
  NoHeaderExtendedOopClosure no_header_cl(cl);
  oop_iterate(&no_header_cl);
}

#ifndef PRODUCT

inline bool
CollectedHeap::promotion_should_fail(volatile size_t* count) {
  // Access to count is not atomic; the value does not have to be exact.
  if (PromotionFailureALot) {
    const size_t gc_num = total_collections();
    const size_t elapsed_gcs = gc_num - _promotion_failure_alot_gc_number;
    if (elapsed_gcs >= PromotionFailureALotInterval) {
      // Test for unsigned arithmetic wrap-around.
      if (++*count >= PromotionFailureALotCount) {
        *count = 0;
        return true;
      }
    }
  }
  return false;
}

inline bool CollectedHeap::promotion_should_fail() {
  return promotion_should_fail(&_promotion_failure_alot_count);
}

inline void CollectedHeap::reset_promotion_should_fail(volatile size_t* count) {
  if (PromotionFailureALot) {
    _promotion_failure_alot_gc_number = total_collections();
    *count = 0;
  }
}

inline void CollectedHeap::reset_promotion_should_fail() {
  reset_promotion_should_fail(&_promotion_failure_alot_count);
}
#endif  // #ifndef PRODUCT

#endif // SHARE_VM_GC_INTERFACE_COLLECTEDHEAP_INLINE_HPP
