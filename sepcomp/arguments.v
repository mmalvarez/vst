Require Import sepcomp.core_semantics.
Require Import sepcomp.StructuredInjections.
Require Import sepcomp.effect_simulations.

Import SM_simulation.

Arguments core_diagram : default implicits.
Arguments match_sm_wd : default implicits.
Arguments core_at_external : default implicits.
Arguments disjoint_extern_local_Src : default implicits.

Arguments core_data {F1 V1 C1 F2 V2 C2 Sem1 Sem2 ge1 ge2} _ _.
Arguments core_ord  {F1 V1 C1 F2 V2 C2 Sem1 Sem2 ge1 ge2 entry_points} _ _ _.
Arguments match_state {F1 V1 C1 F2 V2 C2 Sem1 Sem2 ge1 ge2 entry_points} 
  _ _ _ _ _ _ _.

Arguments match_sm_wd 
  {F1 V1 C1 F2 V2 C2 Sem1 Sem2 ge1 ge2 entry_points s d mu c1 m1 c2 m2} _.
Arguments effect_semantics.effax1 {G C e M g c m c' m'} _.
Arguments effect_semantics.effstepN_unchanged {G C Sem g n U c1 m1 c2 m2} _.
Arguments corestep_fwd {G C c g c0 m c' m'} _ _ _.
Arguments effect_semantics.effstepN_fwd {G C Sem g n U c m c' m'} _ _ _.
Arguments match_validblocks 
  {F1 V1 C1 F2 V2 C2 Sem1 Sem2 ge1 ge2 entry_points} s {d mu c1 m1 c2 m2} _.
