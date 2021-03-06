(*
 * Copyright 2014, General Dynamics C4 Systems
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(GD_GPL)
 *)

theory ArchStructures_H
imports
  "Lib.Lib"
  "../Types_H"
  Hardware_H
begin
context Arch begin global_naming ARM_HYP_H

#INCLUDE_SETTINGS keep_constructor=asidpool
#INCLUDE_SETTINGS keep_constructor=arch_tcb

#INCLUDE_HASKELL SEL4/Object/Structures/ARM.lhs CONTEXT ARM_HYP_H decls_only
#INCLUDE_HASKELL SEL4/Object/Structures/ARM.lhs CONTEXT ARM_HYP_H instanceproofs
#INCLUDE_HASKELL SEL4/Object/Structures/ARM.lhs CONTEXT ARM_HYP_H bodies_only NOT makeVCPUObject

(* we define makeVCPUObject_def manually because we want a total function vgicLR *)
defs makeVCPUObject_def:
"makeVCPUObject \<equiv>
    VCPUObj_ \<lparr>
          vcpuTCBPtr= Nothing
        , vcpuVGIC= VGICInterface_ \<lparr>
                          vgicHCR= vgicHCREN
                        , vgicVMCR= 0
                        , vgicAPR= 0
                        , vgicLR= (\<lambda>_. 0)
                        \<rparr>
        , vcpuRegs= funArray (const 0)  aLU  [(VCPURegSCTLR, sctlrDefault)
                                             ,(VCPURegACTLR, actlrDefault)]
        \<rparr>"

datatype arch_kernel_object_type =
    PDET
  | PTET
  | VCPUT
  | ASIDPoolT

primrec
  archTypeOf :: "arch_kernel_object \<Rightarrow> arch_kernel_object_type"
where
  "archTypeOf (KOPDE e) = PDET"
| "archTypeOf (KOPTE e) = PTET"
| "archTypeOf (KOVCPU e) = VCPUT"
| "archTypeOf (KOASIDPool e) = ASIDPoolT"

end

context begin interpretation Arch .

requalify_types
  vcpu

end
end
