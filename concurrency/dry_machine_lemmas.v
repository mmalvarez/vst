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

Require Import concurrency.threads_lemmas.
Require Import concurrency.permissions.
Require Import concurrency.concurrent_machine.
Require Import concurrency.dry_context.

Global Notation "a # b" := (Maps.PMap.get b a) (at level 1).

(** This file holds various results about the dry machine*)

Module ThreadPoolWF (SEM: Semantics) (Machines: MachinesSig with Module SEM := SEM).

  Import Machines DryMachine ThreadPool.
  Lemma unlift_m_inv :
    forall tp tid (Htid : tid < (num_threads tp).+1) ord
      (Hunlift: unlift (ordinal_pos_incr (num_threads tp))
                       (Ordinal (n:=(num_threads tp).+1)
                                (m:=tid) Htid)=Some ord),
      nat_of_ord ord = tid.
  Proof.
    intros.
    assert (Hcontra: unlift_spec (ordinal_pos_incr (num_threads tp))
                                 (Ordinal (n:=(num_threads tp).+1)
                                          (m:=tid) Htid) (Some ord)).
    rewrite <- Hunlift.
    apply/unliftP.
    inversion Hcontra; subst.
    inversion H0.
    unfold bump.
    assert (pf: ord < (num_threads tp))
      by (by rewrite ltn_ord).
    assert (H: (num_threads tp) <= ord = false).
    rewrite ltnNge in pf.
    rewrite <- Bool.negb_true_iff. auto.
    rewrite H. simpl. rewrite add0n. reflexivity.
  Defined.

  (** Well-formed predicate on new permission map*)
  Definition newPermMap_wf tp pmap :=
    forall i (cnt : containsThread tp i),
      permMapsDisjoint (getThreadR cnt) pmap.

  Definition permMap_wf tp pmap i :=
    forall j (cntj : containsThread tp j) (Hneq: i <> j),
      permMapsDisjoint (getThreadR cntj) pmap.
  
  Opaque pos_incr.
  Lemma addThread_racefree :
    forall tp vf arg p (Hwf: newPermMap_wf tp p) (Hrace: race_free tp),
      race_free (addThread tp vf arg p).
  Proof.
    unfold race_free in *. intros.
    simpl.
    match goal with
    | [ |- context[ match ?Expr with _ => _ end]] =>
      destruct Expr as [ordi|] eqn:Hgeti
    end;
      match goal with
      | [ |- context[ match ?Expr with _ => _ end]] =>
        destruct Expr as [ordj|] eqn:Hgetj
      end.
    unfold containsThread in *; simpl in *.
    - unfold getThreadR in Hrace.
      apply unlift_m_inv in Hgeti.
      apply unlift_m_inv in Hgetj.
      destruct ordi as [i' pfi], ordj as [j' pfj]; subst.
      simpl in *.
      eapply Hrace; eauto.
    - apply unlift_m_inv in Hgeti.
      subst. unfold newPermMap_wf in Hwf.
      destruct ordi. eapply Hwf; eauto.
    - apply unlift_m_inv in Hgetj.
      subst. unfold newPermMap_wf in Hwf.
      destruct ordj. apply permMapsDisjoint_comm. eapply Hwf; eauto.
    - destruct (i == (num_threads tp)) eqn:Heqi.
      + move/eqP:Heqi=>Heqi. subst.
        assert (Hcontra: (ordinal_pos_incr (num_threads tp))
                           != (Ordinal (n:=(num_threads tp).+1) (m:=j) cntj)).
        { apply/eqP. intros Hcontra.
          unfold ordinal_pos_incr in Hcontra.
          inversion Hcontra; auto.
        }
        exfalso. apply unlift_some in Hcontra. rewrite Hgetj in Hcontra.
        destruct Hcontra. discriminate.
      + move/eqP:Heqi=>Heqi.
        assert (
            Hcontra: (ordinal_pos_incr (num_threads tp))
                       !=
                       (Ordinal (n:=(num_threads tp).+1) (m:=i) cnti)).
        { apply/eqP. intros Hcontra.
          unfold ordinal_pos_incr in Hcontra. inversion Hcontra. subst. auto. }
        exfalso. apply unlift_some in Hcontra.
        rewrite Hgeti in Hcontra. destruct Hcontra.
        discriminate.
  Defined.

  Lemma invariant_decr:
    forall tp c pmap i (cnti: containsThread tp i)
      (Hinv: invariant tp)
      (Hdecr: forall b ofs,
          Mem.perm_order'' ((getThreadR cnti) # b ofs)
                           (pmap # b ofs)),
      invariant (updThread cnti c pmap).
  Proof.
    intros.
    destruct Hinv.
    constructor.
    - intros k j cntk cntj Hkj.
      destruct (i == k) eqn:Hik; move/eqP:Hik=>Hik.
      subst k.
      rewrite gssThreadRes.
      rewrite gsoThreadRes; auto.
      intros b ofs.
      specialize (no_race0 _ _ cnti cntj Hkj b ofs).
      rewrite perm_union_comm.
      rewrite perm_union_comm in no_race0;
        by eapply perm_union_lower; eauto.
      rewrite gsoThreadRes; auto.
      destruct (i == j) eqn:Hij; move/eqP:Hij=>Hij.
      subst j.
      rewrite gssThreadRes.
      intros b ofs.
      specialize (no_race0 _ _ cntk cnti Hkj b ofs);
        by eapply perm_union_lower; eauto.
      rewrite gsoThreadRes;
        by auto.
    - intros j cntj.
      destruct (i == j) eqn:Hij; move/eqP:Hij=>Hij.
      subst.
      rewrite gssThreadRes.
      intros b ofs.
      specialize (lock_set_threads0 _ cnti b ofs).
      eapply perm_union_lower;
        by eauto.
      rewrite gsoThreadRes;
        by eauto.
    - intros l rmap j cntj Hres.
      destruct (i == j) eqn:Hij; move/eqP:Hij=>Hij.
      subst j.
      rewrite gssThreadRes.
      intros b ofs.
      specialize (lock_res_threads0 _ _ i cnti Hres b ofs).
      eapply perm_union_lower;
        by eauto.
      rewrite gsoThreadRes;
        by eauto.
    - by eauto.
      eauto.
  Qed.

  Lemma lock_valid_block:
    forall (tpc : thread_pool) (mc : mem) (bl1 : block) 
      (ofs : Z) rmap1
      (HmemCompC: mem_compatible tpc mc)
      (Hl1: lockRes tpc (bl1, ofs) = Some rmap1),
      Mem.valid_block mc bl1.
  Proof.
    intros.
    assert (HlockSet := lockSet_spec_1 tpc bl1 ofs ltac:(rewrite Hl1; auto)).
    destruct (valid_block_dec mc bl1) as [? | Hinvalid]; auto.
    exfalso.
    apply (Mem.nextblock_noaccess) with (k:= Max) (ofs := ofs) in Hinvalid.
    assert (H:= compat_ls HmemCompC).
    unfold permMapLt in H.
    specialize (H bl1 ofs).
    rewrite getMaxPerm_correct in H.
    unfold permission_at in H.
    rewrite Hinvalid in H.
    rewrite HlockSet in H;
      by simpl in H.
  Qed.

End ThreadPoolWF.

Module Type SemanticsAxioms (SEM: Semantics).

  Import event_semantics SEM.
  Parameter corestep_det: corestep_fun Sem.
  Parameter corestep_unchanged_on:
    forall the_ge c m c' m' b ofs
      (Hstep: corestep (msem Sem) the_ge c m c' m')
      (Hvalid: Mem.valid_block m b)
      (Hstable: ~ Mem.perm m b ofs Cur Writable),
      Maps.ZMap.get ofs (Maps.PMap.get b (Mem.mem_contents m)) =
      Maps.ZMap.get ofs (Maps.PMap.get b (Mem.mem_contents m')).
  Parameter corestep_decay:
    forall ge c c' m m',
      corestep Sem ge c m c' m' ->
      decay m m'.
  Parameter corestep_nextblock:
    forall ge c m c' m',
      corestep Sem ge c m c' m' ->
      (Mem.nextblock m <= Mem.nextblock m')%positive.
End SemanticsAxioms.
                                          
(** ** Lemmas about threadwise semantics*)
Module CoreLanguage (SEM : Semantics) (SemAxioms: SemanticsAxioms SEM).
  Import SEM event_semantics SemAxioms.
 
  Lemma corestep_validblock:
      forall ge c m c' m',
        corestep Sem ge c m c' m' ->
        forall b, Mem.valid_block m b ->
             Mem.valid_block m' b.
    Proof.
      intros.
      eapply corestep_nextblock in H.
      unfold Mem.valid_block, Coqlib.Plt in *.
      zify;
        by omega.
    Qed.

    Definition ev_step_det:
        forall (m m' m'' : mem) (ge : G) (c c' c'' : C) ev ev',
          ev_step Sem ge c m ev c' m' ->
          ev_step Sem ge c m ev' c'' m'' -> c' = c'' /\ m' = m'' /\ ev = ev'.
    Proof.
      intros.
      assert (Hcore := ev_step_ax1 _ _ _ _ _ _ _ H).
      assert (Hcore' := ev_step_ax1 _ _ _ _ _ _ _ H0).
      assert (Heq := corestep_det _ _ _  _ _ _ _ Hcore Hcore').
      destruct Heq; repeat split; auto.
      eapply ev_step_fun; eauto.
    Qed.

    Lemma ev_unchanged_on:
      forall the_ge c m c' m' b ofs ev
        (Hstep: ev_step Sem the_ge c m ev c' m')
        (Hvalid: Mem.valid_block m b)
        (Hstable: ~ Mem.perm m b ofs Cur Writable),
        Maps.ZMap.get ofs (Maps.PMap.get b (Mem.mem_contents m)) =
        Maps.ZMap.get ofs (Maps.PMap.get b (Mem.mem_contents m')).
    Proof.
      intros.
      apply ev_step_ax1 in Hstep.
      eapply corestep_unchanged_on; eauto.
    Qed.

    Lemma ev_step_decay:
      forall ge c c' m m' ev,
        ev_step Sem ge c m ev c' m' ->
        decay m m'.
    Proof.
      intros.
      apply ev_step_ax1 in H.
      eapply corestep_decay; eauto.
    Qed.

    Lemma ev_step_nextblock:
      forall ge c m ev c' m',
        ev_step Sem ge c m ev c' m' ->
        (Mem.nextblock m <= Mem.nextblock m')%positive.
    Proof.
      intros.
      apply ev_step_ax1 in H.
      eapply corestep_nextblock; eauto.
    Qed.

    Lemma ev_step_validblock:
      forall ge c m ev c' m',
        ev_step Sem ge c m ev c' m' ->
        forall b, Mem.valid_block m b ->
             Mem.valid_block m' b.
    Proof.
      intros.
      eapply ev_step_ax1 in H.
      eapply corestep_nextblock in H.
      unfold Mem.valid_block, Coqlib.Plt in *.
      zify;
        by omega.
    Qed.
End CoreLanguage.


(** Lemmas about the threadwise semantics with respect to a (dry) concurrent machine*)
Module CoreLanguageDry (SEM : Semantics) (SemAxioms: SemanticsAxioms SEM)
       (DryMachine : dry_machine.Concur.DryMachineSig SEM).
               
  Import SEM event_semantics SemAxioms DryMachine ThreadPool.

  Module CoreLanguage := CoreLanguage SEM SemAxioms.
  Import CoreLanguage.
  (* TODO: These proofs break the opaquness of the modules, they
    should be redone in an opaque way *)


    (** Lemmas about containsThread and coresteps *)
    Lemma corestep_containsThread:
      forall (tp : thread_pool) ge c c' m m' p i j ev
        (Hcnti : containsThread tp i)
        (Hcntj: containsThread tp j)
        (Hcorestep: ev_step Sem ge c m ev c' m')
        (Hcode: getThreadC Hcnti = Krun c),
        containsThread (updThread Hcnti (Krun c') p) j.
    Proof.
      intros.
        by eapply cntUpdate.
    Qed.

    Lemma corestep_containsThread':
      forall (tp : thread_pool) ge c c' m m' p i j ev
        (Hcnti : containsThread tp i)
        (Hcntj : containsThread (updThread Hcnti (Krun c') p) j)
        (Hcorestep: ev_step Sem ge c m ev c' m')
        (Hcode: getThreadC Hcnti = Krun c),
        containsThread tp j.
    Proof.
      intros.
        by eapply cntUpdate'; eauto.
    Qed.

    (** Lemmas about invariants maintaned by coresteps*)
    
    Lemma corestep_compatible:
      forall (tp : thread_pool) ge (m m' : mem) i ev
        (pf : containsThread tp i) (c c': C)
        (Hinv: invariant tp)
        (Hcode: getThreadC pf = Krun c)
        (Hcompatible : mem_compatible tp m)
        (Hcorestep: ev_step Sem ge c (restrPermMap (Hcompatible i pf)) ev c' m'),
        mem_compatible (updThread pf (Krun c') (getCurPerm m')) m'.
    Proof.
      intros.
      constructor. 
      { intros tid cnt b ofs.
        destruct (tid == i) eqn:Htid;
          move/eqP:Htid=>Htid;
          first by (subst; erewrite gssThreadRes; eapply getCur_Max).
        assert (cnt0 : containsThread tp tid)
          by (eapply cntUpdate' in cnt; auto).
        assert (Hlt := Hcompatible tid cnt0 b ofs).
        assert (Hdecay := ev_step_decay _ _ _ _ _ _ Hcorestep).
        destruct (valid_block_dec (restrPermMap (Hcompatible i pf)) b)
          as [Hvalid|Hinvalid].
        - destruct (Hdecay b ofs) as [ _ HdecayValid].
          destruct (HdecayValid Hvalid) as [Hfreed | Heq]; clear Hdecay.
          + destruct (Hfreed Cur) as [HFree Hdrop].
            assert (Hempty: (getThreadR cnt) # b ofs = None).
            { assert (Hp := restrPermMap_Cur (Hcompatible i pf) b ofs).
              unfold permission_at in Hp. rewrite Hp in HFree.
              assert (Hno_race := no_race Hinv).
              unfold race_free in Hno_race.
              specialize (Hno_race _ _ cnt0 pf Htid).
              unfold permMapsDisjoint in Hno_race.
              specialize (Hno_race b ofs).
              assert (Hnot_racy : not_racy ((getThreadR cnt0) # b ofs)).
              rewrite perm_union_comm in Hno_race.
              eapply no_race_racy with (p1 := (getThreadR pf) # b ofs); eauto.
              rewrite HFree. constructor.
              rewrite gsoThreadRes; auto.
                by inversion Hnot_racy.
            }
            rewrite Hempty.
            destruct ((getMaxPerm m') # b ofs); simpl; auto.
          + rewrite getMaxPerm_correct. unfold permission_at.
            assert (HeqCur := Heq Max).
            rewrite <- HeqCur.
            rewrite gsoThreadRes; auto.
            assert (H := compat_th Hcompatible cnt0).
            assert (Hrestr_max := restrPermMap_Max (Hcompatible i pf) b ofs).
            unfold permission_at in Hrestr_max.
            rewrite Hrestr_max;
              by eauto.                        
        - apply Mem.nextblock_noaccess with (ofs := ofs) (k := Max) in Hinvalid.
          assert (Hp := restrPermMap_Max (Hcompatible i pf) b ofs).
          unfold permission_at in Hp. rewrite Hp in Hinvalid.
          rewrite Hinvalid in Hlt.
          simpl in Hlt.
          rewrite gsoThreadRes; auto.
          destruct ((getThreadR cnt0) # b ofs);
            [by exfalso| destruct ((getMaxPerm m') # b ofs); simpl; by auto].
      }
      { intros l pmap Hres b ofs.
        rewrite gsoThreadLPool in Hres.
        assert (Hlt := compat_lp Hcompatible _ Hres b ofs).
        assert (Hdecay := ev_step_decay _ _ _ _ _ _ Hcorestep).
        destruct (valid_block_dec (restrPermMap (Hcompatible i pf)) b)
          as [Hvalid|Hinvalid].
        - destruct (Hdecay b ofs) as [ _ HdecayValid].
          destruct (HdecayValid Hvalid) as [Hfreed | Heq]; clear Hdecay.
          + destruct (Hfreed Cur) as [HFree Hdrop].
            assert (Hempty: pmap # b ofs = None).
            { assert (Hp := restrPermMap_Cur (Hcompatible i pf) b ofs).
              unfold permission_at in Hp. rewrite Hp in HFree.
              assert (Hno_race := lock_res_threads Hinv).
              unfold race_free in Hno_race.
              specialize (Hno_race _ _ _ pf Hres).
              unfold permMapsDisjoint in Hno_race.
              specialize (Hno_race b ofs).
              assert (Hnot_racy : not_racy (pmap # b ofs)).
              rewrite perm_union_comm in Hno_race.
              eapply no_race_racy with (p1 := (getThreadR pf) # b ofs); eauto.
              rewrite HFree.
              constructor.
                by inversion Hnot_racy.
            }
            rewrite Hempty.
            destruct ((getMaxPerm m') # b ofs); simpl; auto.
          + rewrite getMaxPerm_correct. unfold permission_at.
            assert (HeqCur := Heq Max).
            rewrite <- HeqCur.
            assert (H := compat_lp Hcompatible _ Hres b ofs).
            assert (Hrestr_max := restrPermMap_Max (Hcompatible i pf) b ofs).
            unfold permission_at in Hrestr_max.
            rewrite Hrestr_max;
              by eauto.
        - apply Mem.nextblock_noaccess with (ofs := ofs) (k := Max) in Hinvalid.
          assert (Hp := restrPermMap_Max (Hcompatible i pf) b ofs).
          unfold permission_at in Hp. rewrite Hp in Hinvalid.
          rewrite Hinvalid in Hlt.
          simpl in Hlt.
          destruct (pmap # b ofs);
            [by exfalso| destruct ((getMaxPerm m') # b ofs); simpl; by auto].
      }
      { rewrite gsoThreadLock. intros b ofs.
        assert (Hlt := compat_ls Hcompatible b ofs).
        assert (Hdecay := ev_step_decay _ _ _ _ _ _ Hcorestep).
        destruct (valid_block_dec (restrPermMap (Hcompatible i pf)) b)
          as [Hvalid|Hinvalid].
        - destruct (Hdecay b ofs) as [ _ HdecayValid].
          destruct (HdecayValid Hvalid) as [Hfreed | Heq]; clear Hdecay.
          + destruct (Hfreed Cur) as [HFree Hdrop].
            assert (Hempty: (lockSet tp) # b ofs = None).
            { assert (Hp := restrPermMap_Cur (Hcompatible i pf) b ofs).
              unfold permission_at in Hp. rewrite Hp in HFree.
              assert (Hno_race := lock_set_threads Hinv).
              unfold race_free in Hno_race.
              specialize (Hno_race _ pf).
              unfold permMapsDisjoint in Hno_race.
              specialize (Hno_race b ofs).
              assert (Hnot_racy : not_racy ((lockSet tp) # b ofs)).
              rewrite perm_union_comm in Hno_race.
              eapply no_race_racy with (p1 := (getThreadR pf) # b ofs); eauto.
              rewrite HFree.
              constructor.
                by inversion Hnot_racy.
            }
            rewrite Hempty.
            destruct ((getMaxPerm m') # b ofs); simpl; auto.
          + rewrite getMaxPerm_correct. unfold permission_at.
            assert (HeqCur := Heq Max).
            rewrite <- HeqCur.
            assert (H := compat_ls Hcompatible b ofs).
            assert (Hrestr_max := restrPermMap_Max (Hcompatible i pf) b ofs).
            unfold permission_at in Hrestr_max.
            rewrite Hrestr_max;
              by eauto.
        - apply Mem.nextblock_noaccess with (ofs := ofs) (k := Max) in Hinvalid.
          assert (Hp := restrPermMap_Max (Hcompatible i pf) b ofs).
          unfold permission_at in Hp. rewrite Hp in Hinvalid.
          rewrite Hinvalid in Hlt.
          simpl in Hlt.
          destruct ((lockSet tp) # b ofs);
            [by exfalso| destruct ((getMaxPerm m') # b ofs); simpl; by auto].
      }
    Qed.

    Lemma decay_disjoint:
      forall m m' p
        (Hdecay: decay m m')
        (Hlt: permMapLt p (getMaxPerm m))
        (Hdisjoint: permMapsDisjoint (getCurPerm m) p),
        permMapsDisjoint (getCurPerm m') p.
    Proof.
      intros.
      unfold permMapsDisjoint in *.
      intros.
      destruct (Hdecay b ofs) as [_ Hold].
      clear Hdecay.
      specialize (Hdisjoint b ofs).
      destruct (valid_block_dec m b) as [Hvalid | Hinvalid].
      - destruct (Hold Hvalid) as [Hfree | Heq].
        + destruct (Hfree Cur) as [_ Hm']. rewrite getCurPerm_correct.
          assert (not_racy (permission_at m' b ofs Cur))
            by (unfold permission_at; rewrite Hm'; constructor).
            by eapply not_racy_union.
        + rewrite getCurPerm_correct. unfold permission_at.
          rewrite <- Heq. rewrite getCurPerm_correct in Hdisjoint.
          unfold permission_at in Hdisjoint. assumption.
      - assert (Hnone: (p # b ofs) = None).
        { apply Mem.nextblock_noaccess with (ofs := ofs) (k := Max) in Hinvalid.
          unfold permMapLt in Hlt.
          specialize (Hlt b ofs).
          rewrite getMaxPerm_correct in Hlt.
          unfold permission_at in Hlt.
          rewrite Hinvalid in Hlt. simpl in Hlt.
          destruct (p # b ofs); tauto.
        }
        rewrite Hnone.
        rewrite perm_union_comm.
        eapply not_racy_union;
          by constructor.
    Qed.

    Opaque getThreadR.
    Lemma corestep_invariant:
      forall (tp : thread_pool) ge (m : mem) (i : nat)
        (pf : containsThread tp i) c m1 m1' c'
        (Hinv: invariant tp)
        (Hcompatible: mem_compatible tp m)
        (Hrestrict_pmap :restrPermMap (Hcompatible i pf) = m1)
        (Hcorestep: corestep Sem ge c m1 c' m1')
        (Hcode: getThreadC pf = Krun c),
        invariant (updThread pf (Krun c') (getCurPerm m1')).
    Proof.
      intros.
      destruct Hinv as [Hrace Hlp].
      apply corestep_decay in Hcorestep.
      constructor.
      { (* non-interference in threads *)
        unfold race_free in *.
        intros j k.
        destruct (i == j) eqn:Heqj, (i == k) eqn:Heqk; move/eqP:Heqj=>Heqj;
          move/eqP:Heqk=>Heqk; simpl in *; intros cntj' cntk' Hneq;
                        assert (cntk: containsThread tp k)
                          by (eapply cntUpdate'; eauto);
                        assert (cntj: containsThread tp j)
                          by (eapply cntUpdate'; eauto).
        - subst j k; exfalso; auto.
        - subst j.
          erewrite gssThreadRes.
          erewrite @gsoThreadRes with (cntj := cntk); eauto.
          specialize (Hrace _ _ pf cntk Hneq).
          assert (Hlt := compat_th Hcompatible cntk).
          subst m1.
          eapply decay_disjoint; eauto.
          unfold permMapLt in *.
          intros b ofs.
          rewrite getMaxPerm_correct;
            by rewrite restrPermMap_Max.
          intros b ofs.
          rewrite getCurPerm_correct;
            by rewrite restrPermMap_Cur.
        - subst k.
          erewrite @gsoThreadRes with (cntj := cntj); auto.
          erewrite gssThreadRes.
          specialize (Hrace _ _ pf cntj Heqj).
          assert (Hlt := compat_th Hcompatible cntj).
          subst m1.
          eapply permMapsDisjoint_comm.
          eapply decay_disjoint; eauto.
          unfold permMapLt in *.
          intros b ofs.
          rewrite getMaxPerm_correct;
            by rewrite restrPermMap_Max.
          intros b ofs.
          rewrite getCurPerm_correct;
            by rewrite restrPermMap_Cur.
        - erewrite @gsoThreadRes with (cntj := cntj); auto.
          erewrite @gsoThreadRes with (cntj := cntk); auto.
      }
      { (* non-interference with lockpool*)
        intros j cntj.
        rewrite gsoThreadLock.
        destruct (i == j) eqn:Hij; move/eqP:Hij=>Hik; subst.
        - erewrite gssThreadRes. apply permMapsDisjoint_comm.
          assert (Hlt := compat_ls Hcompatible).
          eapply decay_disjoint; eauto.
          intros b ofs.
          rewrite getMaxPerm_correct;
            by rewrite restrPermMap_Max.
          intros b ofs. rewrite perm_union_comm.
          rewrite getCurPerm_correct.
          rewrite restrPermMap_Cur.
            by eapply Hlp.
        - erewrite @gsoThreadRes with (cntj := cntUpdate'  cntj);
            by eauto.
      }
      { intros l pmap j cntj Hres.
        rewrite gsoThreadLPool in Hres.
        destruct (i == j) eqn:Hij; move/eqP:Hij=>Hik; subst.
        - erewrite gssThreadRes. apply permMapsDisjoint_comm.
          assert (Hlt := compat_lp Hcompatible _ Hres).
          eapply decay_disjoint; eauto.
          intros b ofs.
          rewrite getMaxPerm_correct;
            by rewrite restrPermMap_Max.
          intros b ofs. rewrite perm_union_comm.
          rewrite getCurPerm_correct.
          rewrite restrPermMap_Cur;
            by (eapply lock_res_threads0; eauto).
        - erewrite @gsoThreadRes with (cntj := cntUpdate' cntj);
            by eauto.
      }
      { intros l pmap Hres.
        rewrite gsoThreadLock.
        rewrite gsoThreadLPool in Hres;
          by eauto.
      }
      eapply updThread_lr_valid; eauto.
    Qed.

    Lemma corestep_disjoint_val:
      forall (tp : thread_pool) ge (m m' : mem) i j (Hneq: i <> j)
        (c c' : C) 
        (pfi : containsThread tp i) (pfj : containsThread tp j)
        (Hcomp : mem_compatible tp m) (b : block) (ofs : Z) 
        (Hreadable: Mem.perm (restrPermMap (Hcomp j pfj)) b ofs Cur Readable)
        (Hcorestep: corestep Sem ge c (restrPermMap (Hcomp i pfi)) c' m')
        (Hinv: invariant tp),
        Maps.ZMap.get ofs (Mem.mem_contents m) # b =
        Maps.ZMap.get ofs (Mem.mem_contents m') # b.
    Proof.
      intros.
      assert (Hstable: ~ Mem.perm (restrPermMap (Hcomp _ pfi))
                         b ofs Cur Writable).
      { intros Hcontra.
        assert (Hdisjoint := no_race Hinv pfi pfj Hneq).
        assert (Hpermi := restrPermMap_correct (Hcomp _ pfi) b ofs).
        destruct Hpermi as [_ Hpermi].
        assert (Hpermj := restrPermMap_correct (Hcomp _ pfj) b ofs).
        destruct Hpermj as [_ Hpermj].
        unfold permission_at, Mem.perm in *.
        rewrite Hpermi in Hcontra.
        rewrite Hpermj in Hreadable.
        unfold Mem.perm_order' in *.
        clear - Hcontra Hreadable Hdisjoint.
        specialize (Hdisjoint b ofs). destruct Hdisjoint as [pu Hunion].
        destruct ((getThreadR pfi) # b ofs);
          try (exfalso; assumption);
          inversion Hcontra; subst; simpl in Hunion;
          destruct ((getThreadR pfj) # b ofs);
          try match goal with
              | [H: Some _ = Some _ |- _] => inversion H; subst
              | [H: match ?Expr with _ => _ end = _ |- _] => destruct Expr
              end; try discriminate; inversion Hreadable.
      }
      apply corestep_unchanged_on with (b := b) (ofs := ofs) in Hcorestep; auto.
      erewrite restrPermMap_valid.
      destruct (valid_block_dec m b); auto.
      apply Mem.nextblock_noaccess with (ofs := ofs) (k := Max) in n.
      assert (Hlt := Hcomp _ pfj b ofs).
      rewrite getMaxPerm_correct in Hlt.
      assert (Heq:= restrPermMap_Cur (Hcomp j pfj) b ofs).
      unfold permission_at in *.
      unfold Mem.perm in *.
      rewrite Heq in Hreadable.
      rewrite n in Hlt.
      destruct ((getThreadR pfj) # b ofs); simpl in *;
        by exfalso.
    Qed.

    Lemma corestep_disjoint_val_lockset:
      forall (tp : thread_pool) ge (m m' : mem) i
        (c c' : C) 
        (pfi : containsThread tp i)
        (Hcomp : mem_compatible tp m) (b : block) (ofs : Z) 
        (Hreadable: Mem.perm (restrPermMap (compat_ls Hcomp)) b ofs Cur Readable)
        (Hcorestep: corestep Sem ge c (restrPermMap (Hcomp i pfi)) c' m')
        (Hinv: invariant tp),
        Maps.ZMap.get ofs (Mem.mem_contents m) # b =
        Maps.ZMap.get ofs (Mem.mem_contents m') # b.
    Proof.
      intros.
      assert (Hstable: ~ Mem.perm (restrPermMap (Hcomp _ pfi))
                         b ofs Cur Writable).
      { intros Hcontra.
        assert (Hdisjoint := lock_set_threads Hinv pfi).
        assert (Hpermi := restrPermMap_correct (Hcomp _ pfi) b ofs).
        destruct Hpermi as [_ Hpermi].
        assert (Hpermls := restrPermMap_correct ((compat_ls Hcomp)) b ofs).
        destruct Hpermls as [_ Hpermls].
        unfold permission_at, Mem.perm in *.
        rewrite Hpermi in Hcontra.
        rewrite Hpermls in Hreadable.
        unfold Mem.perm_order' in *.
        clear - Hcontra Hreadable Hdisjoint.
        specialize (Hdisjoint b ofs). destruct Hdisjoint as [pu Hunion].
        destruct ((getThreadR pfi) # b ofs);
          try (exfalso; assumption);
          inversion Hcontra; subst; simpl in *;
          destruct ((lockSet tp) # b ofs); simpl in *;
          try match goal with
              | [H: Some _ = Some _ |- _] => inversion H; subst
              | [H: match ?Expr with _ => _ end = _ |- _] => destruct Expr
              end; try discriminate; inversion Hreadable.
      }
      apply corestep_unchanged_on with (b := b) (ofs := ofs) in Hcorestep; auto.
      erewrite restrPermMap_valid.
      destruct (valid_block_dec m b); auto.
      apply Mem.nextblock_noaccess with (ofs := ofs) (k := Max) in n.
      assert (Hlt := (compat_ls Hcomp) b ofs).
      rewrite getMaxPerm_correct in Hlt.
      assert (Heq:= restrPermMap_Cur (compat_ls Hcomp) b ofs).
      unfold permission_at in *.
      unfold Mem.perm in *.
      rewrite Heq in Hreadable.
      rewrite n in Hlt.
      destruct ((lockSet tp) # b ofs); simpl in *;
        by exfalso.
    Qed.

    Lemma corestep_disjoint_val_lockpool :
      forall (tp : thread_pool) ge (m m' : mem) i (c c' : C)
        (pfi : containsThread tp i) (Hcomp : mem_compatible tp m) addr pmap
        (Hlock: lockRes tp addr = Some pmap)
        (b : block) (ofs : Z)
        (Hreadable: Mem.perm (restrPermMap (compat_lp Hcomp _ Hlock))
                             b ofs Cur Readable)
        (Hcorestep: corestep Sem ge c (restrPermMap (Hcomp i pfi)) c' m')
        (Hinv: invariant tp),
        Maps.ZMap.get ofs (Mem.mem_contents m) # b =
        Maps.ZMap.get ofs (Mem.mem_contents m') # b.
    Proof.
      intros.
      assert (Hstable: ~ Mem.perm (restrPermMap (Hcomp _ pfi))
                         b ofs Cur Writable).
      { intros Hcontra.
        assert (Hdisjoint := lock_res_threads Hinv _ pfi Hlock).
        assert (Hpermi := restrPermMap_Cur (Hcomp _ pfi) b ofs).
        assert (Hpermls := restrPermMap_Cur ((compat_lp Hcomp _ Hlock)) b ofs).
        unfold permission_at, Mem.perm in *.
        rewrite Hpermi in Hcontra.
        rewrite Hpermls in Hreadable.
        unfold Mem.perm_order' in *.
        clear - Hcontra Hreadable Hdisjoint.
        specialize (Hdisjoint b ofs). destruct Hdisjoint as [pu Hunion].
        destruct ((getThreadR pfi) # b ofs);
          try (exfalso; assumption);
          inversion Hcontra; subst; simpl in *;
          destruct (pmap # b ofs); simpl in *;
          try match goal with
              | [H: Some _ = Some _ |- _] => inversion H; subst
              | [H: match ?Expr with _ => _ end = _ |- _] => destruct Expr
              end; try discriminate; inversion Hreadable.
      }
      apply corestep_unchanged_on with (b := b) (ofs := ofs) in Hcorestep; auto.
      erewrite restrPermMap_valid.
      destruct (valid_block_dec m b); auto.
      apply Mem.nextblock_noaccess with (ofs := ofs) (k := Max) in n.
      assert (Hlt := ((compat_lp Hcomp) _ _  Hlock) b ofs).
      rewrite getMaxPerm_correct in Hlt.
      assert (Heq:= restrPermMap_Cur ((compat_lp Hcomp) _ _  Hlock) b ofs).
      unfold permission_at in *.
      unfold Mem.perm in *.
      rewrite Heq in Hreadable.
      rewrite n in Hlt.
      destruct (pmap # b ofs); simpl in *;
        by exfalso.
    Qed.
    
End CoreLanguageDry.

(** These lemmas require the machines. But the machines are
parameterized by the semantics so they can be used by either
high-level or low-level languages*)
Module StepLemmas (SEM : Semantics)
       (Machine : MachinesSig with Module SEM := SEM).
               
  Import SEM event_semantics.
  Import Machine DryMachine DryConc ThreadPool.
  
  Lemma updThreadC_compatible:
    forall (tp : thread_pool) m i (c : ctl)
      (ctn : containsThread tp i)
      (Hcomp: mem_compatible tp m),
      mem_compatible (updThreadC ctn c) m.
  Proof.
    intros.
    constructor.
    intros j cntj'.
    assert (cntj := cntUpdateC' _ _ cntj').
    specialize (Hcomp _ cntj).
    erewrite @gThreadCR with (cntj := cntj);
      by auto.
    intros.
    erewrite gsoThreadCLPool in H.
    destruct Hcomp;
      by eauto.
    erewrite @gsoThreadCLock;
      by destruct Hcomp.
  Qed.

  Lemma updThreadC_invariant:
    forall (tp : thread_pool) i (c : ctl)
      (ctn : containsThread tp i)
      (Hinv : invariant tp),
      invariant (updThreadC ctn c).
  Proof.
    intros. 
    inversion Hinv;
    constructor; unfold race_free in *;
      simpl;
      try  by auto.
  Qed.

  (** Lemmas about suspend steps*)
  Lemma suspendC_step_det:
    forall tp tp' tp'' i (cnt: containsThread tp i)
      (Hstep: suspend_thread cnt tp')
      (Hstep':suspend_thread cnt tp''),
      tp' = tp''.
  Proof.
    intros.
    inversion Hstep; inversion Hstep'; subst.
    pf_cleanup. rewrite Hcode in Hcode0.
    inversion Hcode0; by subst.
  Qed.

  Lemma suspendF_containsThread:
    forall tp tp' i j (cnti: containsThread tp i)
      (Hsuspend: FineConc.suspend_thread cnti tp'),
      containsThread tp j <-> containsThread tp' j.
  Proof.
    intros; inversion Hsuspend; subst.
    split;
      [eapply cntUpdateC | eapply cntUpdateC'].
  Qed.

  Lemma suspendC_containsThread:
    forall tp tp' i j (cnti: containsThread tp i)
      (Hsuspend: DryConc.suspend_thread cnti tp'),
      containsThread tp j <-> containsThread tp' j.
  Proof.
    intros; inversion Hsuspend; subst.
    split;
      [eapply cntUpdateC | eapply cntUpdateC'].
  Qed.

  Corollary suspendC_compatible:
    forall tp tp' m i (cnt: containsThread tp i)
      (Hcomp: mem_compatible tp m)
      (Hsuspend: DryConc.suspend_thread cnt tp'),
      mem_compatible tp' m.
  Proof.
    intros. inversion Hsuspend; subst.
      by eapply updThreadC_compatible.
  Qed.

  Corollary suspendF_compatible:
    forall tp tp' m i (cnt: containsThread tp i)
      (Hcomp: mem_compatible tp m)
      (Hsuspend: FineConc.suspend_thread cnt tp'),
      mem_compatible tp' m.
  Proof.
    intros. inversion Hsuspend; subst.
      by apply updThreadC_compatible.
  Qed.

  Lemma gsoThreadC_suspend:
    forall (tp : thread_pool) (i j : tid) (cntj : containsThread tp j)
      (c : code) (Hneq: i <> j) (cnti : containsThread tp i)
      (cntj' : containsThread (updThreadC cnti (Kblocked c)) j),
      getThreadC cntj = getThreadC cntj'.
  Proof.
    intros; erewrite gsoThreadCC; eauto.
  Qed.
  
  Corollary gsoThreadC_suspendC:
    forall tp tp' i j (cnt: containsThread tp i) (cntj: containsThread tp j)
      (cntj': containsThread tp' j) (Hneq: i <> j)
      (Hsuspend: DryConc.suspend_thread cnt tp'),
      getThreadC cntj = getThreadC cntj'.
  Proof.
    intros; inversion Hsuspend; subst;
      by apply gsoThreadC_suspend.
  Qed.

  Corollary gsoThreadC_suspendF:
    forall tp tp' i j (cnt: containsThread tp i) (cntj: containsThread tp j)
      (cntj': containsThread tp' j) (Hneq: i <> j)
      (Hsuspend: FineConc.suspend_thread cnt tp'),
      getThreadC cntj = getThreadC cntj'.
  Proof.
    intros; inversion Hsuspend; subst;
      by apply gsoThreadC_suspend.
  Qed.

  Lemma gsoThreadR_suspendC:
    forall tp tp' i j (cnt: containsThread tp i) (cntj: containsThread tp j)
      (cntj': containsThread tp' j)
      (Hsuspend: DryConc.suspend_thread cnt tp'),
      getThreadR cntj = getThreadR cntj'.
  Proof.
    intros. inversion Hsuspend. subst.
      by erewrite @gThreadCR with (cntj := cntj).
  Qed.

  Lemma gsoThreadR_suspendF:
    forall tp tp' i j (cnt: containsThread tp i) (cntj: containsThread tp j)
      (cntj': containsThread tp' j)
      (Hsuspend: FineConc.suspend_thread cnt tp'),
      getThreadR cntj = getThreadR cntj'.
  Proof.
    intros. inversion Hsuspend. subst.
      by erewrite @gThreadCR with (cntj := cntj).
  Qed.
  
  Lemma suspendC_invariant:
    forall tp tp' i
      (pff: containsThread tp i)
      (Hinv: invariant tp)
      (Hsuspend: DryConc.suspend_thread pff tp'),
      invariant tp'.
  Proof.
    intros.
    inversion Hsuspend; subst.
      by apply updThreadC_invariant.
  Qed.
  
  Lemma suspendF_invariant:
    forall tp tp' i
      (pff: containsThread tp i)
      (Hinv: invariant tp)
      (Hsuspend: FineConc.suspend_thread pff tp'),
      invariant tp'.
  Proof.
    intros.
    inversion Hsuspend; subst.
      by apply updThreadC_invariant.
  Qed.

  Lemma suspendF_lockSet:
    forall tp tp' i
      (pff: containsThread tp i)
      (Hsuspend: FineConc.suspend_thread pff tp'),
      lockSet tp = lockSet tp'.
  Proof.
    intros.
    inversion Hsuspend; subst.
      by erewrite gsoThreadCLock.
  Qed.

  Lemma suspendF_lockRes:
    forall tp tp' i
      (pff: containsThread tp i)
      (Hsuspend: FineConc.suspend_thread pff tp'),
      lockRes tp = lockRes tp'.
  Proof.
    intros.
    inversion Hsuspend; subst.
    extensionality addr.
      by erewrite gsoThreadCLPool.
  Qed.

  Lemma suspendC_lockSet:
    forall tp tp' i
      (pff: containsThread tp i)
      (Hsuspend: DryConc.suspend_thread pff tp'),
      lockSet tp = lockSet tp'.
  Proof.
    intros.
    inversion Hsuspend; subst.
      by erewrite gsoThreadCLock.
  Qed.

  Lemma suspendC_lockPool :
    forall (tp tp' : thread_pool) (i : tid) (pfc : containsThread tp i)
      (Hsuspend: DryConc.suspend_thread pfc tp') addr,
      lockRes tp addr = lockRes tp' addr.
  Proof.
    intros. inversion Hsuspend; subst.
      by erewrite gsoThreadCLPool.
  Qed.
  
  Lemma suspendF_lockPool :
    forall (tp tp' : thread_pool) (i : tid) (pff : containsThread tp i)
      (Hsuspend: FineConc.suspend_thread pff tp') addr,
      lockRes tp addr = lockRes tp' addr.
  Proof.
    intros. inversion Hsuspend; subst.
      by erewrite gsoThreadCLPool.
  Qed.

  Lemma mem_compatible_setMaxPerm :
    forall tp m
      (Hcomp: mem_compatible tp m),
      mem_compatible tp (setMaxPerm m).
  Proof.
    intros tp m Hcomp.
    constructor;
      [intros i cnti b ofs | intros l pmap Hres b ofs |
       intros b ofs];
      rewrite getMaxPerm_correct;
      destruct (valid_block_dec m b) as [Hvalid | Hinvalid];
      try (
          erewrite setMaxPerm_MaxV by assumption; simpl;
          match goal with
          | [ |- match ?Expr with _ => _ end] =>
            destruct Expr
          end; constructor);
      try (
          erewrite setMaxPerm_MaxI by assumption;
          apply Mem.nextblock_noaccess with (ofs := ofs) (k := Max) in Hinvalid;
          destruct Hcomp as [Hltth Hlrp Hltls]);
      [specialize (Hltth _ cnti b ofs) | specialize ((Hlrp _ _ Hres) b ofs) 
       | specialize (Hltls b ofs)];
      rewrite getMaxPerm_correct in Hltth Hlrp Hltls;
      unfold permission_at in *;
      rewrite Hinvalid in Hltth Hlrp Hltls; simpl in *;
        by auto.
  Qed.

  Lemma mem_compatible_add:
    forall tp i (cnti: containsThread tp i) c pmap vf arg pmap2 m
      (Hcomp: mem_compatible
                (addThread
                   (updThread cnti c pmap) vf arg pmap2) m),
      mem_compatible (updThread cnti c pmap) m.
  Proof.
    intros.
    split.
    - intros j cntj.
      assert (cntj' := cntAdd vf arg pmap2 cntj).
      specialize (Hcomp _ cntj').
      erewrite gsoAddRes;
        by eauto.
    - intros l pmap' Hres.
      erewrite <- gsoAddLPool
      with (vf := vf) (arg := arg) (p := pmap2) in Hres;
        by pose proof ((compat_lp Hcomp _ Hres)).
    - erewrite <- gsoAddLock with (vf := vf) (arg := arg) (p := pmap2);
        by pose proof ((compat_ls Hcomp)).
  Qed.
  
  Lemma mem_compatible_remlock:
    forall tp m addr
      (Hinv: lr_valid (lockRes tp))
      (Hlock: lockRes tp addr)
      (Hcomp: mem_compatible tp m),
      mem_compatible (remLockSet tp addr) m.
  Proof.
    intros.
    constructor.
    - eapply Hcomp.
    - intros.
      destruct (EqDec_address addr l).
      subst. rewrite gsslockResRemLock in H. discriminate.
      rewrite gsolockResRemLock in H; auto.
      eapply Hcomp; eauto.
    - intros b' ofs'.
      destruct addr as [b ofs].
      destruct (Pos.eq_dec b b').
      + subst.
        destruct (Intv.In_dec ofs' (ofs, (ofs + lksize.LKSIZE)%Z)).
        rewrite gsslockSet_rem; auto.
        destruct ((getMaxPerm m) # b' ofs'); simpl; constructor.
        rewrite gsolockSet_rem2; auto.
        eapply (compat_ls Hcomp).
      + rewrite gsolockSet_rem1; auto.
        eapply (compat_ls Hcomp).
  Qed.

End StepLemmas.

(** ** Definition of internal steps *)
Module InternalSteps (SEM : Semantics) (SemAxioms: SemanticsAxioms SEM)
       (Machine : MachinesSig with Module SEM := SEM).

  Import SEM event_semantics SemAxioms.
  Import Machine DryMachine DryConc ThreadPool.

  Module CoreLanguage := CoreLanguage SEM SemAxioms.
  Module CoreLanguageDry := CoreLanguageDry SEM SemAxioms DryMachine.
  Module StepLemmas := StepLemmas SEM Machine.
  Import StepLemmas CoreLanguage CoreLanguageDry SCH.

  Section InternalSteps.
    Variable the_ge : G.
    
    Notation threadStep := (threadStep the_ge).
    Notation Sch := SCH.schedule.
    
    (** Internal steps are just thread coresteps or resume steps or
  start steps, they mimic fine-grained internal steps *)
    Definition internal_step {tid} {tp} m (cnt: containsThread tp tid)
               (Hcomp: mem_compatible tp m) tp' m' :=
      (exists ev, threadStep cnt Hcomp tp' m' ev) \/
      (DryConc.resume_thread cnt tp' /\ m = m') \/
      (DryConc.start_thread the_ge cnt tp' /\ m = m').

    (* For now we don't emit events from internal_execution*)
    (*NOTE: we will probably never need to do so*)
    Inductive internal_execution : Sch -> thread_pool -> mem ->
                                   thread_pool -> mem -> Prop :=
    | refl_exec : forall tp m,
        internal_execution empty tp m tp m
    | step_trans : forall tid U U' tp m tp' m' tp'' m''
                     (cnt: containsThread tp tid)
                     (HschedN: schedPeek U = Some tid)
                     (HschedS: schedSkip U = U')
                     (Hcomp: mem_compatible tp m)
                     (Hstep: internal_step cnt Hcomp tp' m')
                     (Htrans: internal_execution U' tp' m' tp'' m''),
        internal_execution U tp m tp'' m''.

    (** Lemmas about internal steps and internal executions *)
    Lemma internal_execution_trans :
      forall i U tp tp' tp'' m m' m'' (pf': containsThread tp' i)
        (Hcomp: mem_compatible tp' m')
        (Hstep: internal_step pf' Hcomp tp'' m'')
        (Hexec: internal_execution U tp m tp' m'),
        internal_execution (U ++ [:: i]) tp m tp'' m''.
    Proof.
      intros i U. induction U; intros.
      simpl in *.
      inversion Hexec; subst.
      econstructor; simpl; eauto. constructor.
      simpl in HschedN. discriminate.
      inversion Hexec. subst. simpl in *.
      econstructor; simpl; eauto.
    Qed.

    Lemma internal_step_det :
      forall tp tp' tp'' m m' m'' i
        (Hcnt: containsThread tp i)
        (Hcomp: mem_compatible tp m)
        (Hstep: internal_step Hcnt Hcomp tp' m')
        (Hstep': internal_step Hcnt Hcomp tp'' m''),
        tp' = tp'' /\ m' = m''.
    Proof.
      intros.
      destruct Hstep as [[? Htstep] | [[Htstep ?] | [Htstep ?]]],
                        Hstep' as [[? Htstep'] | [[Htstep' ?] | [Htstep' ?]]]; subst;
      inversion Htstep; inversion Htstep'; subst; pf_cleanup;
      rewrite Hcode in Hcode0; inversion Hcode0; subst.
      apply ev_step_ax1 in Hcorestep0.
      apply ev_step_ax1 in Hcorestep.
      assert (Heq: c' = c'0 /\ m' = m'')
        by (eapply corestep_det; eauto).
      destruct Heq; subst;
        by auto.
      rewrite Hafter_external in Hafter_external0;
        by inversion Hafter_external0.
      rewrite Hinitial in Hinitial0;
        by inversion Hinitial0.
    Qed.

    Ltac exec_induction base_case :=
      intros;
      match goal with
      | [xs : list _, i : nat, Hexec: internal_execution _ ?Tp ?M _ _ |- _] =>
        generalize dependent Tp; generalize dependent M;
        induction xs as [| x xs' IHxs]; intros;
        [ match goal with
          | [Hexec: internal_execution _ _ _ _ _ |- _] =>
            try (inversion Hexec; subst;
                   by pf_cleanup)
          end
        | match goal with
          | [Hexec: internal_execution _ _ _ _ _ |- _] =>
            simpl in Hexec;
              destruct (x == i) eqn:Heq;
              move/eqP:Heq=>Heq;
              try eauto;
              subst;
              try (inversion Hexec as [|? ? ? ? ? ? ? ? ? ?
                                          HschedN HschedS Hcomp ? Htrans]; subst;
                   simpl in Htrans;
                   simpl in HschedN; inversion HschedN; subst;
                   pf_cleanup;
                   specialize (IHxs _ _  Htrans);
                   rewrite <- IHxs;
                   erewrite base_case; eauto)
          end
        ]
      end. 

    Lemma containsThread_internal_step :
      forall tp m tp' m' tid0 tid
        (Hcnt0: containsThread tp tid0)
        (Hcomp: mem_compatible tp m)
        (Hstep: internal_step Hcnt0 Hcomp tp' m') 
        (Hcnt: containsThread tp tid),
        containsThread tp' tid.
    Proof.
      intros.
      inversion Hstep. destruct H.
      inversion H; subst.
      eapply corestep_containsThread; by eauto.
      destruct H as [[Htstep _] | [Htstep _]];
        inversion Htstep; subst;
        [by eapply cntUpdateC | by eapply cntUpdateC].
    Qed.
    
    Lemma containsThread_internal_execution :
      forall U tp m tp' m' i
        (Hexec: internal_execution U tp m tp' m'),
        containsThread tp i -> containsThread tp' i.
    Proof.
      intros U. induction U. intros.
      inversion Hexec; subst; simpl in *; auto; try discriminate.
      intros.
      inversion Hexec as [|tid0 U0 U0' ? ? tp0' m0' ? ?];
        subst. eapply containsThread_internal_step in Hstep; eauto.
    Qed.

    Lemma containsThread_internal_step' :
      forall tp m tp' m' i j
        (Hcnt0: containsThread tp j)
        (Hcomp: mem_compatible tp m)
        (Hstep: internal_step Hcnt0 Hcomp tp' m') 
        (Hcnt: containsThread tp' i),
        containsThread tp i.
    Proof.
      intros. inversion Hstep as [[? Htstep] | [[Htstep _] | [Htstep _]]];
        inversion Htstep; subst;
        [eapply corestep_containsThread'; eauto
        |  by eapply cntUpdateC'; eauto
        |  by eapply cntUpdateC'; eauto].
    Qed.

    Lemma containsThread_internal_execution' :
      forall U tp m tp' m' i
        (Hexec: internal_execution U tp m tp' m')
        (Hcnt: containsThread tp' i),
        containsThread tp i.
    Proof.
      intros U. induction U. intros.
      inversion Hexec; subst; simpl in *; auto; try discriminate.
      intros.
      inversion Hexec as [|tid0 U0 U0' ? ? tp0' m0' ? ?];
        subst. eapply containsThread_internal_step' in Hstep; eauto.
    Qed.

    Lemma dry_step_compatible :
      forall (tp tp' : thread_pool) m m' (i : nat) ev (pf : containsThread tp i)
        (Hcompatible: mem_compatible tp m)
        (Hdry: dry_step the_ge pf Hcompatible tp' m' ev),
        mem_compatible tp' m'.
    Proof.
      intros.
      inversion Hdry; subst; eapply corestep_compatible;
        by eauto.
    Qed.

    Corollary coarseResume_compatible :
      forall (tp tp' : thread_pool) m (i : nat) (pf : containsThread tp i)
        (Hcompatible: mem_compatible tp m)
        (Hresume: DryConc.resume_thread pf tp'),
        mem_compatible tp' m.
    Proof.
      intros.
      inversion Hresume; subst;
      eapply StepLemmas.updThreadC_compatible;
        by eauto.
    Qed.

    Corollary coarseStart_compatible :
      forall (tp tp' : thread_pool) m (i : nat) (pf : containsThread tp i)
        (Hcompatible: mem_compatible tp m)
        (Hstart: DryConc.start_thread the_ge pf tp'),
        mem_compatible tp' m.
    Proof.
      intros.
      inversion Hstart; subst;
      eapply StepLemmas.updThreadC_compatible;
        by eauto.
    Qed.
    
    Corollary internal_step_compatible :
      forall (tp tp' : thread_pool) m m' (i : nat) (pf : containsThread tp i)
        (Hcompatible: mem_compatible tp m)
        (Hstep: internal_step pf Hcompatible tp' m'),
        mem_compatible tp' m'.
    Proof.
      intros.
      destruct Hstep as [[? Hdry] | [[Hresume ?] | [Hstart ?]]];
        subst;
        [eapply dry_step_compatible
        | eapply coarseResume_compatible
        | eapply coarseStart_compatible]; 
          by eauto.
    Qed.
    
    Lemma internal_step_invariant:
      forall (tp tp' : thread_pool) m m' (i : nat) (pf : containsThread tp i)
        (Hcompatible: mem_compatible tp m)
        (Hstep: internal_step pf Hcompatible tp' m'),
        invariant tp'.
    Proof.
      intros.
      destruct Hstep as [[? Hdry] | Hsr].
      - inversion Hdry as [tp'0 c m1 m1' c']. subst m' tp'0 tp' ev.
        apply ev_step_ax1 in Hcorestep.
        eapply corestep_invariant; eauto.
      - destruct Hsr as [H1 | H1];
        destruct H1 as [H2 ?]; subst;
        inversion H2; subst;
          by apply StepLemmas.updThreadC_invariant.
    Qed.

    Lemma internal_execution_compatible :
      forall (tp tp' : thread_pool) m m' xs
        (Hcompatible: mem_compatible tp m)
        (Hstep: internal_execution xs tp m tp' m'),
        mem_compatible tp' m'.
    Proof.
      intros. induction Hstep. auto. subst.
      eapply IHHstep; eauto.
      eapply internal_step_compatible; eauto.
    Qed.

    Lemma internal_execution_invariant :
      forall (tp tp' : thread_pool) m m' xs
        (Hcompatible: mem_compatible tp m)
        (Hinv: invariant tp)
        (Hstep: internal_execution xs tp m tp' m'),
        invariant tp'.
    Proof.
      intros. induction Hstep. auto. subst.
      eapply IHHstep; eauto.
      eapply internal_step_compatible; eauto.
      eapply internal_step_invariant; eauto.
    Qed.
    
    Lemma gsoThreadC_step:
      forall tp tp' m m' i j (pfi: containsThread tp i)
        (pfj: containsThread tp j)
        (pfj': containsThread tp' j)
        (Hcomp: mem_compatible tp m)
        (Hstep: internal_step pfi Hcomp tp' m')
        (Hneq: i <> j),
        getThreadC pfj = getThreadC pfj'.
    Proof.
      intros. destruct Hstep as [[? Hstep] | [[Hstep Heq] | [Hstep Heq]]];
        inversion Hstep; subst;
        [erewrite <- gsoThreadCode with (cntj' := pfj')
          by eauto
        |
        erewrite gsoThreadCC with (cntj' := pfj')
          by eauto
        |
        erewrite gsoThreadCC with (cntj' := pfj')
          by eauto];
        reflexivity.
    Qed.

    Lemma gsoThreadC_exec:
      forall tp m tp' m' i j xs
        (pfj: containsThread tp j)
        (pfj': containsThread tp' j)
        (Hstep: internal_execution [seq x <- xs | x == i] tp m tp' m')
        (Hneq: i <> j),
        getThreadC pfj = getThreadC pfj'.
    Proof.
      intros. generalize dependent tp. generalize dependent m.
      induction xs; intros.
      - simpl in Hstep. inversion Hstep; subst. by pf_cleanup.
        simpl in HschedN. by discriminate.
      - simpl in Hstep.
        destruct (a == i) eqn:Heq; move/eqP:Heq=>Heq.
        + subst a. inversion Hstep; subst.
          simpl in Htrans.
          assert (pfj'0: containsThread tp'0 j)
            by (eapply containsThread_internal_step; eauto).
          specialize (IHxs _ _  pfj'0 Htrans).
          rewrite <- IHxs.
          erewrite gsoThreadC_step; eauto.
          simpl in HschedN. inversion HschedN; subst.
          assumption.
        + eauto.
    Qed.

    Lemma gsoThreadR_step:
      forall tp tp' m m' i j (pfi: containsThread tp i)
        (pfj: containsThread tp j)
        (pfj': containsThread tp' j)
        (Hcomp: mem_compatible tp m)
        (Hstep: internal_step pfi Hcomp tp' m')
        (Hneq: i <> j),
        getThreadR pfj = getThreadR pfj'.
    Proof.
      intros. destruct Hstep as [[? Hstep] | [[Hstep Heq] | [Hstep Heq]]];
        inversion Hstep; subst;
        [erewrite <- @gsoThreadRes with (cntj' := pfj') |
         erewrite <- @gThreadCR with (cntj' := pfj')
         | erewrite <- @gThreadCR with (cntj' := pfj')];
          by eauto.
    Qed.
    
    Corollary permission_at_step:
      forall tp tp' m m' i j
        (Hneq: i <> j)
        (pfi: containsThread tp i)
        (pfj: containsThread tp j)
        (pfj': containsThread tp' j)
        (Hcomp: mem_compatible tp m)
        (Hcomp': mem_compatible tp' m')
        (Hstep: internal_step pfi Hcomp tp' m') b ofs,
        permission_at (restrPermMap (Hcomp _ pfj)) b ofs Cur =
        permission_at (restrPermMap (Hcomp' _ pfj')) b ofs Cur.
    Proof.
      intros.
      do 2 rewrite restrPermMap_Cur.
      erewrite @gsoThreadR_step;
        by eauto.
    Qed.

    Lemma gsoThreadR_execution:
      forall tp m tp' m' i j xs
        (pfj: containsThread tp j)
        (pfj': containsThread tp' j)
        (Hneq: i <> j)
        (Hstep: internal_execution [seq x <- xs | x == i] tp m tp' m'),
        getThreadR pfj = getThreadR pfj'.
    Proof.
      intros. generalize dependent tp. generalize dependent m.
      induction xs; intros.
      - simpl in Hstep. inversion Hstep; subst. by pf_cleanup.
        simpl in HschedN. by discriminate.
      - simpl in Hstep.
        destruct (a == i) eqn:Heq; move/eqP:Heq=>Heq.
        + subst a. inversion Hstep; subst.
          simpl in Htrans.
          simpl in HschedN; inversion HschedN; subst tid.
          pf_cleanup.
          assert (pfj'0: containsThread tp'0 j)
            by (eapply containsThread_internal_step; eauto).
          specialize (IHxs _ _  pfj'0 Htrans).
          rewrite <- IHxs.
          erewrite gsoThreadR_step; eauto.
        + eauto.
    Qed.

    Lemma gsoLockSet_step:
      forall tp tp' m m' i (pfi: containsThread tp i)
        (Hcomp: mem_compatible tp m)
        (Hstep: internal_step pfi Hcomp tp' m'),
        lockSet tp = lockSet tp'.
    Proof.
      intros;
      destruct Hstep as [[? Htstep] | [[Htstep ?] | [Htstep ?]]];
      inversion Htstep;
      subst;
      [erewrite gsoThreadLock |
       erewrite gsoThreadCLock |
       erewrite gsoThreadCLock];
        by reflexivity.
    Qed.

    Lemma gsoLockSet_execution:
      forall tp m tp' m' i xs
        (Hstep: internal_execution [seq x <- xs | x == i] tp m tp' m'),
        lockSet tp = lockSet tp'.
    Proof.
      intros. generalize dependent tp. generalize dependent m.
      induction xs; intros.
      - simpl in Hstep. inversion Hstep; subst. by pf_cleanup.
        simpl in HschedN. by discriminate.
      - simpl in Hstep.
        destruct (a == i) eqn:Heq; move/eqP:Heq=>Heq; try eauto.
        subst a. inversion Hstep; subst.
        simpl in Htrans.
        simpl in HschedN; inversion HschedN; subst tid.
        pf_cleanup.
        specialize (IHxs _ _  Htrans).
        rewrite <- IHxs.
        erewrite gsoLockSet_step; eauto.
    Qed.
      
    Lemma gsoLockPool_step:
      forall tp tp' m m' i (pfi: containsThread tp i)
        (Hcomp: mem_compatible tp m)
        (Hstep: internal_step pfi Hcomp tp' m') addr,
        lockRes tp addr = lockRes tp' addr.
    Proof.
      intros;
      destruct Hstep as [[? Htstep] | [[Htstep ?] | [Htstep ?]]];
      inversion Htstep;
      subst;
      [erewrite gsoThreadLPool |
       erewrite gsoThreadCLPool |
       erewrite gsoThreadCLPool];
        by reflexivity.
    Qed.

    Lemma gsoLockPool_execution :
      forall (tp : thread_pool) (m : mem) (tp' : thread_pool) 
        (m' : mem) (i : nat) (xs : seq nat_eqType)
        (Hexec: internal_execution [seq x <- xs | x == i] tp m tp' m')
        addr,
        lockRes tp addr = lockRes tp' addr.
    Proof.
      intros. generalize dependent tp. generalize dependent m.
      induction xs; intros.
      - simpl in Hexec. inversion Hexec; subst. by pf_cleanup.
        simpl in HschedN. by discriminate.
      - simpl in Hexec.
        destruct (a == i) eqn:Heq; move/eqP:Heq=>Heq; try eauto.
        subst a. inversion Hexec; subst.
        simpl in Htrans.
        simpl in HschedN; inversion HschedN; subst tid.
        pf_cleanup.
        specialize (IHxs _ _  Htrans).
        rewrite <- IHxs.
        erewrite gsoLockPool_step; eauto.
    Qed.

      
    Lemma permission_at_execution:
      forall tp m tp' m' i j xs
        (pfi: containsThread tp i)
        (pfj: containsThread tp j)
        (pfj': containsThread tp' j)
        (Hneq: i <> j)
        (Hcomp: mem_compatible tp m)
        (Hcomp': mem_compatible tp' m')
        (Hstep: internal_execution [seq x <- xs | x == i] tp m tp' m'),
      forall b ofs,
        permission_at (restrPermMap (Hcomp _ pfj)) b ofs Cur =
        permission_at (restrPermMap (Hcomp' _ pfj')) b ofs Cur.
    Proof.
      intros.
      do 2 rewrite restrPermMap_Cur.
      erewrite gsoThreadR_execution; eauto.
    Qed.
    
    Lemma internal_step_disjoint_val :
      forall tp tp' m m' i j
        (Hneq: i <> j)
        (pfi: containsThread tp i)
        (pfj: containsThread tp j)
        (Hcomp: mem_compatible tp m)
        (Hcomp': mem_compatible tp' m')
        (Hstep: internal_step pfi Hcomp tp' m') b ofs
        (Hreadable: 
           Mem.perm (restrPermMap (Hcomp _ pfj)) b ofs Cur Readable),
        Maps.ZMap.get ofs (Mem.mem_contents m) # b =
        Maps.ZMap.get ofs (Mem.mem_contents m') # b.
    Proof.
      intros.
      inversion Hstep as [[? Htstep] | [[Htstep Heq] | [Htstep Heq]]]; subst; auto.
      inversion Htstep; subst; eapply ev_step_ax1 in Hcorestep;
      eapply corestep_disjoint_val;
        by eauto.
    Qed.
    
    Lemma internal_exec_disjoint_val :
      forall tp tp' m m' i j xs
        (Hneq: i <> j)
        (pfi: containsThread tp i)
        (pfj: containsThread tp j)
        (Hcomp: mem_compatible tp m)
        (Hstep: internal_execution [seq x <- xs | x == i] tp m tp' m') b ofs
        (Hreadable: 
           Mem.perm (restrPermMap (Hcomp _ pfj)) b ofs Cur Readable),
        Maps.ZMap.get ofs (Mem.mem_contents m) # b =
        Maps.ZMap.get ofs (Mem.mem_contents m') # b.
    Proof.
      intros.
      generalize dependent tp.  generalize dependent m.
      induction xs as [|x xs]; intros.
      - simpl in Hstep; inversion Hstep; subst.
        reflexivity.
        simpl in HschedN. by discriminate.
      - simpl in Hstep.
        destruct (x == i) eqn:Heq; move/eqP:Heq=>Heq.
        + subst x.
          inversion Hstep; subst.
          simpl in Htrans.
          simpl in HschedN.
          inversion HschedN; subst tid.
          pf_cleanup.
          assert (pfj0': containsThread tp'0 j) by
              (eapply containsThread_internal_step; eauto).
          assert (pfi0': containsThread tp'0 i) by
              (eapply containsThread_internal_step; eauto).
          assert(Hcomp0': mem_compatible tp'0 m'0) by
              (eapply internal_step_compatible; eauto).
          assert (Hreadable0':
                    Mem.perm (restrPermMap (Hcomp0' j pfj0')) b ofs Cur Readable).
          { clear IHxs Htrans HschedN Hstep.
            assert (Hperm_eq :=
                      permission_at_step Hneq  pfj pfj0' Hcomp0' Hstep0 b ofs).
            do 2 rewrite restrPermMap_Cur in Hperm_eq.
            unfold Mem.perm in *.
            assert (H1:= restrPermMap_Cur (Hcomp0' j pfj0') b ofs).
            unfold permission_at in H1.
            rewrite H1. rewrite <- Hperm_eq.
            assert (H2:= restrPermMap_Cur (Hcomp j pfj) b ofs).
            unfold permission_at in H2.
            rewrite H2 in Hreadable. assumption.
          }
          specialize (IHxs _ _  pfi0' pfj0' Hcomp0' Htrans Hreadable0').
          rewrite <- IHxs.
          eapply internal_step_disjoint_val; eauto.
        + by eauto.
    Qed.

    Lemma internal_step_disjoint_val_lock :
      forall tp tp' m m' i 
        (pfi: containsThread tp i)
        (Hcomp: mem_compatible tp m)
        (Hcomp': mem_compatible tp' m')
        (Hstep: internal_step pfi Hcomp tp' m') b ofs
        (Hreadable: 
           Mem.perm (restrPermMap (compat_ls Hcomp)) b ofs Cur Readable),
        Maps.ZMap.get ofs (Mem.mem_contents m) # b =
        Maps.ZMap.get ofs (Mem.mem_contents m') # b.
    Proof.
      intros.
      inversion Hstep as [[? Hcstep] | [[Hrstep Heq] | [Hsstep Heq]]]; subst; auto.
      inversion Hcstep; subst;
      eapply ev_step_ax1 in Hcorestep;
      eapply corestep_disjoint_val_lockset;
        by eauto.
    Qed.
    
    Lemma internal_exec_disjoint_val_lock :
      forall tp tp' m m' i xs
        (pfi: containsThread tp i)
        (Hcomp: mem_compatible tp m)
        (Hstep: internal_execution [seq x <- xs | x == i] tp m tp' m') b ofs
        (Hreadable: 
           Mem.perm (restrPermMap (compat_ls Hcomp)) b ofs Cur Readable),
        Maps.ZMap.get ofs (Mem.mem_contents m) # b =
        Maps.ZMap.get ofs (Mem.mem_contents m') # b.
    Proof.
      intros.
      generalize dependent tp.  generalize dependent m.
      induction xs as [|x xs]; intros.
      - simpl in Hstep; inversion Hstep; subst.
        reflexivity.
        simpl in HschedN. by discriminate.
      - simpl in Hstep.
        destruct (x == i) eqn:Heq; move/eqP:Heq=>Heq.
        + subst x.
          inversion Hstep; subst.
          simpl in Htrans.
          simpl in HschedN.
          inversion HschedN; subst tid.
          pf_cleanup.
          assert (pfi0': containsThread tp'0 i) by
              (eapply containsThread_internal_step; eauto).
          assert(Hcomp0': mem_compatible tp'0 m'0) by
              (eapply internal_step_compatible; eauto).
          assert (Hreadable0':
                    Mem.perm (restrPermMap (compat_ls Hcomp0')) b ofs Cur Readable).
          { clear IHxs Htrans HschedN Hstep.
            assert (Hperm_eq :=
                      gsoLockSet_step Hstep0).
            unfold Mem.perm in *.
            assert (H1:= restrPermMap_Cur (compat_ls Hcomp0') b ofs).
            unfold permission_at in H1.
            rewrite H1.
            rewrite <- Hperm_eq.
            assert (H2:= restrPermMap_Cur (compat_ls Hcomp) b ofs).
            unfold permission_at in H2.
              by rewrite H2 in Hreadable.
          }
          specialize (IHxs _ _  pfi0' Hcomp0' Htrans Hreadable0').
          rewrite <- IHxs.
          eapply internal_step_disjoint_val_lock; eauto.
        + by eauto.
    Qed.
    
    Lemma internal_step_decay:
      forall tp m tp' m' i (cnt: containsThread tp i)
        (cnt': containsThread tp' i)
        (Hcomp: mem_compatible tp m)
        (Hcomp': mem_compatible tp' m')
        (Hstep: internal_step cnt Hcomp tp' m'),
        decay (restrPermMap (Hcomp _ cnt))
              (restrPermMap (Hcomp' _ cnt')).
    Proof.
      intros. unfold decay. intros b ofs.
      assert (HpermCur: permission_at
                       (restrPermMap (Hcomp' _ cnt')) b ofs Cur =
                     (getThreadR cnt') # b ofs)
        by (eapply restrPermMap_Cur; eauto).
      assert (HpermMax: permission_at
                          (restrPermMap (Hcomp' _ cnt')) b ofs Max =
                        (Mem.mem_access m') # b ofs Max)
        by (erewrite restrPermMap_Max;
             erewrite getMaxPerm_correct;
               by unfold permission_at).
      unfold permission_at in *.
      destruct Hstep as [[? Hcstep] | [[Hresume ?] | [Hstart ?]]]; subst.
      - inversion Hcstep. subst.
        apply ev_step_ax1 in Hcorestep.
        eapply corestep_decay in Hcorestep.
        destruct (Hcorestep b ofs).
        split.
        + intros.
          erewrite restrPermMap_valid in H2.
          assert (Hpmap: getThreadR cnt' = getCurPerm m')
            by (by rewrite gssThreadRes).
          specialize (H H1 H2).
          destruct H as [H | H];
            [left | right]; intros k;
            specialize (H k);
            destruct k;
            try (rewrite HpermMax);
            try (rewrite HpermCur); auto;
          try (rewrite Hpmap;
               rewrite getCurPerm_correct;
               unfold permission_at;
                 by assumption).
        + intros Hvalid.
          specialize (H0 Hvalid).
          destruct H0 as [H0 | H0];
            [left | right];
            intros k;
            specialize (H0 k);
            [destruct H0 | idtac];
            destruct k;
            try rewrite HpermMax;
            try rewrite HpermCur;
            try split;
            auto;
          try rewrite gssThreadRes;
          try rewrite getCurPerm_correct;
          unfold permission_at;
            by assumption.
      - inversion Hresume; subst.
        assert (Hpmap: getThreadR cnt' = getThreadR cnt)
          by (apply gThreadCR).
        assert (H: forall k,
                   (Mem.mem_access (restrPermMap (Hcomp' i cnt'))) # b ofs k =
                   (Mem.mem_access (restrPermMap (Hcomp i cnt))) # b ofs k).
        { intros k.
          destruct k.
          rewrite HpermMax.
          assert (H := restrPermMap_Max (Hcomp i cnt) b ofs).
          rewrite getMaxPerm_correct in H.
          unfold permission_at in H;
            by rewrite H.
          rewrite HpermCur.
          rewrite Hpmap.
          assert (H := restrPermMap_Cur (Hcomp i cnt) b ofs).
          unfold permission_at in H;
            by rewrite H. }
        split.
        intros.
        right.
        intros k.
        apply Mem.nextblock_noaccess with (ofs := ofs)
                                            (k := k) in H0.
        specialize (H k).
        rewrite H;
          by assumption.
        intros; auto.
      - inversion Hstart; subst.
        assert (Hpmap: getThreadR cnt' = getThreadR cnt)
          by (apply gThreadCR).
        assert (H: forall k,
                   (Mem.mem_access (restrPermMap (Hcomp' i cnt'))) # b ofs k =
                   (Mem.mem_access (restrPermMap (Hcomp i cnt))) # b ofs k).
        { intros k.
          destruct k.
          rewrite HpermMax.
          assert (H := restrPermMap_Max (Hcomp i cnt) b ofs).
          rewrite getMaxPerm_correct in H.
          unfold permission_at in H;
            by rewrite H.
          rewrite HpermCur.
          rewrite Hpmap.
          assert (H := restrPermMap_Cur (Hcomp i cnt) b ofs).
          unfold permission_at in H;
            by rewrite H. }
        split.
        intros.
        right.
        intros k.
        apply Mem.nextblock_noaccess with (ofs := ofs)
                                            (k := k) in H0.
        specialize (H k).
        rewrite H;
          by assumption.
        intros; auto.
    Qed.     
                                                         
    Lemma internal_step_valid:
      forall tp m tp' m' i (cnt: containsThread tp i)
        (Hcomp: mem_compatible tp m)
        (Hstep: internal_step cnt Hcomp tp' m') b
        (Hvalid: Mem.valid_block m b),
        Mem.valid_block m' b.
    Proof.
      intros.
      destruct Hstep as [[? Htstep] | [[_ ?] | [_ ?]]];
        [inversion Htstep; subst;
         eapply ev_step_validblock;
           by eauto | by subst | by subst].
    Qed.

    Lemma internal_execution_valid :
      forall tp m tp' m' xs
        (Hexec: internal_execution xs tp m tp' m') b
        (Hvalid: Mem.valid_block m b),
        Mem.valid_block m' b.
    Proof.
      intros.
      generalize dependent tp. generalize dependent m.
      induction xs as [|x xs]; intros.
      inversion Hexec; subst; first by assumption.
      simpl in HschedN;
        by discriminate.
      inversion Hexec; subst.
      simpl in HschedN. inversion HschedN; subst.
      simpl in Htrans.
      assert (Hvalid0: Mem.valid_block m'0 b)
        by (eapply internal_step_valid; eauto).
        by eauto.
    Qed.
 
    Lemma internal_execution_decay:
      forall tp m tp' m' xs i (cnt: containsThread tp i)
        (cnt': containsThread tp' i)
        (Hcomp: mem_compatible tp m)
        (Hcomp': mem_compatible tp' m')
        (Hexec: internal_execution [seq x <- xs | x == i] tp m tp' m'),
        decay (restrPermMap (Hcomp _ cnt))
              (restrPermMap (Hcomp' _ cnt')).
    Proof.
      intros tp m tp' m' xs.
      generalize dependent tp. generalize dependent m.
      induction xs.
      - intros. simpl in Hexec. inversion Hexec; subst.
        pf_cleanup.
          by apply decay_refl.
        simpl in HschedN. discriminate.
      - intros.
        destruct (a == i) eqn:Heq; move/eqP:Heq=>Heq; subst.
        + simpl in Hexec.
          erewrite if_true in Hexec by (apply eq_refl).
          inversion Hexec; subst; simpl in *.
          inversion HschedN; subst tid.
          assert (Hcomp'0: mem_compatible tp'0 m'0)
            by (eapply internal_step_compatible; eauto).
          assert (cnt0': containsThread tp'0 i)
            by (eapply containsThread_internal_step; eauto).
          pf_cleanup.
          eapply IHxs with
          (Hcomp := Hcomp'0) (Hcomp' := Hcomp')
                             (cnt := cnt0') (cnt' := cnt') in Htrans.
          assert (Hdecay:
                    decay (restrPermMap (Hcomp _ cnt))
                          (restrPermMap (Hcomp'0 _ cnt0')))
            by (eapply internal_step_decay; eauto).
          eapply decay_trans with (m' := restrPermMap (Hcomp'0 i cnt0'));
            eauto.
          intros.
          erewrite restrPermMap_valid.
          eapply internal_step_valid;
            by eauto.

        + simpl in Hexec.
          erewrite if_false in Hexec
            by (apply/eqP; assumption).
          auto.
    Qed.

    Lemma internal_step_disjoint_val_lockPool :
      forall tp tp' m m' i bl ofsl pmap
        (pfi: containsThread tp i)
        (Hcomp: mem_compatible tp m)
        (Hcomp': mem_compatible tp' m')
        (Hstep: internal_step pfi Hcomp tp' m') b ofs
        (Hl: lockRes tp (bl,ofsl) = Some pmap)
        (Hreadable: Mem.perm (restrPermMap (compat_lp Hcomp _ Hl))
                             b ofs Cur Readable),
        Maps.ZMap.get ofs (Mem.mem_contents m) # b =
        Maps.ZMap.get ofs (Mem.mem_contents m') # b.
    Proof.
      intros.
      inversion Hstep as [[? Hcstep] | [[Hrstep Heq] | [Hsstep Heq]]]; subst; auto.
      inversion Hcstep; subst; eapply ev_step_ax1 in Hcorestep;
      eapply corestep_disjoint_val_lockpool;
        by eauto.
    Qed.
    
    Lemma internal_exec_disjoint_val_lockPool:
      forall (tp tp' : thread_pool) (m m' : mem) (i : tid) xs bl ofsl pmap
        (Hcomp : mem_compatible tp m)
        (Hexec: internal_execution [seq x <- xs | x == i] tp m tp' m')
        (Hl: lockRes tp (bl,ofsl) = Some pmap)
        b ofs
        (Hreadable: Mem.perm (restrPermMap (compat_lp Hcomp _ Hl)) b ofs Cur Readable),
        Maps.ZMap.get ofs (Mem.mem_contents m) # b =
        Maps.ZMap.get ofs (Mem.mem_contents m') # b.
    Proof.
      intros.
      generalize dependent tp.  generalize dependent m.
      induction xs as [|x xs]; intros.
      - simpl in Hexec; inversion Hexec; subst.
        reflexivity.
        simpl in HschedN. by discriminate.
      - simpl in Hexec.
        destruct (x == i) eqn:Heq; move/eqP:Heq=>Heq.
        + subst x.
          inversion Hexec; subst.
          simpl in Htrans.
          simpl in HschedN.
          inversion HschedN; subst tid.
          pf_cleanup.
          assert (pfi0': containsThread tp'0 i) by
              (eapply containsThread_internal_step; eauto).
          assert(Hcomp0': mem_compatible tp'0 m'0) by
              (eapply internal_step_compatible; eauto).
          assert (Hl0': lockRes tp'0 (bl, ofsl) = Some pmap)
            by (erewrite <- gsoLockPool_step; eauto).
          assert (Hreadable0':
                    Mem.perm (restrPermMap (compat_lp Hcomp0' _ Hl0'))
                             b ofs Cur Readable).
          { clear IHxs Htrans HschedN.
            unfold Mem.perm in *.
            assert (H1:= restrPermMap_Cur (compat_lp Hcomp0' _ Hl0') b ofs).
            unfold permission_at in H1.
            rewrite H1.
            assert (H2:= restrPermMap_Cur (compat_lp Hcomp _ Hl) b ofs).
            unfold permission_at in H2.
              by rewrite H2 in Hreadable.
          }
          specialize (IHxs _ _  Hcomp0' Htrans Hl0' Hreadable0').
          rewrite <- IHxs.
          eapply internal_step_disjoint_val_lockPool; eauto.
        + by eauto.
    Qed.

    Lemma updThread_internal_step:
      forall tp tp' m m' i j c pmap
        (Hneq: i <> j)
        (cnti: containsThread tp i)
        (cnti': containsThread tp' i)
        (cntj: containsThread tp j)
        (cntj': containsThread (updThread cnti c pmap) j)
        (Hcomp: mem_compatible tp m)
        (Hcomp': mem_compatible (updThread cnti c pmap) m)
        (Hinv': invariant (updThread cnti c pmap))
        (Hstep: internal_step cntj Hcomp tp' m'),
        internal_step cntj' Hcomp' (updThread cnti' c pmap) m'.
    Proof.
      intros.
      inversion Hstep as [[? ?] | [[? ?] | [? ?]]].
      - inversion H; subst.
        left.
        exists x.
        eapply step_dry with (c := c0) (c' := c'); eauto.
        erewrite gsoThreadCode; eauto.
        erewrite <- restrPermMap_irr' with (Hlt' := Hcomp' j cntj') (Hlt := Hcomp j cntj);
          eauto.
        erewrite @gsoThreadRes with (cntj := cntj); eauto.
        rewrite updThread_comm; auto.
      - subst.
        inversion H; subst.
        right. left.
        split; auto.
        econstructor; eauto.
        erewrite @gsoThreadCode with (cntj := cntj); eauto.
        pf_cleanup. auto.
        rewrite updThread_updThreadC_comm; auto.
      - subst.
        inversion H; subst.
        do 2 right.
        split; auto.
        econstructor; eauto.
        erewrite @gsoThreadCode with (cntj := cntj); eauto.
        pf_cleanup. auto.
        rewrite updThread_updThreadC_comm; auto.
    Qed.
        
    
    Lemma updThread_internal_execution:
      forall tp tp' m m' i j xs c pmap
        (cnti: containsThread tp i)
        (cnti': containsThread tp' i)
        (Hinv: invariant (updThread cnti c pmap))
        (Hcomp' : mem_compatible (updThread cnti c pmap) m)
        (Hneq: i <> j)
        (Hexec: internal_execution [seq x <- xs | x == j] tp m tp' m'),
        internal_execution [seq x <- xs | x == j] (updThread cnti c pmap) m
                           (updThread cnti' c pmap) m'.
    Proof.
      intros.
      generalize dependent m.
      generalize dependent tp.
      induction xs; intros.
      - simpl in *.
        inversion Hexec; subst;
        first by constructor.
        simpl in HschedN;
          by discriminate.
      - simpl in *.
        destruct (a == j) eqn:Heq; move/eqP:Heq=>Heq.
        subst a.
        inversion Hexec; subst.
        simpl in HschedN. inversion HschedN; subst tid.
        assert (cntj' := cntUpdate c pmap cnti cnt).
        assert (cnti0' := containsThread_internal_step Hstep cnti).
        eapply updThread_internal_step
        with (cntj' := cntj') (cnti' := cnti0') (Hcomp' := Hcomp') in Hstep; eauto.
        specialize (IHxs tp'0 _
                         ltac:(eapply internal_step_invariant; eauto)
                                m'0
                                ltac:(eapply (internal_step_compatible);
                                       eauto) Htrans).
        econstructor;
          by eauto.
        eauto.
    Qed.

    Lemma addThread_internal_step:
      forall tp tp' m m' i vf arg pmap
        (cnti: containsThread tp i)
        (cnti': containsThread (addThread tp vf arg pmap) i)
        (Hcomp: mem_compatible tp m)
        (Hcomp': mem_compatible (addThread tp vf arg pmap) m)
        (Hinv': invariant (addThread tp vf arg pmap))
        (Hstep: internal_step cnti Hcomp tp' m'),
        internal_step cnti' Hcomp' (addThread tp' vf arg pmap) m'.
    Proof.
      intros.
      destruct Hstep as [[? Htstep] | [Hresume | Hinit]].
      - inversion Htstep; subst tp'0 m'0.
        left.
        exists x.
        eapply step_dry with (c := c) (c' := c'); eauto.
        erewrite gsoAddCode with (cntj := cnti); eauto.
        subst.
        erewrite restrPermMap_irr' with (Hlt' := Hcomp i cnti); eauto.
        erewrite gsoAddRes with (cntj := cnti); eauto.
        subst.
          by rewrite add_update_comm.
      - destruct Hresume as [Hresume ?]; subst.
        inversion Hresume; subst.
        right; left.
        split; auto.
        econstructor; eauto.
        erewrite gsoAddCode with (cntj := ctn); eauto.            
          by rewrite add_updateC_comm.
      - destruct Hinit; subst.
        right; right.
        split; auto.
        inversion H; subst.
        econstructor; eauto.
        erewrite gsoAddCode; eauto.
          by rewrite add_updateC_comm.
    Qed.

    
    Lemma addThread_internal_execution:
      forall tp tp' m m' i j xs vf arg pmap
        (Hneq: i <> j)
        (Hinv': invariant (addThread tp vf arg pmap))
        (Hcomp': mem_compatible (addThread tp vf arg pmap) m)
        (Hexec: internal_execution [seq x <- xs | x == j] tp m tp' m'),
        internal_execution [seq x <- xs | x == j]
                           (addThread tp vf arg pmap) m
                           (addThread tp' vf arg pmap) m'.
    Proof.
      intros.
      generalize dependent m.
      generalize dependent tp.
      induction xs; intros.
      - simpl in *.
        inversion Hexec; subst;
        first by constructor.
        simpl in HschedN;
          by discriminate.
      - simpl in *.
        destruct (a == j) eqn:Heq; move/eqP:Heq=>Heq.
        subst a.
        inversion Hexec; subst.
        simpl in HschedN. inversion HschedN; subst tid.
        assert (cnt':= cntAdd vf arg pmap cnt).
        eapply addThread_internal_step
        with (cnti' := cnt') (Hcomp' := Hcomp') in Hstep; eauto.
        specialize (IHxs tp'0
                         ltac:(eapply internal_step_invariant; eauto)
                                m'0
                                ltac:(eapply (internal_step_compatible);
                                       eauto) Htrans).
        econstructor;
          by eauto.
        eauto.
    Qed.

    Lemma remLock_internal_step:
      forall tp tp' m m' j (cntj: containsThread tp j) b ofs
        (Hcomp: mem_compatible tp m)
        (Hcomp': mem_compatible (remLockSet tp (b,ofs)) m)
        (cntj': containsThread (remLockSet tp (b,ofs)) j)
        (Hstep: internal_step cntj Hcomp tp' m'),
        internal_step cntj' Hcomp' (remLockSet tp' (b,ofs)) m'.
    Proof.
      intros.
      inversion Hstep as [[? ?] | [[? ?] | [? ?]]].
      - inversion H; subst.
        left.
        exists x.
        eapply step_dry with (c := c) (c' := c'); eauto.
        eapply DryMachineLemmas.remLock_inv; eauto.
        rewrite gRemLockSetCode.
        auto.
        erewrite <- restrPermMap_irr' with (Hlt' := Hcomp' j cntj') (Hlt := Hcomp j cntj);
          eauto.
        rewrite gRemLockSetRes; auto.
      - subst.
        inversion H; subst.
        right. left.
        split; auto.
        econstructor; eauto.
        rewrite gRemLockSetCode; auto.
        eapply DryMachineLemmas.remLock_inv; eauto.
      - subst.
        inversion H; subst.
        do 2 right.
        split; auto.
        econstructor; eauto.
        rewrite gRemLockSetCode; auto.
        eapply DryMachineLemmas.remLock_inv; eauto.
    Qed.
    
    Lemma remLock_internal_execution:
      forall tp tp' m m' j xs b ofs
        (Hcomp': mem_compatible (remLockSet tp (b,ofs)) m)
        (Hexec: internal_execution [seq x <- xs | x == j] tp m tp' m'),
        internal_execution [seq x <- xs | x == j] (remLockSet tp (b, ofs)) m
                           (remLockSet tp' (b,ofs)) m'.
    Proof.
      intros.
      generalize dependent m.
      generalize dependent tp.
      induction xs; intros.
      - simpl in *.
        inversion Hexec; subst;
        first by constructor.
        simpl in HschedN;
          by discriminate.
      - simpl in *.
        destruct (a == j) eqn:Heq; move/eqP:Heq=>Heq.
        subst a.
        inversion Hexec; subst.
        simpl in HschedN. inversion HschedN; subst tid.
        assert (cntj' := cntRemoveL (b, ofs) cnt).
        eapply remLock_internal_step
        with (cntj' := cntj') (Hcomp' := Hcomp') in Hstep; eauto.
        specialize (IHxs tp'0 _
                         ltac:(eapply (internal_step_compatible);
                                eauto) Htrans).
        econstructor;
          by eauto.
        eauto.
    Qed.

    Lemma internal_step_nextblock:
      forall tp m tp' m' i (cnti: containsThread tp i)
        (Hcomp: mem_compatible tp m)
        (Hstep: internal_step cnti Hcomp tp' m'),
        (Mem.nextblock m <= Mem.nextblock m')%positive.
    Proof.
      intros.
      destruct Hstep as [[? H] | [[? ?] | [? ?]]]; subst.
      inversion H; subst.
      eapply ev_step_nextblock in Hcorestep;
        by rewrite restrPermMap_nextblock in Hcorestep.
      apply Pos.le_refl.
      apply Pos.le_refl.
    Qed.
     
    Lemma internal_execution_nextblock:
      forall tp m tp' m' xs
        (Hexec: internal_execution xs tp m tp' m'),
        (Mem.nextblock m <= Mem.nextblock m')%positive.
    Proof.
      intros.
      generalize dependent m.
      generalize dependent tp.
      induction xs; intros; inversion Hexec; subst;
      first by apply Pos.le_refl.
      simpl in HschedN. discriminate.
      simpl in *.
      inversion HschedN; subst.
      specialize (IHxs _ _ Htrans).
      eapply Pos.le_trans.
      eapply internal_step_nextblock; eauto.
      eauto.
    Qed.
    
  End InternalSteps.
End InternalSteps.

Module StepType (SEM : Semantics)
       (SemAxioms: SemanticsAxioms SEM)
       (Machine : MachinesSig with Module SEM := SEM)
       (AsmContext : AsmContext SEM Machine ).

  Import AsmContext Machine DryMachine ThreadPool.
  Import SEM event_semantics SemAxioms. 

  Module StepLemmas := StepLemmas SEM Machine.
  Module CoreLanguageDry := CoreLanguageDry SEM SemAxioms DryMachine.
  Module InternalSteps := InternalSteps SEM SemAxioms Machine.
  Import CoreLanguageDry InternalSteps StepLemmas event_semantics.
   (** Distinguishing the various step types of the concurrent machine *)

  Inductive StepType : Type :=
    Internal | Concurrent | Halted | Suspend.

  Definition ctlType (code : ctl) : StepType :=
    match code with
    | Kinit _ _ => Internal
    | Krun c =>
      match at_external Sem c with
      | None => 
        match halted Sem c with
        | Some _ => Halted
        | None => Internal
        end
      | Some _ => Suspend
      end
    | Kblocked c => Concurrent
    | Kresume c _ => Internal
    end.
  
  Definition getStepType {i tp} (cnt : containsThread tp i) : StepType :=
    ctlType (getThreadC cnt).

  Global Notation "cnt '@'  'I'" := (getStepType cnt = Internal) (at level 80).
  Global Notation "cnt '@'  'E'" := (getStepType cnt = Concurrent) (at level 80).
  Global Notation "cnt '@'  'S'" := (getStepType cnt = Suspend) (at level 80).
  Global Notation "cnt '@'  'H'" := (getStepType cnt = Halted) (at level 80).

  (** Solves absurd cases from fine-grained internal steps *)
  Global Ltac absurd_internal Hstep :=
    inversion Hstep; try inversion Htstep; subst; simpl in *;
    try match goal with
        | [H: Some _ = Some _ |- _] => inversion H; subst
        end; pf_cleanup;
    repeat match goal with
           | [H: getThreadC ?Pf = _, Hint: ?Pf @ I |- _] =>
             unfold getStepType in Hint;
               rewrite H in Hint; simpl in Hint
           | [H1: match ?Expr with _ => _ end = _,
                  H2: ?Expr = _ |- _] => rewrite H2 in H1
           | [H: threadHalted _ |- _] =>
             inversion H; clear H; subst; simpl in *; pf_cleanup;
             unfold  ThreadPool.SEM.Sem in *
           | [H1: is_true (isSome (halted ?Sem ?C)),
                  H2: match at_external _ _ with _ => _ end = _ |- _] =>
             destruct (at_external_halted_excl Sem C) as [Hext | Hcontra];
               [rewrite Hext in H2;
                 destruct (halted Sem C) eqn:Hh;
                 [discriminate | by exfalso] |
                rewrite Hcontra in H1; by exfalso]
           end; try discriminate; try (exfalso; by auto).
  
  
  Section StepType.
    Variable ge : G.
  Lemma internal_step_type :
    forall  i tp tp' m m' (cnt : containsThread tp i)
      (Hcomp: mem_compatible tp m)
      (Hstep_internal: internal_step ge cnt Hcomp tp' m'),
      cnt @ I.
  Proof.
    intros.
    unfold getStepType, ctlType.
    destruct Hstep_internal as [[? Hcstep] | [[Hresume Heq] | [Hstart Heq]]].
    inversion Hcstep. subst. rewrite Hcode.
    apply ev_step_ax1 in Hcorestep.
    assert (H1:= corestep_not_at_external Sem _ _ _ _ _ Hcorestep).
    rewrite H1.
    assert (H2:= corestep_not_halted Sem _ _ _ _ _ Hcorestep);
      by rewrite H2.
    inversion Hresume; subst.
    pf_cleanup;
      by rewrite Hcode.
    inversion Hstart; subst.
    pf_cleanup;
      by rewrite Hcode.
  Qed.

  Lemma internal_step_result_type:
    forall tp m tp' m' i (cnti: containsThread tp i)
      (cnti': containsThread tp' i)
      (Hcomp: mem_compatible tp m)
      (Hinternal: internal_step ge cnti Hcomp tp' m'),
      ~ (cnti' @ E).
  Proof.
    intros. intro Hcontra.
    destruct Hinternal as [[? Htstep] | [[Htstep ?] | [Htstep ?]]]; subst;
    inversion Htstep; subst;
    unfold getStepType in Hcontra;
    try rewrite gssThreadCode in Hcontra;
    try rewrite gssThreadCC in Hcontra; unfold ctlType in Hcontra;
    repeat match goal with
           | [H: match ?Expr with _ => _ end = _ |- _] =>
             destruct Expr
           end; discriminate.
  Qed.

  Lemma internal_execution_result_type:
    forall tp m tp' m' i xs
      (cnti': containsThread tp' i)
      (Hin: List.In i xs)
      (Hexec: internal_execution ge [seq x <- xs | x == i] tp m tp' m'),
      ~ (cnti' @ E).
  Proof.
    intros.
    generalize dependent m.
    generalize dependent tp.
    induction xs; intros.
    - simpl in *.
      inversion Hexec; subst.
      by exfalso.
      simpl in HschedN;
        by discriminate.
    - destruct (a == i) eqn:Hia; move/eqP:Hia=>Hia.
      subst a.
      simpl in *.
      erewrite if_true in Hexec by apply eq_refl.
      inversion Hexec; subst.
      simpl in HschedN. inversion HschedN; subst tid.
      simpl in Htrans.
      destruct (List.In_dec (eq_dec.nat_eq_dec) i xs).
      eauto.
      rewrite not_in_filter in Htrans; auto.
      inversion Htrans; subst.
      eapply internal_step_result_type; eauto.
      simpl in HschedN0; discriminate.
      destruct Hin; first by (exfalso; auto).
      simpl in Hexec.
      erewrite if_false in Hexec.
      eauto.
      move/eqP:Hia; auto.
  Qed.
      
  (** Proofs about [fmachine_step]*)
  Notation fmachine_step := ((corestep fine_semantics) ge).
  
  Lemma fstep_containsThread :
    forall tp tp' m m' i j U tr tr'
      (cntj: containsThread tp j)
      (Hstep: fmachine_step (i :: U, tr, tp) m (U, tr', tp') m'),
      containsThread tp' j.
  Proof.
    intros.
    inversion Hstep; subst; try inversion Htstep;
    simpl in *; try inversion HschedN;
    subst; auto;
    repeat match goal with
           | [ |- containsThread (updThreadC _ _) _] =>
             apply cntUpdateC; auto
           | [ |- containsThread (updThread _ _ _) _] =>
             apply cntUpdate; auto
           | [ |- containsThread (updThreadR _ _) _] =>
             apply cntUpdateR; auto
           | [ |- containsThread (addThread _ _ _ _) _] =>
             apply cntAdd; auto
           end.
  Qed.

  Lemma fstep_containsThread' :
    forall tp tp' m m' i j U tr tr'
      (cnti: containsThread tp i)
      (cntj: containsThread tp' j)
      (Hinternal: cnti @ I)
      (Hstep: fmachine_step (i :: U, tr, tp) m (U, tr', tp') m'),
      containsThread tp j.
  Proof.
    intros.
    absurd_internal Hstep;
      by eauto.
  Qed.

  Lemma fmachine_step_invariant:
    forall (tp tp' : thread_pool) m m' (i : nat) (pf : containsThread tp i) U tr tr'
      (Hcompatible: mem_compatible tp m)
      (Hinternal: pf @ I)
      (Hstep: fmachine_step (i :: U, tr, tp) m (U, tr', tp') m'),
      invariant tp'.
  Proof.
    intros.
    absurd_internal Hstep.
    - apply updThreadC_invariant; auto.
    - apply updThreadC_invariant; auto.
    - eapply ev_step_ax1 in Hcorestep.
      eapply corestep_invariant;
        by eauto.   
  Qed.

  Lemma fmachine_step_compatible:
    forall (tp tp' : thread_pool) m m' (i : nat) (pf : containsThread tp i) U tr tr'
      (Hcompatible: mem_compatible tp m)
      (Hinternal: pf @ I)
      (Hstep: fmachine_step (i :: U,tr, tp) m (U, tr',tp') m'),
      mem_compatible tp' m'.
  Proof.
    intros.
    absurd_internal Hstep;
      try (eapply updThreadC_compatible;
             by eauto).
    eapply mem_compatible_setMaxPerm.
    eapply corestep_compatible;
      by eauto.
    (* this holds trivially, we don't need to use corestep_compatible*)
  Qed.

  Lemma gsoThreadR_fstep:
    forall tp tp' m m' i j U tr tr'
      (Hneq: i <> j)
      (pfi: containsThread tp i)
      (pfj: containsThread tp j)
      (pfj': containsThread tp' j)
      (Hinternal: pfi @ I)
      (Hstep: fmachine_step (i :: U,tr, tp) m (U,tr', tp') m'),
      getThreadR pfj = getThreadR pfj'.
  Proof.
    intros.
    absurd_internal Hstep;
      try (by rewrite <- gThreadCR with (cntj' := pfj'));
      erewrite <- @gsoThreadRes with (cntj' := pfj');
        by eauto.
  Qed.

  Lemma permission_at_fstep:
    forall tp tp' m m' i j U tr tr'
      (Hneq: i <> j)
      (pfi: containsThread tp i)
      (pfj: containsThread tp j)
      (pfj': containsThread tp' j)
      (Hcomp: mem_compatible tp m)
      (Hcomp': mem_compatible tp' m')
      (Hinv: pfi @ I)
      (Hstep: fmachine_step (i :: U, tr, tp) m (U,tr',tp') m') b ofs,
      permission_at (restrPermMap (Hcomp _ pfj)) b ofs Cur =
      permission_at (restrPermMap (Hcomp' _ pfj')) b ofs Cur.
  Proof.
    intros.
    do 2 rewrite restrPermMap_Cur;
      erewrite gsoThreadR_fstep;
        by eauto.
  Qed.

  Lemma gsoThreadC_fstepI:
    forall tp tp' m m' i j U tr tr'
      (pfj: containsThread tp j)
      (pfj': containsThread tp' j)
      (pfi: containsThread tp i)
      (Hinternal: pfi @ I)
      (Hstep: fmachine_step (i :: U, tr, tp) m (U, tr', tp') m')
      (Hneq: i <> j),
      getThreadC pfj = getThreadC pfj'.
  Proof.
    intros.
    absurd_internal Hstep;
      try (erewrite gsoThreadCC with (cntj' := pfj');
             by eauto);
      erewrite gsoThreadCode with (cntj' := pfj');
        by eauto.
  Qed.

  Lemma gsoLockSet_fstepI:
    forall tp tp' m m' i U tr tr'
      (pfi: containsThread tp i)
      (Hinternal: pfi @ I)
      (Hstep: fmachine_step (i :: U, tr, tp) m (U, tr', tp') m'),
      lockSet tp = lockSet tp'.
  Proof.
    intros.
    absurd_internal Hstep;
      try (erewrite gsoThreadCLock;
             by eauto);
      erewrite gsoThreadLock;
        by eauto.
  Qed.

  Lemma gsoLockRes_fstepI :
    forall (tp tp' : thread_pool) (m m' : mem) (i : tid) tr tr'
      (U : seq tid) (pfi : containsThread tp i)
      (Hinternal: pfi @ I)
      (Hstep: fmachine_step (i :: U,tr, tp) m (U, tr', tp') m'),
      lockRes tp' = lockRes tp.
  Proof.
    intros.
    absurd_internal Hstep;
      extensionality addr;
      try (by rewrite gsoThreadCLPool);
      try (by rewrite gsoThreadLPool).
  Qed.
  
  Lemma fmachine_step_disjoint_val :
    forall tp tp' m m' i j U tr tr'
      (Hneq: i <> j)
      (pfi: containsThread tp i)
      (pfj: containsThread tp j)
      (pfj': containsThread tp' j)
      (Hcomp: mem_compatible tp m)
      (Hcomp': mem_compatible tp' m')
      (Hinv: pfi @ I)
      (Hstep: fmachine_step (i :: U, tr, tp) m (U,tr', tp') m') b ofs
      (Hreadable: 
         Mem.perm (restrPermMap (Hcomp _ pfj)) b ofs Cur Readable),
      Maps.ZMap.get ofs (Mem.mem_contents m) # b =
      Maps.ZMap.get ofs (Mem.mem_contents m') # b.
  Proof.
    intros.
    absurd_internal Hstep;
      try reflexivity;
    apply ev_step_ax1 in Hcorestep;
      eapply corestep_disjoint_val;
        by eauto.
  Qed.

  Lemma diluteMem_valid :
    forall b m,
      Mem.valid_block m b <-> Mem.valid_block (diluteMem m) b.
  Proof.
    intros.
    split; auto.
  Qed.
  
  Lemma fstep_valid_block:
    forall tpf tpf' mf mf' i U b tr tr'
      (Hvalid: Mem.valid_block mf b)
      (Hstep: fmachine_step (i :: U, tr, tpf) mf (U, tr',tpf') mf'),
      Mem.valid_block mf' b.
  Proof.
    intros.
    inversion Hstep; subst; auto.
    inversion Htstep; subst.
    erewrite <- diluteMem_valid.
    eapply CoreLanguage.ev_step_validblock; eauto.
    inversion Htstep; subst; eauto.
    eapply Mem.store_valid_block_1; eauto.
    eapply Mem.store_valid_block_1; eauto.
    eapply Mem.store_valid_block_1; eauto.
  Qed.
  
  End StepType.

  Hint Resolve fmachine_step_compatible fmachine_step_invariant
       fstep_containsThread fstep_containsThread' gsoLockSet_fstepI : fstep.

  Hint Rewrite gsoThreadR_fstep permission_at_fstep : fstep.
  
End StepType.