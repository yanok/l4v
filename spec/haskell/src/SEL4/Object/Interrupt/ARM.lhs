%
% Copyright 2014, General Dynamics C4 Systems
%
% This software may be distributed and modified according to the terms of
% the GNU General Public License version 2. Note that NO WARRANTY is provided.
% See "LICENSE_GPLv2.txt" for details.
%
% @TAG(GD_GPL)
%

This module defines the machine-specific interrupt handling routines.

\begin{impdetails}

> {-# LANGUAGE CPP #-}

\end{impdetails}

> module SEL4.Object.Interrupt.ARM where

\begin{impdetails}

> import Prelude hiding (Word)
> import SEL4.Machine
> import SEL4.Model
> import SEL4.Object.Structures
> import SEL4.API.Failures
> import SEL4.API.Invocation.ARM as ArchInv
> import {-# SOURCE #-} SEL4.Object.Interrupt (setIRQState)
#ifdef CONFIG_ARM_HYPERVISOR_SUPPORT
> import SEL4.Object.VCPU.TARGET (vgicMaintenance)
> import SEL4.Machine.Hardware.ARM.PLATFORM (irqVGICMaintenance, irqSMMU)
#endif

\end{impdetails}

> decodeIRQControlInvocation :: Word -> [Word] -> PPtr CTE -> [Capability] ->
>     KernelF SyscallError ArchInv.IRQControlInvocation
> decodeIRQControlInvocation _ _ _ _ = throw IllegalOperation

> performIRQControl :: ArchInv.IRQControlInvocation -> KernelP ()
> performIRQControl _ = fail "performIRQControl: not defined"

> checkIRQ :: Word -> KernelF SyscallError ()
> checkIRQ irq = rangeCheck irq (fromEnum minIRQ) (fromEnum maxIRQ)

> handleReservedIRQ :: IRQ -> Kernel ()
> handleReservedIRQ irq = do
#ifdef CONFIG_ARM_HYPERVISOR_SUPPORT
>     -- case irq of IRQ irqVGICMaintenance -> vgicMaintenance -- FIXME how to properly handle IRQ for haskell translator here?
>     when (fromEnum irq == fromEnum irqVGICMaintenance) vgicMaintenance
>     return ()
#else
>     return () -- handleReservedIRQ does nothing on ARM
#endif

> initInterruptController :: Kernel ()
> initInterruptController = do
#ifdef CONFIG_ARM_HYPERVISOR_SUPPORT
>     setIRQState IRQReserved $ IRQ irqVGICMaintenance
#endif
#ifdef CONFIG_SMMU
>     setIRQState IRQReserved $ IRQ irqSMMU
#endif
>     return ()

