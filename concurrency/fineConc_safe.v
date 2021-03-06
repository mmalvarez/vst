Require Import compcert.lib.Axioms.

Require Import concurrency.sepcomp. Import SepComp.
Require Import sepcomp.semantics_lemmas.

Require Import concurrency.pos.


From mathcomp.ssreflect Require Import ssreflect ssrbool ssrnat ssrfun eqtype seq fintype finfun.
Set Implicit Arguments.

(*NOTE: because of redefinition of [val], these imports must appear 
  after Ssreflect eqtype.*)
Require Import compcert.common.AST.     (*for typ*)
Require Import compcert.common.Values. (*for val*)
Require Import compcert.common.Globalenvs. 
Require Import compcert.common.Memory.
Require Import compcert.common.Events.
Require Import compcert.lib.Integers.

Require Import Coq.ZArith.ZArith.

Require Import concurrency.dry_machine_lemmas.
Require Import concurrency.threads_lemmas.
Require Import concurrency.permissions.
Require Import concurrency.concurrent_machine.
Require Import concurrency.mem_obs_eq.
Require Import concurrency.compcert_threads_lemmas.
Require Import concurrency.dry_context.
Require Import Coqlib.
Require Import msl.Coqlib2.

Set Bullet Behavior "None".
Set Bullet Behavior "Strict Subproofs".

Module Type FineConcInitial (SEM : Semantics)
       (Machine : MachinesSig with Module SEM := SEM)
       (AsmContext : AsmContext SEM Machine)
       (CI : CoreInjections SEM).

  Import Renamings MemObsEq ValObsEq ValueWD MemoryWD
         AsmContext CI event_semantics.

  (** The initial memory is well-defined*)
  Parameter init_mem_wd:
    forall m, init_mem = Some m -> valid_mem m.

  (** The initial core is well-defined*)
  Parameter init_core_wd:
    forall v args m (ARGS:valid_val_list (id_ren m) args),
      init_mem = Some m -> 
      match initial_core SEM.Sem the_ge v args with
      | Some c => core_wd (id_ren m) c
      | None => True
      end.

  (** The initial global env is well-defined*)
  Parameter the_ge_wd:
    forall m,
      init_mem = Some m ->
      ge_wd (id_ren m) the_ge.
  
End FineConcInitial.

(** ** Safety for FineConc (interleaving) semantics *)
Module FineConcSafe (SEM : Semantics) (SemAxioms : SemanticsAxioms SEM)
       (Machine : MachinesSig with Module SEM := SEM)
       (AsmContext : AsmContext SEM Machine)
       (CI : CoreInjections SEM)
       (FineConcInitial: FineConcInitial SEM Machine AsmContext CI).

  Module SimProofs := SimProofs SEM SemAxioms Machine AsmContext CI.
  Import AsmContext SimProofs SimDefs Machine DryMachine.
  Import Renamings MemObsEq ValObsEq ValueWD CI FineConcInitial ThreadPool.
  Import SimDefs.StepType dry_machine.Concur.mySchedule.
  Import StepType.InternalSteps StepLemmas.

  Import MemoryWD ThreadPoolInjections event_semantics.
 
  (** Excluded middle is required, but can be easily lifted*)
  Axiom em : ClassicalFacts.excluded_middle.

  Lemma init_tp_wd:
    forall v args m tp (ARGS:valid_val_list (id_ren m) args),
      init_mem = Some m -> 
      init_mach init_perm the_ge v args = Some tp ->
      tp_wd (id_ren m) tp.
  Proof.
    intros.
    intros i cnti.
    unfold init_mach in H0.
    destruct (initial_core SEM.Sem the_ge v args) eqn:?, init_perm; try discriminate.
    inversion H0; subst.
    simpl.
    specialize (init_core_wd v ARGS H). rewrite Heqo; trivial. 
  Qed.
  
  (** Assuming safety of cooperative concurrency*)
  Section safety.
    Variable (f : val) (arg : list val).
    Variable init_coarse_safe:
      forall  U tpc mem sched n,
        init_mem = Some mem ->
        tpc_init f arg = Some (U, [::], tpc) ->
        csafe the_ge (sched,[::],tpc) mem n.

  (** If the initial state is defined then the initial memory was also
defined*)
  Lemma tpc_init_mem_defined:
    forall U tpc,
      tpc_init f arg = Some (U, tpc) ->
      exists m, init_mem = Some m.
  Proof.
    unfold tpc_init. simpl.
    unfold DryConc.init_machine.
    unfold init_mach. intros.
    destruct init_perm eqn:?.
    unfold init_perm in *.
    destruct init_mem; try discriminate.
    eexists; reflexivity.
    destruct (initial_core SEM.Sem the_ge f arg); try discriminate.
  Qed.

  (** Simulation relation with id renaming for initial memory*)
  Lemma init_mem_obs_eq :
    forall m tp i (cnti : containsThread tp i)
      (Hcomp: mem_compatible tp m)
      (HcompF: mem_compatible tp (diluteMem m)),
      init_mem = Some m ->
      init_mach init_perm the_ge f arg = Some tp ->
      mem_obs_eq (id_ren m) (restrPermMap (Hcomp _ cnti))
                 (restrPermMap (HcompF _ cnti)).
  Proof.
    intros.
    pose proof (mem_obs_eq_id (init_mem_wd H)) as Hobs_eq_id.
    unfold init_mach in H0.
    destruct (initial_core SEM.Sem the_ge f arg), init_perm eqn:Hinit_perm;
      try discriminate.
    inversion H0; subst.
    unfold init_perm in Hinit_perm.
    rewrite H in Hinit_perm.
    inversion Hinit_perm. subst.
    destruct Hobs_eq_id.
    constructor.
    - constructor;
      destruct weak_obs_eq0; eauto.
      intros.
      do 2 rewrite restrPermMap_Cur.
      simpl.
      apply id_ren_correct in Hrenaming. subst.
      apply po_refl.
    - constructor.
      intros.
      apply id_ren_correct in Hrenaming.
      subst.
      do 2 rewrite restrPermMap_Cur.
      reflexivity.
      intros.
      apply id_ren_correct in Hrenaming. subst.
      eapply memval_obs_eq_id.
      apply Mem.perm_valid_block in Hperm.
      simpl.
      pose proof (init_mem_wd H Hperm ofs ltac:(reflexivity)).
      destruct (ZMap.get ofs (Mem.mem_contents m) # b2); simpl; auto.
      rewrite <- wd_val_valid; eauto.
      apply id_ren_domain.
      apply id_ren_correct.
  Qed.
  
  Lemma init_compatible:
    forall tp m,
      init_mem = Some m ->
      init_mach init_perm the_ge f arg = Some tp ->
      mem_compatible tp m.
  Proof.
    intros.
    unfold init_mach in *.
    destruct (initial_core SEM.Sem the_ge f arg); try discriminate.
    unfold init_perm in *. rewrite H in H0.
    inversion H0; subst.
    constructor.
    intros j cntj.
    simpl.
    unfold permMapLt; intros.
    rewrite getMaxPerm_correct getCurPerm_correct.
    destruct m; simpl.
    unfold permission_at; simpl.
    apply access_max.
    unfold initial_machine. simpl. intros.
    unfold lockRes in H1.
    simpl in H1.
    rewrite threadPool.find_empty in H1. discriminate.
    unfold initial_machine, lockSet.
    simpl. unfold addressFiniteMap.A2PMap.
    simpl.
    intros b ofs. rewrite Maps.PMap.gi.
    destruct ((getMaxPerm m) # b ofs); simpl; auto.
  Qed.

  Lemma init_thread:
    forall tp i,
      init_mach init_perm the_ge f arg = Some tp ->
      containsThread tp i ->
      containsThread tp 0.
  Proof.
    intros.
    unfold init_mach in *.
    unfold initial_machine in *.
    repeat match goal with
           | [H: match ?Expr with _ => _ end = _ |- _] =>
             destruct Expr eqn:?; try discriminate
           end.
    simpl in H. inversion H; subst.
    unfold containsThread. simpl.
    ssromega.
  Qed.

  Lemma strong_tsim_refl:
    forall tp m i (cnti: containsThread tp i)
      (Hcomp: mem_compatible tp m)
      (HcompF: mem_compatible tp (diluteMem m))
      (ARGS:valid_val_list (id_ren m) arg),
      init_mem = Some m ->
      init_mach init_perm the_ge f arg = Some tp ->
      strong_tsim (id_ren m) cnti cnti Hcomp HcompF.
  Proof.
    intros.
    constructor.
    - eapply ctl_inj_id; eauto.
      apply (init_tp_wd _ ARGS H H0).
      apply id_ren_correct.
    - eapply init_mem_obs_eq; eauto.
  Qed.

  Lemma setMaxPerm_inv:
    forall m, max_inv (diluteMem m).
  Proof.
    intros.
    unfold diluteMem, max_inv, Mem.valid_block, permission_at.
    intros b ofs H.
    simpl in H.
    apply setMaxPerm_MaxV with (ofs := ofs) in H.
    unfold permission_at in H.
    auto.
  Qed.

  (** Establishing the simulation relation for the initial state*)
  Lemma init_sim:
    forall U U' tpc tpf m n (ARG:valid_val_list (id_ren m) arg),
      tpc_init f arg = Some (U, [::], tpc) ->
      tpf_init f arg = Some (U', [::], tpf) ->
      init_mem = Some m ->
      sim tpc m tpf (diluteMem m) nil (id_ren m) (id_ren m) (fun i cnti => id_ren m) n.
  Proof.
    intros.
    unfold tpc_init, tpf_init in *. simpl in *.
    unfold DryConc.init_machine, FineConc.init_machine in *.
    destruct (init_mach init_perm the_ge f arg) eqn:Hinit; try discriminate.
    inversion H; subst. inversion H0; subst.
    clear H H0.
    assert (HmemComp := init_compatible H1 Hinit).
    assert (HmemCompF: mem_compatible tpf (diluteMem m))
      by (eapply mem_compatible_setMaxPerm; eauto).
    eapply Build_sim with (mem_compc := HmemComp) (mem_compf := HmemCompF).
    - intros; split; auto.
    - simpl. rewrite addn0.
      intros.
      eapply init_coarse_safe with (n := n); eauto.
    - intros i cnti cnti'.
      pose proof (strong_tsim_refl cnti HmemComp HmemCompF ARG H1 Hinit).
      pf_cleanup.
      destruct H. destruct obs_eq0.
      eauto.
    - intros; by congruence.
    - intros.
      exists tpf, m.
      split; eauto with renamings.
      split; eauto.
      split; first by constructor.
      split.
      intros; pf_cleanup.
      eapply strong_tsim_refl; eauto.
      repeat (split; intros); congruence.
    - unfold init_mach in *.
      unfold init_perm in Hinit.
      rewrite H1 in Hinit.
      destruct (initial_core SEM.Sem the_ge f arg); try discriminate.
      inversion Hinit; subst.
      split.
      constructor.
      intros.
      do 2 rewrite restrPermMap_Cur.
      unfold initial_machine, lockSet. simpl.
      unfold addressFiniteMap.A2PMap. simpl.
      do 2 rewrite Maps.PMap.gi; reflexivity.
      intros.
      assert (Heq := restrPermMap_Cur (compat_ls HmemComp) b1 ofs).
      unfold permission_at in Heq.
      unfold Mem.perm in Hperm.
      rewrite Heq in Hperm.
      unfold lockSet, initial_machine, addressFiniteMap.A2PMap in Hperm.
      simpl in Hperm.
      rewrite Maps.PMap.gi in Hperm.
      simpl in Hperm. exfalso; auto.
      intros. unfold lockRes, initial_machine in H. simpl in H.
        by exfalso.
    - unfold init_mach, init_perm in Hinit.
      rewrite H1 in Hinit.
      destruct (initial_core SEM.Sem the_ge f arg); try discriminate.
      inversion Hinit; subst.
      unfold lockRes, initial_machine. simpl.
      split; intros.
      exfalso.
      rewrite threadPool.find_empty in Hl1; discriminate.
      split; auto.
    - unfold init_mach, init_perm in Hinit.
      rewrite H1 in Hinit.
      destruct (initial_core SEM.Sem the_ge f arg); try discriminate.
      inversion Hinit; subst.
      apply DryMachineLemmas.initial_invariant.
    - apply setMaxPerm_inv; auto.
    - apply init_mem_wd; auto.
    - eapply init_tp_wd; eauto.
    - eapply the_ge_wd; eauto.
    - split; eauto with renamings.
      apply id_ren_correct.
    - simpl. tauto.
  Qed.

  (** Proof of safety of the FineConc machine*)

  Notation fsafe := (FineConc.fsafe the_ge).

  (*TODO: Put in threadpool*)
  Definition containsThread_dec:
    forall i tp, {containsThread tp i} + { ~ containsThread tp i}.
  Proof.
    intros.
    unfold containsThread.
    destruct (leq (S i) (num_threads tp)) eqn:Hleq;
      by auto.
  Qed.

  Lemma at_external_not_in_xs:
    forall tpc mc tpf mf xs f fg fp i n
      (Hsim: sim tpc mc tpf mf xs f fg fp n)
      (pffi: containsThread tpf i)
      (Hexternal: pffi @ E),
      ~ List.In i xs.
  Proof.
    intros; intro Hin.
    destruct Hsim.
    assert (pfci: containsThread tpc i)
      by (eapply numThreads0; eauto).
    specialize (simStrong0 _ pfci pffi).
    destruct simStrong0 as (tpc' & mc' & Hincr & _ & Hexec & Htsim & _).
    assert (pfci' : containsThread tpc' i)
      by (eapply InternalSteps.containsThread_internal_execution; eauto).

    assert (HmemCompC': mem_compatible tpc' mc')
      by (eapply InternalSteps.internal_execution_compatible with (tp := tpc); eauto).
    specialize (Htsim pfci' HmemCompC').
    destruct Htsim.
    clear - Hexec code_eq0 Hexternal Hin.
    unfold getStepType in Hexternal.
    eapply internal_execution_result_type with (cnti' := pfci') in Hexec; eauto.
    unfold getStepType in Hexec.
    apply ctlType_inj in code_eq0.
    rewrite Hexternal in code_eq0.
    auto.
  Qed.

  Lemma fine_safe:
    forall tpf tpc mf mc (g fg : memren) fp (xs : Sch) sched
      (Hsim: sim tpc mc tpf mf xs g fg fp (S (size sched))),
      fsafe tpf mf sched (S (size sched)).
  Proof.
    intros.
    generalize dependent xs.
    generalize dependent mf.
    generalize dependent tpf.
    generalize dependent fp.
    generalize dependent tpc.
    generalize dependent mc.
    generalize dependent g.
    induction sched as [|i sched]; intros; simpl; auto.
    econstructor; simpl; eauto.
    destruct (containsThread_dec i tpf) as [cnti | invalid].
    - (* By case analysis on the step type *)
      destruct (getStepType cnti) eqn:Htype.
      + pose proof (sim_internal [::] cnti Htype Hsim) as
            (tpf' & m' & fp' & tr' & Hstep & Hsim').
        specialize (Hstep sched).
        specialize (IHsched _ _ _ _ _ _ _ Hsim').
        econstructor 3; simpl; eauto.
      + assert (~ List.In i xs)
          by (eapply at_external_not_in_xs; eauto).
        pose proof (sim_external [::] cnti Htype H Hsim) as Hsim'.
        destruct Hsim' as (? & ? & ? & ? & ? & ? & tr' & Hstep & Hsim'').
        specialize (IHsched _ _ _ _ _ _ _ Hsim'').
        specialize (Hstep sched).
        econstructor 3; simpl; eauto.
      + pose proof (sim_halted [::] cnti Htype Hsim) as Hsim'.
        destruct Hsim' as (tr' & Hstep & Hsim'').
        specialize (IHsched _ _ _ _ _ _ _ Hsim'').
        specialize (Hstep sched).
        econstructor 3;
          eauto.
      + pose proof (sim_suspend [::] cnti Htype Hsim) as
            (? & ? & tpf' & m' & ? & ? & tr' & Hstep & Hsim').
        specialize (IHsched _ _ _ _ _ _ _ Hsim').
        specialize (Hstep sched).
        econstructor 3; simpl; eauto.
    -  pose proof (sim_fail [::] invalid Hsim) as
          (tr' & Hstep & Hsim').
       specialize (IHsched _ _ _ _ _ _ _ Hsim').
       specialize (Hstep sched).
       econstructor 3; eauto.
       Unshelve. eapply [::].
  Qed.


  (** Safety preservation for the FineConc machine starting from the initial state*)
  Theorem init_fine_safe:
    forall U tpf m
      (Hmem: init_mem = Some m)
      (Hinit: tpf_init f arg = Some (U, [::], tpf))
      (ARG: valid_val_list (id_ren m) arg),
    forall (sched : Sch),
      fsafe tpf (diluteMem m) sched (size sched).+1.
  Proof.
    intros. (* specialize (init_sim f ARG (size sched).+1).*)
    assert (Hsim := init_sim (size sched).+1 ARG Hinit Hinit Hmem).
    clear - Hsim.
    eapply fine_safe; eauto.
  Qed.
  

  End safety.
End FineConcSafe.






