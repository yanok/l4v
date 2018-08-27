%
% Copyright 2014, General Dynamics C4 Systems
%
% This software may be distributed and modified according to the terms of
% the GNU General Public License version 2. Note that NO WARRANTY is provided.
% See "LICENSE_GPLv2.txt" for details.
%
% @TAG(GD_GPL)
%

\begin{impdetails}

> {-# LANGUAGE CPP, GeneralizedNewtypeDeriving, FlexibleContexts #-}

\end{impdetails}

This module defines the ARM register set.

> module SEL4.Machine.RegisterSet.ARM where

\begin{impdetails}

> import Prelude hiding (Word)
> import qualified Data.Word
> import Data.Array
> import Data.Helpers
> import Control.Monad.State(State, gets, modify)

\end{impdetails}

> data Register =
>     R0 | R1 | R2 | R3 | R4 | R5 | R6 | R7 | R8 | R9 | SL | FP | IP | SP |
>     LR | LR_svc | FaultInstruction | CPSR | TLS_BASE | TPIDRURW
>     deriving (Eq, Enum, Bounded, Ord, Ix, Show)

> type Word = Data.Word.Word32

> capRegister = R0
> msgInfoRegister = R1
> msgRegisters = [R2 .. R5]
> badgeRegister = R0
> frameRegisters = FaultInstruction : SP : CPSR : [R0, R1] ++ [R8 .. IP]
> gpRegisters = [R2, R3, R4, R5, R6, R7, LR]
> exceptionMessage = [FaultInstruction, SP, CPSR]
> syscallMessage = [R0 .. R7] ++ [FaultInstruction, SP, LR, CPSR]
> tlsBaseRegister = TLS_BASE

#ifdef CONFIG_ARM_HYPERVISOR_SUPPORT
> elr_hyp = LR_svc

\subsection{VCPU-saved Registers}

> data VCPUReg =
>       VCPURegSCTLR
>     | VCPURegACTLR
>     | VCPURegTTBCR
>     | VCPURegTTBR0
>     | VCPURegTTBR1
>     | VCPURegDACR
>     | VCPURegDFSR
>     | VCPURegIFSR
>     | VCPURegADFSR
>     | VCPURegAIFSR
>     | VCPURegDFAR
>     | VCPURegIFAR
>     | VCPURegPRRR
>     | VCPURegNMRR
>     | VCPURegCIDR
>     | VCPURegTPIDRPRW
>     | VCPURegFPEXC
>     | VCPURegCNTVTVAL
>     | VCPURegCNTVCTL
>     | VCPURegLRsvc
>     | VCPURegSPsvc
>     | VCPURegLRabt
>     | VCPURegSPabt
>     | VCPURegLRund
>     | VCPURegSPund
>     | VCPURegLRirq
>     | VCPURegSPirq
>     | VCPURegLRfiq
>     | VCPURegSPfiq
>     | VCPURegR8fiq
>     | VCPURegR9fiq
>     | VCPURegR10fiq
>     | VCPURegR11fiq
>     | VCPURegR12fiq
>     | VCPURegSPSRsvc
>     | VCPURegSPSRabt
>     | VCPURegSPSRund
>     | VCPURegSPSRirq
>     | VCPURegSPSRfiq
>     deriving (Eq, Enum, Bounded, Ord, Ix, Show)

> vcpuRegNum :: Int
> vcpuRegNum = fromEnum (maxBound :: VCPUReg)

#endif

> initContext :: [(Register, Word)]
> initContext = [(CPSR,0x150)] -- User mode

\subsubsection{User-level Context}

The representation of the user-level context of a thread is an array of machine words, indexed by register name.

> newtype UserContext = UC { fromUC :: Array Register Word }
>         deriving Show

A new user-level context is a list of values for the machine's registers. Registers are generally initialised to 0, but there may be machine-specific initial values for certain registers.

> newContext :: UserContext
> newContext = UC $ (funArray $ const 0)//initContext

Functions are provided to get and set a single register.

> getRegister r = gets $ (!r) . fromUC

> setRegister r v = modify $ UC . (//[(r, v)]) . fromUC

