(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

header {* Abstract datatype for the abstract specification *}

theory ADT_AI
imports
  "../../lib/Simulation"
  Invariants_AI
begin

text {*
  The general refinement calculus (see theory Simulation) requires
  the definition of a so-called ``abstract datatype'' for each refinement layer.
  This theory defines this datatype for the abstract specification.
  Along the path, the theory extends the abstract specification of the kernel
  with respect to user-mode transitions.
*}

text {*
  We constrain idle thread behaviour, so we distinguish three main
  machine control states:
*}
datatype mode = UserMode | KernelMode | IdleMode

text {*
  The global state contains the current user's register context of the machine
  as well as the internal kernel state, the mode and the current event (if any).
*}
type_synonym 'k global_state = "(user_context \<times> 'k) \<times> mode \<times> event option"

text {*
  As observable state, we take the global abstract state.
*}
type_synonym 'a observable = "('a state) global_state"

text {*
  From the kernel's perspective,
  the user memory is a mapping from addresses to bytes.
  A virtual-memory view will later on be built on top of that.
*}
type_synonym user_mem = "word32 \<Rightarrow> word8 option"

text {*
  A user state consists of a register context and (physical) user memory.
*}
type_synonym user_state = "user_context \<times> user_mem"

text {* Virtual-memory mapping: translates virtual to physical addresses *}
type_synonym vm_mapping = "word32 \<rightharpoonup> word32"

text {* Memory rights for each virtual adress *}
type_synonym mem_rights = "word32 \<Rightarrow> vm_rights"

text {*
  A user transition is characterized by a function
  that takes the following arguments:
  a current thread identifier,
  a virtual-memory mapping
    (i.e., a partial function from virtual to physical addresses),
  a memory-rights mapping
    (i.e., a partial function from virtual addresses to rights).

  The function is then a non-deterministic state monad on user state,
  returning an optional kernel-entry event.

  Note that the current-thread identifiers are identical in both specs
    (i.e. @{term "Structures_A.cur_thread \<Colon> 'z state \<Rightarrow> obj_ref"}
          in the abstract kernel model and
          @{text "KernelStateData_H.ksCurThread \<Colon> kernel_state \<Rightarrow> machine_word"}
          in the executable specification).
*}
type_synonym user_transition =
  "obj_ref \<Rightarrow> vm_mapping \<Rightarrow> mem_rights \<Rightarrow> (user_state, event option) nondet_monad"

text {* Abbreviation for user context plus additional state *}
type_synonym 'k uc_state = "user_context \<times> 'k"

text {*
  The following definition models machine and kernel entry/exit behaviour
  abstractly.
  Furthermore, it constrains the behaviour of user threads as well as
  the idle thread.

  The first parameter is used to check of pending interrupts, potentially
  modifying the machine state embedded in the kernel state. 
  The second parameter lifts a user-thread transition into 
  the kernel state (i.e. the new user memory should be injected into the 
  kernel state) and the third parameter provides a kernel specification (it
  will later be used with the abstract specification, the executable
  specification, as well as the C implementation).

  Despite the fact that the global automaton does not distinguish different
  kinds of transitions to the outside world, the definition groups them into
  6 kinds:
  1. Kernel transition: The kernel specification is started in kernel mode and
     uses the event part of the state as input.
     The next control state will either be user mode or idle mode
     (idle thread running).
  2. Normal user-mode executions.
     The computed new user states are then lifted into the kernel state
     using the first parameter to the definition below.
  3. and 4. Event generation in user mode.
     In user mode, events may be generated by the user and 
     any interrupt can be generated at any time. 
  5. and 6. Finally, events generated by the idle thread.
     These can only be interrupts. If there is no interrupt, we stay in idle mode.
*}
definition
  global_automaton ::
    "('k uc_state \<times> (bool \<times> 'k uc_state)) set
     \<Rightarrow> ('k uc_state \<times> (event option \<times> 'k uc_state)) set
     \<Rightarrow> (event \<Rightarrow> ('k uc_state \<times> mode \<times> 'k uc_state) set)
     \<Rightarrow> ('k global_state \<times> 'k global_state) set"
  where
  "global_automaton get_active_irq do_user_op kernel_call \<equiv>
  (* Kernel transition *)
     { ( (s, KernelMode, Some e),
         (s', m, None) ) |s s' e m. (s, m, s') \<in> kernel_call e } \<union>
  (* User to user transition, no kernel entry *)
     { ( (s, UserMode, None),
         (s', UserMode, None) ) |s s'. (s, None, s') \<in> do_user_op} \<union>
  (* User to kernel transition, potentially includes Interrupt from user mode *)
     { ( (s, UserMode, None), 
         (s', KernelMode, Some e) ) |s s' e. (s, Some e, s') \<in> do_user_op} \<union>
  (* User to kernel transition, Interrupt from user mode *)
     { ( (s, UserMode, None), 
         (s', KernelMode, Some Interrupt) ) |s s'. (s, True, s') \<in> get_active_irq} \<union>
  (* Idling in idle mode *)
     { ( (s, IdleMode, None),
         (s', IdleMode, None) ) |s s'.  (s, False, s') \<in> get_active_irq} \<union>
  (* Interrupt while in idle mode *)
     { ( (s, IdleMode, None),
         (s', KernelMode, Some Interrupt) ) |s s'.  (s, True, s') \<in> get_active_irq}"

text {*
  After kernel initialisation, the machine is in UserMode, running the initial thread.
*} 
definition
  Init_A :: "'a::state_ext state global_state set"
where
  "Init_A \<equiv> {((empty_context, init_A_st), UserMode, None)}"

text {*
  The content of user memory is stored in the machine state.
  The definition below constructs a map
  from all kernel addresses pointing inside a user frame
  to the respective memory content.

  NOTE: There is an offset from kernel addresses to physical memory addresses.
*}
definition
  "user_mem s \<equiv> \<lambda>p.
  if in_user_frame p s
  then Some (underlying_memory (machine_state s) p)
  else None"

definition
  "user_memory_update um \<equiv> modify (\<lambda>ms.
   ms\<lparr>underlying_memory := (\<lambda>a. case um a of Some x \<Rightarrow> x
                                 | None \<Rightarrow> underlying_memory ms a)\<rparr>)"

subsection {* Constructing a virtual-memory view *}

text {*
  Function @{text get_pd_of_thread} takes three parameters:
  the kernel heap, the architecture-specific state, and
  a thread identifier.
  It returns the identifier of the corresponding page directory.
  Note that this function is total.
  If the traversal stops before a page directory can be found
  (e.g. because the VTable entry is not set or a reference has been invalid),
  the function returns the global kernel mapping.

  Looking up the page directory for a thread reference involves the following
  steps:

    At first, we check that the reference actually points to a TCB object in
  the kernel heap.
  If so, we check whether the vtable entry of the TCB contains a capability
  to a page directory with valid mapping data.
  Note that the mapping data might become stale.
  Hence, we have to follow the mapping data through the ASID table.
*}
definition
  get_pd_of_thread :: "kheap \<Rightarrow> arch_state \<Rightarrow> obj_ref \<Rightarrow> obj_ref"
where
  get_pd_of_thread_def:
  "get_pd_of_thread khp astate tcb_ref \<equiv>
   case khp tcb_ref of Some (TCB tcb) \<Rightarrow>
     (case tcb_vtable tcb of
        cap.ArchObjectCap (ARM_Structs_A.PageDirectoryCap pd_ref (Some asid))
          \<Rightarrow> (case arm_asid_table astate (asid_high_bits_of asid) of
                None \<Rightarrow> arm_global_pd astate
              | Some p \<Rightarrow> (case khp p of None \<Rightarrow> arm_global_pd astate
                           | Some ko \<Rightarrow>
                               if (VSRef (asid && mask asid_low_bits)
                                         (Some AASIDPool), pd_ref)
                                  \<in> vs_refs ko
                                 then pd_ref
                               else arm_global_pd astate))
      | _ \<Rightarrow>  arm_global_pd astate)
   | _ \<Rightarrow>  arm_global_pd astate"


lemma VSRef_AASIDPool_in_vs_refs:
  "(VSRef (asid && mask asid_low_bits) (Some AASIDPool), r) \<in> vs_refs ko =
   (\<exists>apool. ko = ArchObj (arch_kernel_obj.ASIDPool apool) \<and>
            apool (ucast (asid && mask asid_low_bits)) = Some r)"
  apply (simp add: vs_refs_def)
  apply (case_tac ko, simp_all)
  apply (case_tac arch_kernel_obj, simp_all add: image_def graph_of_def)
  apply clarsimp
  apply (rule iffI)
   apply clarsimp
   apply (subst ucast_up_ucast_id, simp add: is_up, assumption)
  apply (intro exI conjI, assumption)
  apply (rule sym, rule ucast_ucast_len)
  apply (cut_tac and_mask_less'[of asid_low_bits asid])
   apply (simp_all add: asid_low_bits_def)
  done

lemma get_pd_of_thread_def2:
  "get_pd_of_thread khp astate tcb_ref \<equiv>
   case khp tcb_ref of Some (TCB tcb) \<Rightarrow>
     (case tcb_vtable tcb of
        cap.ArchObjectCap (ARM_Structs_A.PageDirectoryCap pd_ref (Some asid))
          \<Rightarrow> if (\<exists>p apool.
                   arm_asid_table astate (asid_high_bits_of asid) = Some p \<and>
                   khp p = Some (ArchObj (arch_kernel_obj.ASIDPool apool)) \<and>
                   apool (ucast (asid && mask asid_low_bits)) = Some pd_ref)
               then pd_ref
             else arm_global_pd astate
      | _ \<Rightarrow>  arm_global_pd astate)
   | _ \<Rightarrow>  arm_global_pd astate"
  apply (rule eq_reflection)
  apply (clarsimp simp: get_pd_of_thread_def
                 split: Structures_A.kernel_object.splits option.splits)
  apply (rename_tac tcb)
  apply (case_tac "tcb_vtable tcb",
         simp_all split: arch_cap.splits Structures_A.kernel_object.splits
                         arch_kernel_obj.splits option.splits)
  apply (auto simp: VSRef_AASIDPool_in_vs_refs)
  done

lemma get_pd_of_thread_vs_lookup:
  "get_pd_of_thread (kheap s) (arch_state s) tcb_ref =
   (case kheap s tcb_ref of
      Some (TCB tcb) \<Rightarrow>
        (case tcb_vtable tcb of
           cap.ArchObjectCap (ARM_Structs_A.PageDirectoryCap r (Some asid)) \<Rightarrow>
             if (the (vs_cap_ref (tcb_vtable tcb)) \<rhd> r) s then r
             else arm_global_pd (arch_state s)
         | _ \<Rightarrow> arm_global_pd (arch_state s))
    | _ \<Rightarrow> arm_global_pd (arch_state s))"
  apply (clarsimp simp: get_pd_of_thread_def Let_def vs_cap_ref_def
           split: option.splits Structures_A.kernel_object.splits
                  cap.splits arch_cap.splits)
  apply (rename_tac tcb p a pd_ref)
  apply (intro conjI impI allI)

     apply clarsimp
     apply (erule vs_lookupE)
     apply (clarsimp simp: vs_asid_refs_def split_def image_def graph_of_def)
     apply (erule rtranclE, simp+)
     apply (clarsimp dest!: vs_lookup1D)
     apply (case_tac ko, simp_all add: vs_refs_def graph_of_def
                                split: arch_kernel_obj.splits)[1]
      prefer 2
      apply clarsimp+
     apply (erule rtranclE)
      apply (clarsimp simp: up_ucast_inj_eq)
     apply (clarsimp dest!: vs_lookup1D)
     apply (case_tac ko, simp_all add: vs_refs_def graph_of_def
                                split: arch_kernel_obj.splits)[1]
      prefer 2
      apply clarsimp+

    apply (erule vs_lookupE)
    apply (clarsimp simp: vs_asid_refs_def split_def image_def graph_of_def)
    apply (erule rtranclE, simp+)
    apply (clarsimp dest!: vs_lookup1D)
    apply (case_tac ko, simp_all add: vs_refs_def graph_of_def
                               split: arch_kernel_obj.splits)[1]
     prefer 2
     apply clarsimp+
    apply (erule rtranclE)
     apply (clarsimp simp: up_ucast_inj_eq obj_at_def)
    apply (clarsimp dest!: vs_lookup1D)
    apply (case_tac ko, simp_all add: vs_refs_def graph_of_def
                               split: arch_kernel_obj.splits)[1]
     prefer 2
     apply clarsimp+

   apply (erule swap)
   apply (erule vs_lookupE)
   apply (clarsimp simp: vs_asid_refs_def split_def image_def graph_of_def)
   apply (erule rtranclE, simp+)
   apply (erule rtranclE)
    apply (clarsimp dest!: vs_lookup1D simp: up_ucast_inj_eq obj_at_def)
   apply (clarsimp dest!: vs_lookup1D simp: up_ucast_inj_eq obj_at_def)
   apply (case_tac ko, simp_all add: vs_refs_def graph_of_def
                             split: arch_kernel_obj.splits)[1]
    prefer 2
    apply clarsimp+
   apply (rename_tac ko apool a r)
   apply (case_tac ko, simp_all add: vs_refs_def graph_of_def
                              split: arch_kernel_obj.splits)[1]
    prefer 2
    apply clarsimp+

  apply (erule swap)
  apply (rule vs_lookupI)
   apply (fastforce simp: vs_asid_refs_def image_def graph_of_def)
  apply (rule rtrancl.rtrancl_into_rtrancl)
   apply (rule rtrancl.rtrancl_refl)
  apply (erule vs_lookup1I[rotated], simp_all add: obj_at_def)[1]
  done

(* NOTE: This statement would clearly be nicer for a partial function
         but later on, we really want the function to be total. *)
lemma get_pd_of_thread_eq:
  "pd_ref \<noteq> arm_global_pd (arch_state s) \<Longrightarrow>
   get_pd_of_thread (kheap s) (arch_state s) tcb_ref = pd_ref \<longleftrightarrow>
   (\<exists>tcb. kheap s tcb_ref = Some (TCB tcb) \<and>
          (\<exists>asid. tcb_vtable tcb =
                  cap.ArchObjectCap (ARM_Structs_A.PageDirectoryCap
                                       pd_ref (Some asid)) \<and>
                  (the (vs_cap_ref (tcb_vtable tcb)) \<rhd> pd_ref) s))"
  by (auto simp: get_pd_of_thread_vs_lookup vs_cap_ref_def
          split: option.splits Structures_A.kernel_object.splits
                 cap.splits arch_cap.splits)

text {* The following function is used to extract the
  architecture-specific objects from the kernel heap  *}
definition
  "get_arch_obj ==
   case_option None (%x. case x of ArchObj a \<Rightarrow> Some a | _ \<Rightarrow> None)"

text {* Non-monad versions of @{term get_pte} and @{term get_pde}.
  The parameters are:
  \begin{description}
  \item[@{term ahp}] a heap of architecture-specific objects,
  \item[@{term pt_ref}] a page-table reference,
  \item[@{term pd_ref}] a page-directory reference, and
  \item[@{term vptr}] a virtual address.
  \end{description}
*}
definition
  "get_pt_entry ahp pt_ref vptr \<equiv>
   case ahp pt_ref of
     Some (ARM_Structs_A.PageTable pt) \<Rightarrow>
       Some (pt (ucast ((vptr >> 12) && mask 8)))
   | _ \<Rightarrow> None"
definition
  "get_pd_entry ahp pd_ref vptr \<equiv>
   case ahp pd_ref of
     Some (PageDirectory pd) \<Rightarrow> Some (pd (ucast (vptr >> 20)))
   | _ \<Rightarrow> None"

lemma get_pd_entry_None_iff_get_pde_fail:
  "is_aligned pd_ref pd_bits \<Longrightarrow>
   get_pd_entry (\<lambda>obj. get_arch_obj (kheap s obj)) pd_ref vptr = None \<longleftrightarrow>
   get_pde (pd_ref + (vptr >> 20 << 2)) s = ({}, True)"
apply (subgoal_tac "(vptr >> 20 << 2) && ~~ mask pd_bits = 0")
 apply (clarsimp simp add: get_pd_entry_def get_arch_obj_def
            split: option.splits Structures_A.kernel_object.splits
                   arch_kernel_obj.splits)
 apply (clarsimp simp add: get_pde_def get_pd_def bind_def return_def assert_def
  get_object_def simpler_gets_def fail_def split_def mask_out_sub_mask mask_eqs)
 apply (subgoal_tac "pd_ref + (vptr >> 20 << 2) -
                    (pd_ref + (vptr >> 20 << 2) && mask pd_bits) = pd_ref")
  apply (simp (no_asm_simp) add: fail_def return_def)
  apply clarsimp
 apply (simp add: mask_add_aligned pd_bits_def pageBits_def)
apply (simp add: pd_bits_def pageBits_def)
apply (simp add: and_not_mask)
apply (simp add: shiftl_shiftr3 word_size shiftr_shiftr)
apply (subgoal_tac "vptr >> 32 = 0", simp)
apply (cut_tac shiftr_less_t2n'[of vptr 32 0], simp)
 apply (simp add: mask_eq_iff)
 apply (cut_tac lt2p_lem[of 32 vptr])
  apply (cut_tac word_bits_len_of, simp+)
done

lemma get_pd_entry_Some_eq_get_pde:
  "is_aligned pd_ref pd_bits \<Longrightarrow>
   get_pd_entry (\<lambda>obj. get_arch_obj (kheap s obj)) pd_ref vptr = Some x \<longleftrightarrow>
   get_pde (pd_ref + (vptr >> 20 << 2)) s = ({(x,s)}, False)"
apply (subgoal_tac "(vptr >> 20 << 2) && ~~ mask pd_bits = 0")
 apply (clarsimp simp add: get_pd_entry_def get_arch_obj_def
            split: option.splits Structures_A.kernel_object.splits
                   arch_kernel_obj.splits)
 apply (clarsimp simp add: get_pde_def get_pd_def bind_def return_def assert_def
            get_object_def simpler_gets_def fail_def split_def mask_out_sub_mask
            mask_eqs)
 apply (subgoal_tac "pd_ref + (vptr >> 20 << 2) -
                    (pd_ref + (vptr >> 20 << 2) && mask pd_bits) = pd_ref")
  apply (simp (no_asm_simp) add: fail_def return_def)
  apply (clarsimp simp add: mask_add_aligned pd_bits_def pageBits_def)
  apply (cut_tac shiftl_shiftr_id[of 2 "vptr >> 20"])
    apply (simp add: word_bits_def)+
  apply (cut_tac shiftr_less_t2n'[of vptr 20 30])
    apply (simp add: word_bits_def)
   apply (simp add: mask_eq_iff)
   apply (cut_tac lt2p_lem[of 50 vptr])
    apply (cut_tac word_bits_len_of, simp+)
 apply (simp add: mask_add_aligned pd_bits_def pageBits_def)
apply (simp add: pd_bits_def pageBits_def)
apply (simp add: and_not_mask)
apply (simp add: shiftl_shiftr3 word_size shiftr_shiftr)
apply (subgoal_tac "vptr >> 32 = 0", simp)
apply (cut_tac shiftr_less_t2n'[of vptr 32 0], simp)
 apply (simp add: mask_eq_iff)
 apply (cut_tac lt2p_lem[of 32 vptr])
  apply (cut_tac word_bits_len_of, simp+)
done

lemma get_pt_entry_None_iff_get_pte_fail:
  "is_aligned pt_ref pt_bits \<Longrightarrow>
   get_pt_entry (\<lambda>obj. get_arch_obj (kheap s obj)) pt_ref vptr = None \<longleftrightarrow>
   get_pte (pt_ref + ((vptr >> 12) && 0xFF << 2)) s = ({}, True)"
apply (clarsimp simp add: get_pt_entry_def get_arch_obj_def
             split: option.splits Structures_A.kernel_object.splits
                    arch_kernel_obj.splits)
apply (clarsimp simp add: get_pte_def get_pt_def bind_def return_def assert_def
  get_object_def simpler_gets_def fail_def split_def mask_out_sub_mask mask_eqs)
apply (subgoal_tac "pt_ref + ((vptr >> 12) && 0xFF << 2) -
                    (pt_ref + ((vptr >> 12) && 0xFF << 2) && mask pt_bits) =
                    pt_ref")
 apply (simp (no_asm_simp) add: fail_def return_def)
 apply clarsimp
apply (simp add: mask_add_aligned pt_bits_def pageBits_def)
apply (cut_tac and_mask_shiftl_comm[of 8 2 "vptr >> 12"])
 apply (simp_all add: word_size mask_def AND_twice)
done

lemma get_pt_entry_Some_eq_get_pte:
  "is_aligned pt_ref pt_bits \<Longrightarrow>
   get_pt_entry (\<lambda>obj. get_arch_obj (kheap s obj)) pt_ref vptr = Some x \<longleftrightarrow>
   get_pte (pt_ref + ((vptr >> 12) && mask 8 << 2)) s = ({(x,s)}, False)"
  apply (clarsimp simp add: get_pt_entry_def get_arch_obj_def
             split: option.splits Structures_A.kernel_object.splits
                    arch_kernel_obj.splits)
  apply (clarsimp simp add: get_pte_def get_pt_def bind_def return_def
            assert_def get_object_def simpler_gets_def fail_def split_def
            mask_out_sub_mask mask_eqs)
  apply (subgoal_tac "pt_ref + ((vptr >> 12) && mask 8 << 2) -
                      (pt_ref + ((vptr >> 12) && mask 8 << 2) && mask pt_bits) =
                      pt_ref")
   apply (simp (no_asm_simp) add: fail_def return_def)
   apply (clarsimp simp add: mask_add_aligned pt_bits_def pageBits_def
              word_size
              and_mask_shiftr_comm and_mask_shiftl_comm shiftr_shiftr AND_twice)
   apply (cut_tac shiftl_shiftr_id[of 2 "(vptr >> 12)"])
     apply (simp add: word_bits_def)+
   apply (cut_tac shiftr_less_t2n'[of vptr 12 30])
     apply (simp add: word_bits_def)
    apply (simp add: mask_eq_iff)
    apply (cut_tac lt2p_lem[of 32 vptr])
     apply (cut_tac word_bits_len_of, simp+)
  apply (simp add: mask_add_aligned pt_bits_def pageBits_def
                   word_size and_mask_shiftl_comm  AND_twice)
done

definition
  "get_pt_info ahp pt_ref vptr \<equiv>
   case get_pt_entry ahp pt_ref vptr of
     Some (ARM_Structs_A.SmallPagePTE base attrs rights) \<Rightarrow> Some (base, 12, attrs, rights)
   | Some (ARM_Structs_A.LargePagePTE base attrs rights) \<Rightarrow> Some (base, 16, attrs, rights)
   | _ \<Rightarrow> None"

text {*
  @{text get_page_info} takes the architecture-specific part of the kernel heap,
  a reference to the page directory, and a virtual memory address.
  It returns a tuple containing
  (a) the physical address, where the associated page table starts,
  (b) the page table's size in bits, and
  (c) the page attributes (cachable, XNever, etc)
  (d) the access rights (a subset of @{term "{AllowRead, AllowWrite}"}).
*}
definition
  get_page_info :: "(obj_ref \<rightharpoonup> arch_kernel_obj) \<Rightarrow> obj_ref \<Rightarrow>
                    word32 \<rightharpoonup> (word32 \<times> nat \<times> vm_attributes \<times> vm_rights)"
where
  get_page_info_def:
  "get_page_info ahp pd_ref vptr \<equiv>
   case get_pd_entry ahp pd_ref vptr of
     Some (ARM_Structs_A.PageTablePDE p _ _) \<Rightarrow>
       get_pt_info ahp (Platform.ptrFromPAddr p) vptr
   | Some (ARM_Structs_A.SectionPDE base attrs _ rights) \<Rightarrow> Some (base, 20, attrs, rights)
   | Some (ARM_Structs_A.SuperSectionPDE base attrs rights) \<Rightarrow> Some (base,24, attrs, rights)
   | _ \<Rightarrow> None"


(* FIXME: Lemma can be found in Untyped_R;
   proof mostly copied from ArchAcc_R.pd_shifting *)
lemma pd_shifting':
   "is_aligned pd pd_bits \<Longrightarrow>
    (pd + (vptr >> 20 << 2) && ~~ mask pd_bits) = (pd::word32)"
  apply (simp add: pd_bits_def pageBits_def)
  apply (rule word_eqI)
  apply (subst word_plus_and_or_coroll)
   apply (rule word_eqI)
   apply (clarsimp simp: word_size nth_shiftr nth_shiftl is_aligned_nth)
   apply (erule_tac x=na in allE)
   apply (simp add: linorder_not_less)
   apply (drule test_bit_size)+
   apply (simp add: word_size)
  apply (clarsimp simp: word_size nth_shiftr nth_shiftl is_aligned_nth
                        word_ops_nth_size pd_bits_def linorder_not_less)
  apply (rule iffI)
   apply clarsimp
   apply (drule test_bit_size)+
   apply (simp add: word_size)
  apply clarsimp
  apply (erule_tac x=n in allE)
  apply simp
  done

lemma lookup_pt_slot_fail:
  "is_aligned pd pd_bits \<Longrightarrow>
   lookup_pt_slot pd vptr s = ({},True) \<longleftrightarrow>
   (\<forall>pdo. kheap s pd \<noteq> Some (ArchObj (PageDirectory pdo)))"
apply (frule pd_shifting'[of _ vptr])
by (auto simp add: lookup_pt_slot_def lookup_pd_slot_def liftE_def bindE_def
        returnOk_def lift_def bind_def split_def throwError_def return_def
        get_pde_def get_pd_def Union_eq get_object_def simpler_gets_def
        assert_def fail_def mask_eqs
      split: sum.splits split_if_asm Structures_A.kernel_object.splits
             arch_kernel_obj.splits ARM_Structs_A.pde.splits)

(* FIXME: Lemma can be found in ArchAcc_R *)
lemma shiftr_shiftl_mask_pd_bits:
  "(((vptr :: word32) >> 20) << 2) && mask pd_bits = (vptr >> 20) << 2"
  apply (rule iffD2 [OF mask_eq_iff_w2p])
   apply (simp add: pd_bits_def pageBits_def word_size)
  apply (rule shiftl_less_t2n)
   apply (simp_all add: pd_bits_def word_bits_def pageBits_def word_size)
  apply (cut_tac shiftr_less_t2n'[of vptr 20 12])
    apply simp
   apply (simp add: mask_eq_iff)
   apply (cut_tac lt2p_lem[of 32 vptr], simp)
   apply (cut_tac word_bits_len_of, simp)
  apply simp
  done

lemma lookup_pt_slot_no_fail:
  "is_aligned pd pd_bits \<Longrightarrow>
   kheap s pd = Some (ArchObj (PageDirectory pdo)) \<Longrightarrow>
   lookup_pt_slot pd vptr s =
   (case pdo (ucast (vptr >> 20)) of
      ARM_Structs_A.InvalidPDE \<Rightarrow>
        ({(Inl (ExceptionTypes_A.MissingCapability 20),s)},False)
    | ARM_Structs_A.PageTablePDE p _ _ \<Rightarrow>
        ({(Inr (Platform.ptrFromPAddr p + ((vptr >> 12) && 0xFF << 2)),s)},
         False)
    | ARM_Structs_A.SectionPDE _ _ _ _ \<Rightarrow>
        ({(Inl (ExceptionTypes_A.MissingCapability 20),s)},False)
    | ARM_Structs_A.SuperSectionPDE _ _ _ \<Rightarrow>
        ({(Inl (ExceptionTypes_A.MissingCapability 20),s)},False)  )"
apply (frule pd_shifting'[of _ vptr])
apply (cut_tac shiftr_shiftl_mask_pd_bits[of vptr])
apply (subgoal_tac "vptr >> 20 << 2 >> 2 = vptr >> 20")
defer
 apply (rule shiftl_shiftr_id)
  apply (simp_all add: word_bits_def)
  apply (cut_tac shiftr_less_t2n'[of vptr 20 30])
    apply (simp add: word_bits_def)
   apply (simp add: mask_eq_iff)
   apply (cut_tac lt2p_lem[of 32 vptr])
    apply (cut_tac word_bits_len_of, simp_all)
by (clarsimp simp add: lookup_pt_slot_def lookup_pd_slot_def liftE_def bindE_def
        returnOk_def lift_def bind_def split_def throwError_def return_def
        get_pde_def get_pd_def Union_eq get_object_def simpler_gets_def
        assert_def fail_def mask_add_aligned
      split: sum.splits split_if_asm kernel_object.splits arch_kernel_obj.splits
             ARM_Structs_A.pde.splits)

lemma get_page_info_pte:
  "is_aligned pd_ref pd_bits \<Longrightarrow>
   lookup_pt_slot pd_ref vptr s = ({(Inr x,s)},False) \<Longrightarrow>
   is_aligned (x - ((vptr >> 12) && 0xFF << 2)) pt_bits \<Longrightarrow>
   get_pte x s = ({(pte,s)},False) \<Longrightarrow>
   get_page_info (\<lambda>obj. get_arch_obj (kheap s obj)) pd_ref vptr =
   (case pte of
     ARM_Structs_A.SmallPagePTE base attrs rights \<Rightarrow> Some (base, 12, attrs, rights)
   | ARM_Structs_A.LargePagePTE base attrs rights \<Rightarrow> Some (base, 16, attrs, rights)
   | _ \<Rightarrow> None)"
apply (clarsimp simp add: get_page_info_def get_pd_entry_def
                split: option.splits)
apply (intro conjI impI allI)
  apply (frule lookup_pt_slot_fail[of _ vptr s],
         clarsimp simp add: get_arch_obj_def)
 apply (frule lookup_pt_slot_fail[of _ vptr s],
        clarsimp simp add: get_arch_obj_def)
apply (frule lookup_pt_slot_fail[of _ vptr s],
       clarsimp simp add: get_arch_obj_def)
apply (frule (1) lookup_pt_slot_no_fail[where vptr=vptr])
apply (clarsimp split: ARM_Structs_A.pde.splits option.splits)
apply (clarsimp simp add: get_pt_info_def split: option.splits)
apply (intro conjI impI)
 apply (drule get_pt_entry_None_iff_get_pte_fail[where s=s and vptr=vptr])
 apply (simp add: pt_bits_def pageBits_def mask_def)
apply clarsimp
apply (drule_tac x=x2 in get_pt_entry_Some_eq_get_pte[where s=s and vptr=vptr])
apply (simp add: pt_bits_def pageBits_def mask_def)
done

lemma get_page_info_section:
  "is_aligned pd_ref pd_bits \<Longrightarrow>
   get_pde (lookup_pd_slot pd_ref vptr) s =
     ({(ARM_Structs_A.SectionPDE base attrs X rights, s)},False) \<Longrightarrow>
   get_page_info (\<lambda>obj. get_arch_obj (kheap s obj)) pd_ref vptr =
     Some (base, 20, attrs, rights)"
apply (simp add: lookup_pd_slot_def get_page_info_def split: option.splits)
apply (intro conjI impI allI)
 apply (drule get_pd_entry_None_iff_get_pde_fail[where s=s and vptr=vptr])
 apply (simp split: option.splits)
apply (drule_tac x=x2 in get_pd_entry_Some_eq_get_pde[where s=s and vptr=vptr])
apply clarsimp
done

lemma get_page_info_super_section:
  "is_aligned pd_ref pd_bits \<Longrightarrow>
   get_pde (lookup_pd_slot pd_ref vptr) s =
     ({(ARM_Structs_A.SuperSectionPDE base attrs rights,s)},False) \<Longrightarrow>
   get_page_info (\<lambda>obj. get_arch_obj (kheap s obj)) pd_ref vptr =
     Some (base, 24, attrs, rights)"
apply (simp add: lookup_pd_slot_def get_page_info_def split: option.splits)
apply (intro conjI impI allI)
 apply (drule get_pd_entry_None_iff_get_pde_fail[where s=s and vptr=vptr])
 apply (simp split: option.splits)
apply (drule_tac x=x2 in get_pd_entry_Some_eq_get_pde[where s=s and vptr=vptr])
apply clarsimp
done

text {*
  Both functions, @{text ptable_lift} and @{text vm_rights},
  take a kernel state and a virtual address.
  The former returns the physical address, the latter the associated rights.
*}
definition
  ptable_lift :: "obj_ref \<Rightarrow> 'z state \<Rightarrow> word32 \<rightharpoonup> word32" where
  "ptable_lift tcb s \<equiv> \<lambda>addr.
   case_option None (\<lambda>(base, bits, rights). Some (base + (addr && mask bits)))
     (get_page_info (\<lambda>obj. get_arch_obj (kheap s obj))
        (get_pd_of_thread (kheap s) (arch_state s) tcb) addr)"
definition
  ptable_rights :: "obj_ref \<Rightarrow> 'z state \<Rightarrow> word32 \<Rightarrow> vm_rights" where
 "ptable_rights tcb s \<equiv> \<lambda>addr.
  case_option {} (snd o snd o snd)
     (get_page_info (\<lambda>obj. get_arch_obj (kheap s obj))
        (get_pd_of_thread (kheap s) (arch_state s) tcb) addr)"

text {*
  The below definition gives the kernel monad computation that checks for
  active interrupts, given the present user_context. This is necessarily
  a computation in the kernel monad because checking interrupts will update
  the interrupt state.
*}
definition
  check_active_irq :: "(bool,'z :: state_ext) s_monad"
  where
  "check_active_irq \<equiv> do
      irq \<leftarrow> do_machine_op getActiveIRQ;
      return (irq \<noteq> None)
  od"

definition 
  check_active_irq_A :: "(('z :: state_ext) state uc_state \<times> bool \<times> ('z :: state_ext) state uc_state) set"
  where
  "check_active_irq_A \<equiv> {((tc, s), (irq, (tc, s'))). (irq , s') \<in> fst (check_active_irq s)}"

text {*
  The definition below lifts a user transition into the kernel monad.
  Note that the user memory (as seen by the kernel) is
  converted to true physical addresses and
  restricted to those addresses, the current thread is permitted to access.
  Furthermore, user memory is updated if and only if
  the current thread has write permission.

  NOTE: An unpermitted write access would generate a page fault on the machine.
    The global transitions, however, model page faults non-deterministically.
*}
definition
  do_user_op :: "user_transition \<Rightarrow> user_context \<Rightarrow> (event option \<times> user_context,'z::state_ext) s_monad"
  where
  "do_user_op uop tc \<equiv> 
   do t \<leftarrow> gets cur_thread;
      conv \<leftarrow> gets (ptable_lift t);
      rights \<leftarrow> gets (ptable_rights t);
      um \<leftarrow> gets (\<lambda>s. user_mem s \<circ> ptrFromPAddr);
      (e,tc',um') \<leftarrow> select (fst
                     (uop t (restrict_map conv {pa. rights pa \<noteq> {}}) rights
                       (tc, restrict_map um {pa. \<exists>va. conv va = Some pa \<and> AllowRead \<in> rights va})));
      do_machine_op (user_memory_update
                       (restrict_map um' {pa. \<exists>va. conv va = Some pa \<and> AllowWrite \<in> rights va}
                      \<circ> Platform.addrFromPPtr));
      return (e, tc')
   od" 


definition
  monad_to_transition :: 
 "(user_context \<Rightarrow> ('s, event option \<times> user_context) nondet_monad) \<Rightarrow> 
  ('s uc_state \<times> event option \<times> 's uc_state) set"
where
  "monad_to_transition m \<equiv> {((tc,s),(e,tc',s')). ((e,tc'),s') \<in> fst (m tc s)}"

definition
  do_user_op_A :: "user_transition \<Rightarrow>
                   ('z state uc_state \<times> event option \<times> ('z::state_ext state) uc_state) set"
  where
  "do_user_op_A uop \<equiv> monad_to_transition (do_user_op uop)"


text {*
  Kernel calls are described completely by the abstract and concrete spec.
  We model kernel entry by allowing an arbitrary user (register) context.
  The mode after a kernel call is either user or idle
  (see also thm in Refine.thy).
*}
definition
  kernel_entry :: "event \<Rightarrow> user_context \<Rightarrow> (user_context,'z::state_ext_sched) s_monad"
  where
  "kernel_entry e tc \<equiv> do
    t \<leftarrow> gets cur_thread;
    thread_set (\<lambda>tcb. tcb \<lparr> tcb_context := tc \<rparr>) t;
    call_kernel e;
    t' \<leftarrow> gets cur_thread;
    thread_get tcb_context t'
  od"


definition
  kernel_call_A
    :: "event \<Rightarrow> ((user_context \<times> ('a::state_ext_sched state)) \<times> mode \<times> (user_context \<times> 'a state)) set"
  where
  "kernel_call_A e \<equiv>
      {(s, m, s'). s' \<in> fst (split (kernel_entry e) s) \<and>
                   m = (if ct_running (snd s') then UserMode else IdleMode)}"

text {* Putting together the final abstract datatype *}

(* NOTE: the extensible abstract specification leaves the type of the extension
     unspecified; later on, we will instantiate this type with det_ext from the
     deterministic abstract specification as well as with unit.  The former is
     used for refinement between the deterministic specification and C.  The
     latter is used for refinement between the non-deterministic specification
     and C. *)
definition
  ADT_A :: "user_transition \<Rightarrow> (('a::state_ext_sched state) global_state, 'a observable, unit) data_type"
where
 "ADT_A uop \<equiv> 
  \<lparr> Init = \<lambda>s. Init_A, Fin = id,
    Step = (\<lambda>u. global_automaton check_active_irq_A (do_user_op_A uop) kernel_call_A) \<rparr>"


text {*
  Lifting a state relation on kernel states to global states.
*}
definition
  "lift_state_relation sr \<equiv>
   { (((tc,s),m,e), ((tc,s'),m,e))|s s' m e tc. (s,s') \<in> sr }"

lemma lift_state_relationD:
  "(((tc, s), m, e), ((tc', s'), m', e')) \<in> lift_state_relation R \<Longrightarrow>
  (s,s') \<in> R \<and> tc' = tc \<and> m' = m \<and> e' = e"
  by (simp add: lift_state_relation_def)

lemma lift_state_relationI:
  "(s,s') \<in> R \<Longrightarrow> (((tc, s), m, e), ((tc, s'), m, e)) \<in> lift_state_relation R"
  by (fastforce simp: lift_state_relation_def)

lemma in_lift_state_relation_eq:
  "(((tc, s), m, e), (tc', s'), m', e') \<in> lift_state_relation R \<longleftrightarrow>
   (s, s') \<in> R \<and> tc' = tc \<and> m' = m \<and> e' = e"
  by (auto simp add: lift_state_relation_def)

end
