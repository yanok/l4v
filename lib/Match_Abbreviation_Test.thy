(*
 *
 * Copyright 2018, Data61, CSIRO
 *
 * This software may be distributed and modified according to the terms of
 * the BSD 2-Clause license. Note that NO WARRANTY is provided.
 * See "LICENSE_BSD2.txt" for details.
 *
 * @TAG(DATA61_BSD)
 *)
theory Match_Abbreviation_Test

imports
  Match_Abbreviation
  "Monad_WP/NonDetMonad"

begin

experiment
  fixes a :: "(int, unit) nondet_monad"
    and b :: "int \<Rightarrow> (int, int) nondet_monad"
    and c :: "(int, unit) nondet_monad"
begin

definition
  "test_foo z = do
    a; a;
    x \<leftarrow> b 2;
    x \<leftarrow> b z;
    a; a; a; a;
    x \<leftarrow> c;
    x \<leftarrow> a; a;
    return ()
  od"

match_abbreviation (input) foo_block
  in concl test_foo_def
  select "bind (b x) y" (for x y)
  and rewrite "bind c y" to "c" (for y)

definition
  "test_foo_bind = do
    a; a;
    x \<leftarrow> b 2;
    y \<leftarrow> b x;
    a; a; a; a;
    z \<leftarrow> b (x + y);
    fin \<leftarrow> b (z + x);
    x \<leftarrow> a; a;
    c;
    a; a;
    return fin
  od"

match_abbreviation (input) foo_block_capture
  in concl test_foo_bind_def[simplified K_bind_def]
  select "bind (b (x + y)) tail" (for x y tail)
  and rewrite "bind c y" to "c" (for y)
  and retype_consts bind

definition
  "foo_blockc x y = foo_block_capture x y"

reassoc_thm foo_block_capture_reassoc
  "bind (foo_block_capture x y) f" (for x y f)
  bind_assoc
lemmas foo_blockc_fold = foo_block_capture_reassoc[folded foo_blockc_def]

end

end
