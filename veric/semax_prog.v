Require Import veric.juicy_base.
Require Import veric.juicy_mem veric.juicy_mem_lemmas veric.juicy_mem_ops.
Require Import veric.res_predicates.
Require Import veric.extend_tc.
Require Import veric.seplog.
Require Import veric.assert_lemmas.
Require Import veric.Clight_new.
Require Import sepcomp.extspec.
Require Import sepcomp.step_lemmas.
Require Import veric.juicy_extspec.
Require Import veric.tycontext.
Require Import veric.expr2.
Require Import veric.expr_lemmas.
Require Import veric.semax.
Require Import veric.semax_lemmas.
Require Import veric.Clight_lemmas.
Require Import veric.initial_world.
Require Import msl.normalize.
Require Import veric.semax_call.
Require Import veric.initial_world.
Require Import veric.initialize.
Require Import veric.coqlib4.

Open Local Scope pred.

Fixpoint match_globvars (gvs: list (ident * globvar type)) (V: varspecs) : bool :=
 match V with
 | nil => true 
 | (id,t)::V' => match gvs with 
                       | nil => false
                       | (j,g)::gvs' => if eqb_ident id j 
                                              then andb (is_pointer_type t) 
                                                       (andb (eqb_type t (gvar_info g)) (match_globvars gvs' V'))
                                              else match_globvars gvs' V
                      end
  end.

Section semax_prog.
Context (Espec: OracleKind).

Definition prog_contains (ge: genv) (fdecs : list (ident * fundef)) : Prop :=
     forall id f, In (id,f) fdecs -> 
         exists b, Genv.find_symbol ge id = Some b /\ Genv.find_funct_ptr ge b = Some f.

Definition entry_tempenv (te: temp_env) (f: function) (vl: list val) :=
   length vl = length f.(fn_params) /\
   forall id v, PTree.get id te = Some v ->  
                      In (id,v) 
                       (combine (map (@fst _ _) f.(fn_params)) vl 
                          ++ map (fun tv => (fst tv, Vundef)) f.(fn_temps)).

Definition semax_body_params_ok f : bool :=
   andb 
        (compute_list_norepet (map (@fst _ _) (fn_params f) ++ map (@fst _ _) (fn_temps f)))
        (compute_list_norepet (map (@fst _ _) (fn_vars f))).

Definition semax_body
       (V: varspecs) (G: funspecs) {C: compspecs} (f: function) (spec: ident * funspec) : Prop :=
  match spec with (_, mk_funspec _ cc A P Q) =>
    forall Espec x,
      semax Espec (func_tycontext f V G)
          (fun rho => P x rho * stackframe_of f rho)
           (Ssequence f.(fn_body) (Sreturn None))
          (frame_ret_assert (function_body_ret_assert (fn_return f) (Q x)) (stackframe_of f))
 end.

Definition semax_func
         (V: varspecs) (G: funspecs) {C: compspecs} (fdecs: list (ident * fundef)) (G1: funspecs) : Prop :=
   match_fdecs fdecs G1 /\
  forall ge, prog_contains ge fdecs -> 
          genv_cenv ge = cenv_cs ->
          forall n, believe Espec (nofunc_tycontext V G) ge (nofunc_tycontext V G1) n.

Definition main_pre (prog: program) : unit -> assert :=
(fun tt => globvars2pred (prog_vars prog)).

Definition Tint32s := Tint I32 Signed noattr.

Definition main_post (prog: program) : unit -> assert := 
  (fun tt _ => TT).

Definition is_Internal (prog : program) (f : ident) :=
  match Genv.find_symbol (Genv.globalenv prog) f with
    None => false
  | Some b =>
    match Genv.find_funct_ptr (Genv.globalenv prog) b with
    | None => false
    | Some f =>
      match f with
      | External _ _ _ _ => false
      | Internal _ => true
      end
    end
  end.

Definition semax_prog {C: compspecs}
           (prog: program)  (V: varspecs) (G: funspecs) : Prop :=
  compute_list_norepet (prog_defs_names prog) = true  /\
  all_initializers_aligned prog /\
  cenv_cs = prog_comp_env prog /\
  @semax_func V G C (prog_funct prog) G /\
  match_globvars (prog_vars prog) V = true /\
  In (prog.(prog_main), mk_funspec (nil,Tvoid) cc_default unit (main_pre prog ) (main_post prog)) G /\
  is_Internal prog (prog_main prog) = true.

Lemma semax_func_nil: 
   forall
     V G {C: compspecs}, semax_func V G nil nil.
Proof.
intros; split; auto.
constructor.
intros. rename H0 into HGG.
intros b fsig cc ty P Q w ? ?.
hnf in H1.
destruct H1 as [b' [? ?]].
simpl in H1.
rewrite PTree.gempty in H1. inv H1. 
Qed.

Program Definition HO_pred_eq {T}{agT: ageable T}
    (A: Type) (P: A -> pred T) (A': Type) (P': A' -> pred T) : pred nat :=
 fun v => exists H: A=A', 
     match H in (_ = A) return (A -> pred T) -> Prop with
     | refl_equal => fun (u3: A -> pred T) =>
                                    forall x: A, (P x <=> u3 x) v
     end P'.
 Next Obligation.
  intros; intro; intros.
  destruct H0. exists x.
  destruct x. 
   intros. specialize (H0 x). eapply pred_hereditary; eauto.
 Qed.

Lemma approx_oo_approx'':
   forall n n' : nat,
  (n' >= n)%nat ->
    approx n' oo approx n = approx n.
Proof.
intros.
extensionality P.
apply pred_ext'; extensionality w.
unfold approx, compose.
simpl. rewrite rmap_level_eq.
case_eq (unsquash w); intros; simpl in *.
apply prop_ext; intuition.
Qed.

Lemma laterR_level: forall w w' : rmap, laterR w w' -> (level w > level w')%nat.
Proof.
induction 1.
unfold age in H. rewrite <- ageN1 in H.
change rmap with R.rmap; change ag_rmap with R.ag_rmap.
rewrite (ageN_level _ _ _ H). generalize (@level _ R.ag_rmap y). intros; omega.
omega.
Qed.

Lemma necR_level:  forall w w' : rmap, necR w w' -> (level w >= level w')%nat.
Proof.
induction 1.
unfold age in H. rewrite <- ageN1 in H.
change rmap with R.rmap; change ag_rmap with R.ag_rmap.
rewrite (ageN_level _ _ _ H). generalize (@level _ R.ag_rmap y). intros; omega.
omega.
omega.
Qed.

Lemma HO_pred_eq_i1:
  forall A P P' m, 
      approx (level m) oo  P = approx (level m) oo P' ->
    (|> HO_pred_eq A P A  P') m.
Proof.
intros.
unfold HO_pred_eq.
intros ?m ?.
hnf.
exists (refl_equal A).
intros.
generalize (f_equal (fun f => f x) H); clear H; intro.
simpl in H0.
unfold compose in *.
apply clos_trans_t1n in H0.
revert H; induction H0; intros.
Focus 2. apply IHclos_trans_1n.
unfold age,age1 in H. unfold ag_nat in H. unfold natAge1 in H. destruct x0; inv H.
clear - H1.
assert (forall w, app_pred (approx (level (S y)) (P x)) w <-> app_pred (approx (level (S y)) (P' x)) w).
intros; rewrite H1; intuition.
apply pred_ext; intros w ?; destruct (H w); simpl in *; intuition.
apply H0; auto. clear - H4.  unfold natLevel in *. omega.
apply H2; auto. clear - H4.  unfold natLevel in *. omega.
(* End Focus 2 *)
unfold age,age1 in H. unfold ag_nat in H. unfold natAge1 in H. destruct x0; inv H.
intros z ?.
split; intros ? ? ?.
assert (app_pred (approx (level (S y)) (P x)) a').
simpl. split; auto. unfold natLevel.  apply necR_level in H1.
change compcert_rmaps.R.rmap with rmap in *.
change compcert_rmaps.R.ag_rmap with ag_rmap in *.
omega.
rewrite H0 in H3.
simpl in H3. destruct H3; auto.
assert (app_pred (approx (level (S y)) (P' x)) a').
simpl. split; auto. unfold natLevel.  apply necR_level in H1.
change compcert_rmaps.R.rmap with rmap in *.
change compcert_rmaps.R.ag_rmap with ag_rmap in *.
omega.
rewrite <- H0 in H3.
simpl in H3. destruct H3; auto.
Qed.

Require Import Coq.Logic.JMeq.

Lemma semax_func_cons_aux:
  forall (psi: genv) id fsig1 cc1 A1 P1 Q1 fsig2 cc2 A2 P2 Q2 (V: varspecs) (G': funspecs) {C: compspecs} b fs,
  Genv.find_symbol psi id = Some b ->
  ~ In id (map (fst (A:=ident) (B:=fundef)) fs) ->
   match_fdecs fs G'  ->
   claims  psi (nofunc_tycontext V ((id, mk_funspec fsig1 cc1 A1 P1 Q1) :: G')) (Vptr b Int.zero) fsig2 cc2 A2 P2 Q2 ->
    fsig1=fsig2 /\ cc1 = cc2 /\ A1=A2 /\ JMeq P1 P2 /\ JMeq Q1 Q2.
Proof.
intros until fs. intros H Hin Hmf; intros.
destruct H0 as [id' [? ?]].
simpl in H0.
destruct (eq_dec id id').
subst id'. rewrite PTree.gss in H0. inv H0.
apply inj_pair2 in H6. apply inj_pair2 in H7.
subst.
split; auto.
rewrite PTree.gso in H0 by auto.
elimtype False.
destruct H1 as [b' [? ?]].
symmetry in H2; inv H2.
assert (In id' (map (@fst _ _) G')).
clear - H0.
revert H0; induction G'; simpl; intros; auto.
rewrite PTree.gempty in H0; inv H0.
destruct (eq_dec id' (fst a)). subst. rewrite PTree.gss in H0 by auto. inv  H0.
auto.
destruct a; simpl in *.
destruct (eq_dec i id'). subst. rewrite PTree.gss in H0. auto.
rewrite PTree.gso in H0 by auto.
right; apply IHG'; auto.
destruct (eq_dec id id').
2: apply (Genv.global_addresses_distinct psi n H H1); auto.
subst id'.
clear - Hin H2 Hmf.
eapply match_fdecs_in in Hmf; eauto.
Qed.

Lemma semax_func_cons: 
   forall 
         fs id f cc A P Q (V: varspecs) (G G': funspecs) {C: compspecs},
      andb (id_in_list id (map (@fst _ _) G)) 
      (andb (negb (id_in_list id (map (@fst ident fundef) fs)))
        (semax_body_params_ok f)) = true ->
      Forall
         (fun it : ident * type =>
          complete_type cenv_cs (snd it) =
          true) (fn_vars f) ->
       var_sizes_ok cenv_cs (f.(fn_vars)) ->
       f.(fn_callconv) = cc ->
       precondition_closed f P ->
      semax_body V G f (id, mk_funspec (fn_funsig f) cc A P Q) ->
      semax_func V G fs G' ->
      semax_func V G ((id, Internal f)::fs) 
           ((id, mk_funspec (fn_funsig f) cc A P Q)  :: G').
Proof.
intros until C.
intros H' COMPLETE Hvars Hcc Hpclos H3 [Hf' Hf].
apply andb_true_iff in H'.
destruct H' as [Hin H'].
apply andb_true_iff in H'.
destruct H' as [Hni H].
split.
simpl. constructor 2; auto.
simpl.
unfold type_of_function. f_equal. auto.
intros ge H0 HGG n.
assert (prog_contains ge fs).
unfold prog_contains in *.
intros.
apply H0.
simpl.
auto.
spec Hf ge H1 HGG.
clear H1.
hnf in Hf|-*.
intros v fsig cc' A' P' Q'.
apply derives_imp.
clear n.
intros n ?.
subst cc.
spec H0 id (Internal f).
destruct H0 as [b [? ?]].
left; auto.
rewrite <- Genv.find_funct_find_funct_ptr in H2.
apply negb_true_iff in Hni.
apply id_in_list_false in Hni.
destruct (eq_dec  (Vptr b Int.zero) v) as [?H|?H].
* (* Vptr b Int.zero = v *)
subst v.
right.
exists b; exists f.
split; auto.
apply andb_true_iff in H.
destruct H as [H H'].
apply compute_list_norepet_e in H.
apply compute_list_norepet_e in H'.
split3; auto.
rewrite Genv.find_funct_find_funct_ptr in H2; auto.
split; auto.
rewrite HGG; auto.
split; auto.
split; auto.
split.
rewrite HGG; auto.
(* split; auto.*)
destruct H1 as [id' [? [b' [? ?]]]].
symmetry in H5; inv H5.
destruct (eq_dec id id').
subst.
simpl in H1.
rewrite PTree.gss in H1.
inv H1; auto.
contradiction (Genv.global_addresses_distinct ge n0 H0 H4); auto.
(*destruct H. *)
intro x.
simpl in H1.
pose proof (semax_func_cons_aux ge _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ H0 Hni Hf' H1).
destruct H4 as [H4' [H4 [H4a [H4b H4c]]]].
subst A' fsig cc'.
apply JMeq_eq in H4b.
apply JMeq_eq in H4c.
subst P' Q'.
specialize (H3 Espec x).
rename H3 into H4.
pose proof I.
specialize (H4 n).
apply now_later.
rewrite HGG.
clear - Hpclos H4.
rewrite semax_fold_unfold in H4|-*.
revert n H4.
apply allp_derives; intro gx.
apply allp_derives; intro Delta'.
apply imp_derives; auto.
apply imp_derives; auto.
apply allp_derives; intro k.
apply allp_derives; intro F.
apply imp_derives; auto.
unfold guard.
apply allp_derives; intro tx.
eapply allp_derives; intro vx.
eapply subp_derives; auto.
apply andp_derives; auto.
apply andp_derives; auto.
apply sepcon_derives; auto.
apply andp_left1; auto.
apply sepcon_derives; auto.
unfold bind_args.
apply andp_left2; auto.
destruct (Hpclos x).
apply close_precondition_e; auto.
* (***   Vptr b Int.zero <> v'  ********)
apply (Hf n v fsig cc' A' P' Q'); auto.
destruct H1 as [id' [? ?]].
simpl in H1.
destruct (eq_dec id id').
subst. rewrite PTree.gss in H1.
destruct H5 as [? [? ?]]. congruence.
rewrite PTree.gso in H1 by auto.
exists id'; split; auto.
Qed.

(* EXPERIMENT 
Lemma semax_func_skip: 
   forall 
        V (G: funspecs) {C: compspecs} fs idf (G': funspecs),
      semax_func V G fs G' ->
      semax_func V G (idf::fs) G'.
Proof.
 intros.
 hnf in H|-*.
 destruct H; split.
 constructor 3. auto.
 intros.
 eapply H0; eauto.
 hnf in H1|-*.
 intros; eapply H1; eauto.
 right; auto.
Qed.
*)

Lemma semax_external_FF:
 forall Espec ids ef A n, 
  @semax_external Espec ids ef A (fun _ _ => FF) (fun _ _ => FF) n.
intros.
hnf; intros.
simpl.
intros.
destruct H2 as [? [? [? [? ?]]]].
contradiction.
Qed.

Lemma semax_func_cons_ext: 
   forall (V: varspecs) (G: funspecs) {C: compspecs} fs id ef argsig retsig A P Q 
          argsig'
          (G': funspecs) cc (ids: list ident),
      ids = map fst argsig' -> (* redundant but useful for the client,
               to calculate ids by reflexivity *)
      argsig' = zip_with_tl ids argsig ->
      id_in_list id (map (@fst _ _) fs) = false ->
      length ids = length (typelist2list argsig) ->
      (forall gx (x: A) (ret : option val),
         (Q x (make_ext_rval gx ret) |-- !!tc_option_val retsig ret)) ->
      (forall n, semax_external Espec ids ef A P Q n) ->
      semax_func V G fs G' ->
      semax_func V G ((id, External ef argsig retsig cc)::fs) 
           ((id, mk_funspec (argsig', retsig) cc A P Q)  :: G').
Proof.
intros until ids.
intros Hids Hargsig Hni Hlen Hretty H [Hf' Hf].
rewrite Hargsig in *.  clear Hids Hargsig argsig'.
apply id_in_list_false in Hni.
split.
hnf; simpl; f_equal; auto.
constructor 2. simpl.
f_equal.
clear -Hlen.
revert ids Hlen; induction argsig; simpl; intros; auto.
destruct ids; auto.
destruct ids; auto. inv Hlen. simpl. f_equal; auto.
auto.
intros ge ? HGG; intros.
assert (prog_contains ge fs).
unfold prog_contains in *.
intros.
apply H0.
simpl.
auto.
specialize (Hf ge H1 HGG).
clear H1.
unfold believe.
intros v' fsig' cc' A' P' Q'.
apply derives_imp.
clear n.
intros n ?.
unfold prog_contains in H0.
generalize (H0 id (External ef argsig retsig cc)); clear H0; intro H0.
destruct H0 as [b [? ?]].
left; auto.
rewrite <- Genv.find_funct_find_funct_ptr in H2.
destruct (eq_dec  (Vptr b Int.zero) v') as [?H|?H].
subst v'.
left.
specialize (H n).
pose proof (semax_func_cons_aux ge _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ H0 Hni Hf' H1).
destruct H3 as [H4' [H4'' [H4 [H4b H4c]]]].
subst A' fsig' cc'.
apply JMeq_eq in H4b.
apply JMeq_eq in H4c.
subst P' Q'.
unfold believe_external.
rewrite H2.
assert (Hty: map fst (zip_with_tl ids argsig) = ids). 
{ clear -Hlen. revert argsig Hlen. induction ids; auto.
  simpl; intros. destruct argsig; auto. inv Hlen. 
  simpl. f_equal. auto. }
rewrite fst_split. simpl map. rewrite Hty.
split; auto.
split; auto. split; auto.
intros x ret phi Hlev Hx Hnec. apply Hretty.

(* **   Vptr b Int.zero <> v'  ********)
apply (Hf n v' fsig' cc' A' P' Q'); auto.
destruct H1 as [id' [? ?]].
simpl in H1.
destruct (eq_dec id id').
subst. rewrite PTree.gss in H1. inv H1.
destruct H4 as [? [? ?]]; congruence.
exists id'; split; auto.
simpl. rewrite PTree.gso in H1 by auto; auto.
Qed.

Definition main_params (ge: genv) start : Prop :=
  exists b, exists func,
    Genv.find_symbol ge start = Some b /\
        Genv.find_funct ge (Vptr b Int.zero) = Some (Internal func) /\
        func.(fn_params) = nil.

Lemma in_prog_funct'_in {F V}:
  forall i f (g: list (ident * globdef F V)), In (i,f) (prog_funct' g) -> In (i, Gfun f) g.
Proof.
induction g; intros. inv H. simpl in *. 
destruct a; destruct g0. simpl in H. destruct H; auto. left; congruence.
right; auto.
Qed.

Lemma in_prog_funct_in_prog_defs:
  forall i f prog, In (i,f) (prog_funct prog) -> In (i, Gfun f) (prog_defs prog).
Proof.
 intros; apply in_prog_funct'_in; auto.
Qed.

Lemma in_prog_vars_in_prog_defs:
  forall i v prog, In (i,v) (prog_vars prog) -> In (i, Gvar v) (prog_defs prog).
Proof.
unfold prog_vars. intros ? ? ?.
induction (prog_defs prog); intros. inv H. simpl in *. 
destruct a; destruct g. auto. simpl in H. destruct H; auto. left; congruence.
Qed.

Lemma find_funct_ptr_exists:
  forall (p: program) id f,
  list_norepet (prog_defs_names p) ->
  In (id, Gfun f) (prog_defs p) ->
  exists b,
     Genv.find_symbol (Genv.globalenv p) id = Some b
  /\ Genv.find_funct_ptr (Genv.globalenv p) b = Some f.
Proof.
intros.
pose proof (prog_defmap_norepet _ _ _ H H0).
destruct (proj1 (Genv.find_def_symbol _ _ _) H1) 
  as [b [? ?]].
exists b; split; auto.
unfold Genv.find_funct_ptr.
rewrite H3.
auto.
Qed.

Lemma funassert_initial_core:
  forall (prog: program) ve te V G {C: compspecs} n, 
      list_norepet (prog_defs_names prog) ->
      match_fdecs (prog_funct prog) G ->
      app_pred (funassert (nofunc_tycontext V G) (mkEnviron (filter_genv (globalenv prog)) ve te))
                      (initial_core (Genv.globalenv prog) G n).
Proof.
 intros; split.
*
 intros id fs.
 apply prop_imp_i; intros.
 simpl ge_of; simpl fst; simpl snd.
 unfold filter_genv.
 assert (exists f, In (id, f) (prog_funct prog)). {
 simpl in H1.
 forget (prog_funct prog) as g.
clear - H1 H0.
revert G H1 H0; induction g; destruct G; intros; simpl in *.
elimtype False.
rewrite PTree.gempty in H1; inv H1.
inv H0.
destruct a; simpl in *; subst.
destruct (eq_dec i id). subst; eauto.
 specialize (IHg nil H1). inv H0.
(*destruct (IHg). destruct g; simpl; auto.
constructor. apply match_fdecs_nil.
eauto. *)
destruct a. destruct p.
 inv H0.
 simpl in H1.
 destruct (ident_eq i0 id). subst. eauto.
 destruct (IHg G); auto. rewrite PTree.gso in H1; auto.
 eauto.
(* simpl in H1. 
 destruct (IHg ((i0,f0)::G)); auto. eauto.
*)
 }
 destruct H2 as [f ?].
 destruct (find_funct_ptr_exists prog id f) as [b [? ?]]; auto.
 apply in_prog_funct_in_prog_defs; auto.
 exists b. unfold fundef.
 unfold globalenv. simpl. rewrite H3.
 split; auto.
 unfold func_at. destruct fs as [f0 cc0 A a a0].
 unfold initial_core.
 hnf. rewrite resource_at_make_rmap.
 rewrite level_make_rmap.
 unfold initial_core'.
 simpl.
 rewrite (Genv.find_invert_symbol (Genv.globalenv prog) id); auto.
 assert (H9: In (id, mk_funspec f0 cc0 A a a0) G). {
   clear - H1.
    simpl in H1. unfold make_tycontext_g in H1; simpl in H1.
    induction G; simpl in *.
    rewrite PTree.gempty in H1; inv H1.
    destruct (ident_eq (fst a1) id); subst.
    rewrite PTree.gss in H1; inv H1. destruct a1; left; auto.
    rewrite PTree.gso in H1; auto.
 }
 rewrite (find_id_i _ _ _ H9); auto.
 clear - H0 H. unfold prog_defs_names, prog_funct in *.
 eapply match_fdecs_norepet; eauto.
 apply list_norepet_prog_funct'; auto.
*
 intros loc'  [fsig' cc' A' P' Q'].
 unfold func_at.
 intros w ? ?.
 destruct H2 as [pp ?].
 hnf in H2.
 assert (exists pp, initial_core (Genv.globalenv prog) G n @ (loc',0) = PURE (FUN fsig' cc') pp).
case_eq (initial_core (Genv.globalenv prog) G n @ (loc',0)); intros.
destruct (necR_NO _ _ (loc',0) t H1) as [? _].
rewrite H4 in H2 by auto.
inv H2.
eapply necR_YES in H1; try apply H3.
rewrite H1 in H2; inv H2.
eapply necR_PURE in H1; try apply H3.
rewrite H1 in H2; inv H2; eauto.
destruct H3 as [pp' ?].
unfold initial_core in H3.
rewrite resource_at_make_rmap in H3.
unfold initial_core' in H3.
if_tac in H3; [ | inv H3].
simpl.
simpl @fst in *.
revert H3; case_eq (@Genv.invert_symbol fundef type
         (@Genv.globalenv (Ctypes.fundef function) type
            prog) loc'); intros;
  [ | congruence].
revert H5; case_eq (find_id i G); intros; [| congruence].
destruct f as [?f ?A ?a ?a]; inv H6.
apply Genv.invert_find_symbol in H3.
exists i.
simpl ge_of. unfold filter_genv.
unfold globalenv; simpl.
 rewrite H3.
 split; auto.
 assert (exists f, In (i,f) (prog_funct prog)
              /\ type_of_fundef f = Tfunction (type_of_params (fst fsig')) (snd fsig') cc'). {
 clear - H0 H5.
 forget (prog_funct prog) as g.
 revert G H0 H5; induction g; intros.
 inv H0. inv H5.
 inv H0.
 simpl in H5.
 if_tac in H5. subst i0. inv H5. exists fd; split; auto. left; auto.
 destruct (IHg G0) as [f3 [? ?]]; auto. exists f3; split; auto.
 right; auto.
(*
 destruct (IHg _ H3 H5) as [f [H4 H4']].
 exists f; split; auto. right; auto.
*)
 }
 clear H4.
 destruct H6 as [f [H4 H4']].
 destruct (find_funct_ptr_exists prog i f) as [b [? ?]]; auto.
 apply in_prog_funct_in_prog_defs; auto.
 unfold fundef in *.
 inversion2 H3 H6.
 case_eq (Genv.find_var_info (Genv.globalenv prog) loc'); intros.
 elimtype False; clear - H7 H6. 
 unfold Genv.find_funct_ptr in H7.
 unfold Genv.find_var_info in H6.
 destruct (Genv.find_def (Genv.globalenv prog) loc'); try destruct g0; congruence.
 apply find_id_e in H5. apply in_map_fst in H5.
 clear - H5.
 revert H5; induction G; simpl; intro. contradiction.
 destruct H5. subst. econstructor; rewrite PTree.gss; reflexivity.
 destruct (IHG H) as [fs ?].
 destruct (eq_dec (fst a) i). econstructor; subst; rewrite PTree.gss; eauto.
 econstructor; rewrite PTree.gso by auto; eauto.
Qed.

Lemma prog_contains_prog_funct: forall prog: program,  
      list_norepet (prog_defs_names prog) ->
          prog_contains (globalenv prog) (prog_funct prog).
Proof.
  intros; intro; intros.
  apply (find_funct_ptr_exists prog id f); auto.
  unfold prog_funct in H0.
  change (AST.prog_defs prog) with (prog_defs prog).
  induction (prog_defs prog). inv H0.
   simpl in H0.  destruct a. 
  destruct g. simpl in H0. destruct H0. inv H0.  left. auto.
  right; auto.  right; auto.
Qed. 

(* there's a place this lemma should be applied, perhaps in proof of semax_call *)
Lemma funassert_rho:
  forall G rho rho', ge_of rho = ge_of rho' -> funassert G rho |-- funassert G rho'.
Proof.
unfold funassert; intros.
rewrite H; auto.
Qed.

Lemma core_inflate_initial_mem:
  forall (m: mem) (prog: program) (G: funspecs) (n: nat)
     (INIT: Genv.init_mem prog = Some m),
    match_fdecs (prog_funct prog) G ->
      list_norepet (prog_defs_names prog) ->
   core (inflate_initial_mem m (initial_core (Genv.globalenv prog) G n)) =
         initial_core (Genv.globalenv prog) G n.
Proof.
intros.
assert (IOK := initial_core_ok _ _ n _ H0 H INIT).
apply rmap_ext.
  unfold inflate_initial_mem, initial_core; simpl.
  rewrite level_core. do 2 rewrite level_make_rmap; auto.
intro l.
unfold inflate_initial_mem, initial_core; simpl.
rewrite <- core_resource_at.
repeat rewrite resource_at_make_rmap.
unfold inflate_initial_mem'.
repeat rewrite resource_at_make_rmap.
unfold initial_core'.
case_eq (Genv.invert_symbol (Genv.globalenv prog) (fst l)); intros; auto.
rename i into id.
case_eq (find_id id G); intros; auto.
rename f into fs.
assert (exists f, In (id,f) (prog_funct prog)).
apply find_id_e in H2.
apply in_map_fst in H2.
eapply match_fdecs_in in H2; eauto.
apply in_map_iff in H2.
destruct H2 as [[i' f] [? ?]]. subst id; exists f; auto.
destruct H3 as [f ?].
apply Genv.invert_find_symbol in H1.
destruct (find_funct_ptr_exists prog id f) as [b [? ?]]; auto.
apply in_prog_funct_in_prog_defs; auto.
inversion2 H1 H4.
if_tac.
 destruct (IOK l) as [_ ?].
 unfold initial_core in H6. rewrite resource_at_make_rmap in H6.
  unfold initial_core' in H6. rewrite if_true in H6 by auto.
  apply Genv.find_invert_symbol in H1.
  unfold fundef in *; rewrite H1 in *.
  rewrite H2 in *. destruct fs.
  destruct H6 as [? [? ?]]. rewrite H7.
  rewrite core_PURE; auto.
  destruct (access_at m l); try destruct p; try rewrite core_YES; try rewrite core_NO; auto.
  unfold fundef in *; rewrite H1,H2 in *.
  if_tac;  destruct (access_at m l); try destruct p; try rewrite core_YES; try rewrite core_NO; auto.
  unfold fundef in *; rewrite H1 in *.
 if_tac;   destruct (access_at m l); try destruct p; try rewrite core_YES; try rewrite core_NO; auto.
Qed.

Definition Delta1 V G {C: compspecs}: tycontext := 
  make_tycontext ((1%positive,(Tfunction Tnil Tvoid cc_default))::nil) nil nil Tvoid V G.

Lemma match_globvars_in':
  forall i t vl vs,
  match_globvars vl vs = true ->
  In (i,t) vs ->
  exists g, In (i,g) vl /\ gvar_info g = t /\ is_pointer_type t = true.
Proof.
 induction vl; destruct vs; intros. inv H0.
 destruct p; inv H.
 inv H0. destruct p, H0. inv H0.  simpl in *.
 destruct a. 
 pose proof (eqb_ident_spec i i0); destruct (eqb_ident i i0).
 assert (i=i0) by (rewrite <- H0; auto). subst i0; clear H0.
 apply andb_true_iff in H; destruct H as [PT ?].
 apply andb_true_iff in H; destruct H.
 apply eqb_type_true in H. subst t.
 exists g; split3; auto.
 destruct (IHvl _ H) as [g' [? [? ?]]]. left; auto. exists g'; split3; auto.
 simpl in H. destruct a.
 pose proof (eqb_ident_spec i0 i1); destruct (eqb_ident i0 i1).
 apply andb_true_iff in H; destruct H as [PT ?].
 apply andb_true_iff in H; destruct H.
 destruct (IHvl _ H2) as [g' [? [? ?]]]; auto. exists g'; split3; auto.
 right; auto.
 apply IHvl in H. destruct H as [g' [? [? ?]]]. exists g'; split3; auto.
 right; auto.
 right; auto.
Qed.

Lemma match_globvars_in:
  forall i vl vs, match_globvars vl vs = true -> In i  (map (@fst _ _) vs) -> In i (map (@fst _ _) vl).
Proof.
 intros.
 apply list_in_map_inv in H0. destruct H0 as [t [? ?]]. subst i.
 destruct t as [i t].
 destruct  (match_globvars_in' _ _ _ _ H H1) as [g [? [? ?]]].
 simpl. apply in_map_fst with g; auto.
Qed.

Lemma match_globvars_norepet:
  forall vl vs, 
   list_norepet (map (@fst _ _) vl) ->
   match_globvars vl vs = true ->
   list_norepet (map (@fst _ _) vs).
Proof.
induction vl; destruct vs; simpl; intros.
constructor. destruct p. inv H0.
constructor.
destruct p; destruct a.
simpl in *.
inv H.
 pose proof (eqb_ident_spec i i0); destruct (eqb_ident i i0). 
 assert (i=i0) by (apply H; auto); subst i0; clear H.
 apply andb_true_iff in H0; destruct H0 as [_ H0].
 apply andb_true_iff in H0; destruct H0.
 constructor; auto.
 contradict H3.
 eapply match_globvars_in; eauto.
 assert (i<>i0). intro; subst; destruct H. specialize (H1 (eq_refl _)); inv H1.
 clear H.
 specialize (IHvl ((i,t)::vs) H4 H0).
 inv IHvl.
 constructor; auto.
Qed.

Lemma make_tycontext_g_denote:
  forall id t l vs G,
    list_norepet (map fst l) ->
    match_globvars (prog_vars' l) vs = true ->
    match_fdecs (prog_funct' l) G ->
   ((make_tycontext_g vs G) ! id = Some t <->
    ((exists f, In (id,f) G /\ t = type_of_funspec f) \/ In (id,t) vs)).
Proof.
  intros.
  assert (list_norepet (map (@fst _ _) (prog_funct' l) ++  (map (@fst _ _) (prog_vars' l)))). {
   clear - H.
  induction l; simpl. constructor.
  destruct a; destruct g; simpl in *; inv H.
  constructor; auto.
  clear - H2; contradict H2.
   induction l. inv H2. destruct a; destruct g; simpl in *. destruct H2; auto.
   apply in_app in H2. destruct H2. right; apply IHl. apply in_app; auto.
   destruct H; auto. right; apply IHl; apply in_app; auto.
   specialize (IHl H3).
   apply list_norepet_app in IHl. destruct IHl as [? [? ?]].
   apply list_norepet_app; split3; auto.
   constructor; auto.
  clear - H2; contradict H2.
   induction l. inv H2. destruct a; destruct g. simpl in H2. constructor 2; auto.
   simpl in H2. destruct H2. subst; left; auto. right. auto.
  apply list_disjoint_cons_r; auto.
  clear - H2; contradict H2.
   induction l. inv H2. destruct a; destruct g. simpl in H2.
  destruct H2. subst; left; auto. right; auto.
  simpl in *. right; auto.
}
 forget (prog_vars' l) as vl.
 forget (prog_funct' l) as fl.
 clear l H.
 revert G H2 H1; induction fl; intros.
* (* fl = nil *)
 destruct G; inv H1.
 simpl in H2.
 apply iff_trans with (In (id, t) vs );
  [ | clear; intuition; destruct H0 as [? [? ?]]; contradiction].
 revert vs H0; induction vl; destruct vs; simpl in *; intros.
+(* fl = nil /\ vl = nil /\ vs = nil*)
 rewrite PTree.gempty.
 split; intros. discriminate. contradiction.
+ (* fl = nil /\ vl = nil /\ vs<>nil *)
 clear H2.
 destruct p. inv H0.
+ (* fl = nil /\ vl inductive case /\ vs = nil  *)
 clear H0. rewrite PTree.gempty.
   clear. intuition congruence.
 + (* fl = nil /\ vl inductive case /\ vs <> nil *)
   destruct p. destruct a. simpl in *. inv H2.
  specialize (IHvl H4).
  destruct (ident_eq id i).
 - subst id.
  rewrite PTree.gss. split; intro. inv H.
  auto.
 destruct H. inv H. auto.
 pose proof (eqb_ident_spec i i0); destruct (eqb_ident i i0).
 assert (i=i0) by (rewrite <- H1; auto). subst i0; clear H1.
  apply andb_true_iff in H0; destruct H0 as [_ H0].
  apply andb_true_iff in H0; destruct H0.
 contradiction H3.
 eapply match_globvars_in; eauto. apply in_map_fst with t. auto.
 assert (i<>i0). intro; subst. clear - H1. destruct H1. specialize (H0 (eq_refl _)); inv H0.
 clear H1.
 pose proof (match_globvars_norepet _ _ H4 H0).
 inv H1. contradiction H7. apply in_map_fst with t; auto.
 - (* id <> i *)
 rewrite PTree.gso by auto.
 pose proof (eqb_ident_spec i i0). 
 destruct (ident_eq i i0). 
 subst. destruct H. rewrite H1 in H0 by auto. 
  apply andb_true_iff in H0; destruct H0 as [_ H0].
 rewrite andb_true_iff in H0; destruct H0.
 apply eqb_type_true in H0. subst t0.
 clear H H1.
 rewrite IHvl; auto.
 clear - n; intuition. inv H0; congruence.
 destruct (eqb_ident i i0). contradict n0; apply H; auto.
 eapply iff_trans; [ | apply (IHvl ((i,t0)::vs))]; clear IHvl.
 simpl;  rewrite PTree.gso by auto. apply iff_refl.
 auto.
*
 inv H1.
 + 
   inv H2.
   specialize (IHfl _ H5 H6).
   destruct (ident_eq id i). subst. 
  simpl; rewrite PTree.gss.
  split; intro.
  left; exists fspec.  inv H; auto.
  f_equal.
  destruct H as [[f [? ?]]| ?].
  destruct H. inv H. auto.
  elimtype False; clear - H3 H H6.
  apply H3; apply in_app_iff. left; eapply match_fdecs_in; eauto.
  apply in_map_fst in H; auto. 
  contradiction H3. apply in_app_iff; right.
  subst.
  eapply match_globvars_in; eauto.
  apply in_map_fst in H; auto.
  simpl; rewrite PTree.gso; auto.
  rewrite IHfl. clear IHfl.
  split; intros [[f [? ?]]| ?]; subst.
  left; eauto. right; eauto.
  left; eauto. destruct H. congruence.
  exists f; eauto.
  right; eauto.
(*+
  simpl in H2; inv H2.
  apply (IHfl G); auto.
*)
Qed.

Lemma tc_ge_denote_initial:
  forall vs G (prog: program),
list_norepet (prog_defs_names prog) ->
match_globvars (prog_vars prog) vs = true->
match_fdecs (prog_funct prog) G ->
typecheck_glob_environ (filter_genv (globalenv prog)) (make_tycontext_g vs G).
Proof.
intros.
hnf; intros.
rewrite make_tycontext_g_denote in H2; eauto.
destruct H2 as [[f [? ?]]|?].
*
subst t.
unfold filter_genv.
destruct (match_fdecs_exists_Gfun prog G id f) as [fd [? H20]]; auto.
apply find_id_i; auto.
eapply match_fdecs_norepet; eauto.
unfold prog_defs_names in H.
clear - H.
unfold prog_funct.
change (AST.prog_defs prog) with (prog_defs prog) in H. 
induction (prog_defs prog). constructor.
inv H. destruct a; simpl.  destruct g.
simpl map. constructor; auto. simpl in H2.
contradict H2.
clear - H2. induction l; simpl; auto.
destruct a. destruct g; simpl in *. destruct H2; auto. right; auto.
apply IHl; auto.
destruct (find_funct_ptr_exists prog id fd) as [b [? ?]]; auto.
exists b.
unfold globalenv; simpl Genv.find_symbol.
split; auto.
unfold type_of_global.
destruct f; simpl; auto.
*
 unfold filter_genv.
 destruct (match_globvars_in' _ _ _ _ H0 H2) as [g [? [? TC]]].
 apply in_prog_vars_in_prog_defs in H3.
 pose proof (prog_defmap_norepet _ _ _ H H3).
destruct (proj1 (Genv.find_def_symbol _ _ _) H5) 
  as [b [? ?]].
 exists b. 
 split; auto.
Qed.

Lemma semax_prog_typecheck_aux:
  forall vs G {C: compspecs} (prog: program) b,
   list_norepet (prog_defs_names prog) ->
   match_globvars (prog_vars prog) vs = true ->
   match_fdecs (prog_funct prog) G ->
   typecheck_environ
      (Delta1 vs G) (construct_rho (filter_genv (globalenv prog)) empty_env
        (PTree.set 1 (Vptr b Int.zero) (PTree.empty val))) .
Proof.
unfold Delta1; intros.
unfold construct_rho.
unfold make_tycontext.
unfold  typecheck_environ.
unfold ve_of, ge_of, te_of.
split; [ | split3].
* 
unfold temp_types. unfold fst.
unfold make_tycontext_t.
unfold fold_right. unfold snd, fst.
unfold typecheck_temp_environ.
unfold make_tenv.
unfold Map.get.
intros.
rewrite PTree.gsspec in *. if_tac. inv H2. eauto. 
rewrite PTree.gempty in H2. congruence.
* 
unfold var_types.
unfold typecheck_var_environ. intros.
unfold make_tycontext_v. simpl.
rewrite PTree.gempty.
unfold Map.get, make_venv, empty_env.
rewrite PTree.gempty.
intuition. inv H2. destruct H2; inv H2.
*
unfold glob_types. unfold make_tycontext_t, snd.
eapply tc_ge_denote_initial; eauto.
*
hnf; intros.
simpl.
left. unfold make_venv. unfold empty_env. apply PTree.gempty.
Qed.

Lemma in_map_sig {A B} (E:forall b b' : B, {b=b'}+{b<>b'}) y (f : A -> B) l : In y (map f l) -> {x : A | f x = y /\ In x l }.
Proof.
  induction l; intros HI.
  - inversion HI.
  - simpl in HI.
    destruct (E (f a) y).
    + exists a; intuition.
    + destruct IHl. tauto. exists x; intuition.
Qed.

Lemma semax_prog_rule {CS: compspecs} :
  forall V G prog m,
     @semax_prog CS prog V G ->
     Genv.init_mem prog = Some m ->
     { b : block & { q : corestate &
       (Genv.find_symbol (globalenv prog) (prog_main prog) = Some b) *
       (semantics.initial_core (juicy_core_sem cl_core_sem)
                    (globalenv prog) (Vptr b Int.zero) nil = Some q) *
       forall n,
         { jm |
           m_dry jm = m /\ level jm = n /\
           (forall z, jsafeN (@OK_spec Espec) (globalenv prog) n z q jm) /\
           no_locks (m_phi jm)
     } } }%type.
Proof.
  intros until m.
  pose proof I; intros.
  destruct H0 as [? [AL [HGG [[? ?] [GV [? HInt]]]]]].
  assert ({ f | In (prog_main prog, f) (prog_funct prog)}).
  forget (prog_main prog) as id.
  apply in_map_fst in H4.
  pose proof (match_fdecs_in _ _ _ H4 H2).
  apply in_map_sig in H5. 2:decide equality.
  destruct H5 as [[? ?] [? ?]]; subst.
  eauto.
  destruct H5 as [f ?].
  apply compute_list_norepet_e in H0.
  assert (indefs: In (prog_main prog, Gfun f) (AST.prog_defs prog))
    by (apply in_prog_funct_in_prog_defs; auto).
  pose proof (find_funct_ptr_exists prog (prog_main prog) f) as EXx.
  (* Genv.find_funct_ptr_exists is a Prop existential, we use constructive epsilon and
     decidability on a countable set to transform it to a Type existential *)
  assert (dec: forall x : positive,
             {Genv.find_symbol (Genv.globalenv prog) (prog_main prog) = Some x /\
              Genv.find_funct_ptr (Genv.globalenv prog) x = Some f} +
             {~ (Genv.find_symbol (Genv.globalenv prog) (prog_main prog) = Some x /\
                 Genv.find_funct_ptr (Genv.globalenv prog) x = Some f)}).
  {
    intros p.
    assert (group : forall {A} {B} (a a':A) (b b':B), (a = a' /\ b = b') <-> ((a, b) = (a', b')))
      by (intros;split; [ intros [<- <-]; reflexivity | intros E; injection E; auto]).
    assert (sumbool_iff_left : forall (A A' B : Prop), (A -> A') -> {A}+{B} -> {A'}+{B}) by tauto.
    assert (sumbool_iff_right : forall (A B B' : Prop), (B -> B') -> {A}+{B} -> {A}+{B'}) by tauto.
    eapply sumbool_iff_left. apply group.
    eapply sumbool_iff_right. rewrite group. apply (fun x => x).
    pose proof type_eq.
    pose proof eq_dec_statement.
    repeat (hnf; decide equality; auto).
  }
  apply (decidable_countable_ex_sig Pos.of_nat) in EXx; auto. clear dec.
  2: intro; eexists; symmetry; apply Pos2Nat.id.
  
  pose proof I.
  destruct EXx as [b [? ?]]; auto.
  exists b.
  unfold semantics.initial_core; simpl.
  unfold fundef in *; rewrite H7.
  rewrite if_true by auto.
  unfold is_Internal in HInt.
  rewrite H6 in HInt.
  rewrite H7 in HInt.
  destruct f as [func | ]; [ | exfalso; discriminate ].
  (* set (func' := func) at 1; destruct func' eqn:Ef. *)
  econstructor.
  repeat split; auto.
  intro n.
  exists (initial_jm _ _ _ n H1 H0 H2).
  repeat split.
  - simpl.
    rewrite inflate_initial_mem_level.
    unfold initial_core. rewrite level_make_rmap; auto.
  
  - specialize (H3 (globalenv prog) (prog_contains_prog_funct _ H0)).
    
    assert (E: func.(fn_params) = nil). {
      destruct (match_fdecs_exists_Gfun
                  prog G (prog_main prog)
                  (mk_funspec (nil, Tvoid) cc_default unit (main_pre prog) (main_post prog)))
        as (fd, (Ifd, sametypes)); auto.
      {
        apply find_id_i; auto.
        eapply match_fdecs_norepet; eauto.
        clear -H0; revert H0.
        apply sublist_norepet.
        unfold prog_funct, prog_funct', prog_defs_names.
        replace (AST.prog_defs prog) with (prog_defs prog) by reflexivity.
        generalize (prog_defs prog); intros l; induction l as [|(i,[g|]) l];
          constructor; auto.
      }
      assert (fd = Internal func).
      cut (Gfun fd = @Gfun _ type (Internal func)); [ intros E; injection E; auto | ].
      apply (list_norepet_In_In (prog_main prog) _ _ (prog_defs prog)); auto.
      subst fd.
      simpl in sametypes.
      destruct func.
      destruct fn_params. auto.
      destruct p; discriminate.
    }
    
    rewrite E in *.
    unfold temp_bindings. simpl length. simpl typed_params. simpl type_of_params.
    pattern n at 1; replace n with (level (m_phi (initial_jm prog m G n H1 H0 H2))).
    pose (rho := mkEnviron (filter_genv (globalenv prog)) (Map.empty (block * type)) 
                           (Map.set 1 (Vptr b Int.zero) (Map.empty val))).
    intros z.
    eapply (semax_call_aux Espec (Delta1 V G) unit
                           _ (fun _ => main_post prog tt) _ tt (fun _ => TT) (fun _ => TT)
                           None (nil,Tvoid) cc_default _ _ (normal_ret_assert (fun _ => TT)) _ _ _ _ 
                           (construct_rho (filter_genv (globalenv prog)) empty_env
                                          (PTree.set 1 (Vptr b Int.zero) (PTree.empty val)))
                           _ _ b (prog_main prog));
      try apply H3; try eassumption; auto.
    + clear - GV H2 H0.
      split.
      eapply semax_prog_typecheck_aux; eauto.
      simpl.
      auto.
    + hnf; intros; intuition.
    + hnf; intros; intuition.
      unfold normal_ret_assert; simpl.
      extensionality rho'.
      unfold main_post.
      normalize. rewrite TT_sepcon_TT.
      apply pred_ext. apply exp_right with Vundef; auto. auto.
    + rewrite (corable_funassert _ _).
      simpl m_phi.
      rewrite core_inflate_initial_mem; auto.
      do 3 (pose proof I).
      replace (funassert (Delta1 V G)) with
      (funassert (@nofunc_tycontext V G)).
      unfold rho; apply funassert_initial_core; auto.
      apply same_glob_funassert.
      reflexivity.
    + intros ek vl tx' vx'.
      unfold normal_ret_assert, frame_ret_assert.
      normalize.
      rewrite TT_sepcon_TT.
      normalize.
      apply derives_subp.
      normalize.
      simpl.
      intros ? ? ? ? _ ?.
      destruct H8 as [[? [? ?]] ?].
      hnf in H10, H11. subst ek vl.
      destruct H8.
      subst a.
      change Clight_new.true_expr with true_expr.
      change (level (m_phi jm)) with (level jm).
      apply safe_loop_skip.
    + unfold glob_types, Delta1. simpl @snd.
      forget (prog_main prog) as main.
      instantiate (1:=main_post prog). 
      instantiate (1:=main_pre prog).
      assert (H8: list_norepet (map (@fst _ _) (prog_funct prog))).
      clear - H0.
      unfold prog_defs_names in H0. unfold prog_funct.
      change (AST.prog_defs prog) with (prog_defs prog) in H0.
      induction (prog_defs prog); auto. inv H0.
      destruct a; destruct g; simpl; auto. constructor; auto.
      clear - H2; simpl in H2; contradict H2; induction l; simpl in *; auto.
      destruct a; destruct g; simpl in *; auto. destruct H2; auto.
      forget (prog_funct prog) as fs.
      clear - H4 H8 H2.
      forget (mk_funspec (nil, Tvoid) cc_default unit (main_pre prog) (main_post prog)) as fd.
      revert G H2 H4 H8; induction fs; intros; inv H2.
      inv H4.
      simpl in *.
      destruct (ident_eq i main). subst. rewrite PTree.gss.
      destruct H4. inv H; auto.
      inv H8.
      contradiction H3.
      eapply match_fdecs_in; eauto.
      apply in_map_fst in H; auto.
      rewrite PTree.gso by auto.
      destruct H4; try congruence.
      inv H8.
      eapply IHfs; eauto.
(*      inv H8; eauto. *)
    + intros.
      intros ? ?.
      split; apply derives_imp; auto.
    + unfold main_pre.
      apply now_later.
      rewrite TT_sepcon_TT.
      rewrite sepcon_comm.
      apply sepcon_TT.
      simpl.
      apply global_initializers; auto.
    + simpl.
      rewrite inflate_initial_mem_level.
      unfold initial_core.
      apply level_make_rmap.
  - apply initial_jm_without_locks.
  - apply initial_jm_without_locks.
Qed.

Definition Delta_types V G {C: compspecs} (tys : list type) : tycontext := 
  make_tycontext
    (params_of_types
       1 ((Tfunction (type_of_params (params_of_types 2 tys)) Tvoid cc_default) :: tys))
    nil nil Tvoid V G.

Lemma semax_prog_typecheck_aux_types:
  forall vs G {C: compspecs} (prog: program) b (typed_args : list (val * type)),
   list_norepet (prog_defs_names prog) ->
   match_globvars (prog_vars prog) vs = true ->
   match_fdecs (prog_funct prog) G ->
   forallb (fun x => typecheck_val (fst x) (snd x)) typed_args = true ->
   typecheck_environ
     (Delta_types vs G (map snd typed_args))
     (construct_rho
        (filter_genv (globalenv prog)) empty_env
        (PTree.set 1 (Vptr b Int.zero)
                   (temp_bindings 2 (map fst typed_args)))).
Proof.
  intros vs G C prog b typed_args NR MG MF TYP.
  repeat split.
  - unfold te_of, construct_rho.
    intros i b' ty.
    unfold make_tycontext, temp_types.
    intros Found.
    assert (make_tycontext_t_cons1 : forall i i' t l1 l2, (make_tycontext_t ((i, t) :: l1) l2) ! i' =
      if peq i' i then Some (t, true) else (make_tycontext_t l1 l2) ! i')
    by (clear; intros i i' t l1 l2; simpl; rewrite PTree.gsspec; reflexivity).
    unfold Delta_types, make_tycontext in Found.
    simpl params_of_types in Found.
    rewrite make_tycontext_t_cons1 in Found.
    rewrite <-map_ptree_rel, Map.gsspec.
    if_tac; if_tac in Found; subst; try tauto.
    + injection Found as <- <- ; eauto.
    + revert Found; generalize (2%positive).
      induction typed_args; intros p Found.
      * rewrite PTree.gempty in Found.
        discriminate.
      * simpl (params_of_types _ _ ) in Found.
        rewrite make_tycontext_t_cons1 in Found.
        simpl (map _ _).
        change (exists v : val, Map.get (make_tenv (PTree.set p (fst a) (temp_bindings (p+1)
          (map fst typed_args)))) i = Some v /\ (is_true (negb b') \/ typecheck_val v ty = true)).
        rewrite <-map_ptree_rel, Map.gsspec.
        simpl in TYP; rewrite andb_true_iff in TYP; destruct TYP as [Ta TYP].
        { if_tac; if_tac in Found; subst; try tauto.
          - injection Found as <- <- ; eauto.
          - apply IHtyped_args; auto. }
  - simpl.
    rewrite PTree.gempty.
    intro; discriminate.
  - simpl.
    unfold make_venv, Map.get, empty_env.
    rewrite PTree.gempty.
    intros [? ?]; discriminate.
  - eapply tc_ge_denote_initial; eauto.
  - left.
    apply PTree.gempty.
Qed.

Lemma find_id_maketycontext_s G id : (make_tycontext_s G) ! id = find_id id G.
Proof.
  induction G as [|(i,t) G]; simpl.
  - destruct id; reflexivity.
  - rewrite PTree.gsspec.
    do 2 if_tac; congruence.
Qed.

Definition find_params (prog : program) (f : ident) :=
  match Genv.find_symbol (Genv.globalenv prog) f with
    None => None
  | Some b =>
    match Genv.find_funct_ptr (Genv.globalenv prog) b with
    | None => None
    | Some f =>
      match f with
      | External _ _ _ _ => None
      | Internal func => Some func.(fn_params)
      end
    end
  end.

Lemma semax_prog_entry_point {CS: compspecs} :
  forall V G prog id_fun id_arg arg params A P Q,
    @semax_prog CS prog V G ->
    (* is_Internal prog id_fun = true -> *)
    params = (id_arg, Tpointer Tvoid noattr) :: nil ->
    find_params prog id_fun = Some params ->
    find_id id_fun G = Some (mk_funspec (params, Tvoid) cc_default A P Q) ->
    (* (* P is closed wrt all tempvars except 2 *) *)
    (* (forall x, closed_wrt_vars (fun n => ~eq 2%positive n) (P x)) -> *)
    (forall a rho, Q a rho |-- FF) ->
    is_pointer_or_null arg ->
    { b : block &
      (* initial environment *)
      let rho0 : environ :=
          construct_rho
            (filter_genv (globalenv prog)) empty_env
            (PTree.set 1 (Vptr b Int.zero)
                       (PTree.set id_arg arg (PTree.empty val))) in
      
      (* initial environment without the function => to check jm |= P a *)
      let rho1 : environ :=
          construct_rho
            (filter_genv (globalenv prog)) empty_env
            ((* PTree.set 1 (Vptr b Int.zero) *)
                       (PTree.set id_arg arg (PTree.empty val))) in
      
      { q : corestate |
        Genv.find_symbol (globalenv prog) id_fun = Some b /\
        semantics.initial_core
          (juicy_core_sem cl_core_sem)
          (globalenv prog) (Vptr b Int.zero) (arg :: nil) = Some q /\
        
        forall (jm : juicy_mem) (a : A),
          app_pred (P a rho1) (m_phi jm) ->
          app_pred (funassert (Delta_types V G (Tpointer Tvoid noattr::nil)) rho0) (m_phi jm) ->
          forall z, jsafeN (@OK_spec Espec) (globalenv prog) (level jm) z q jm } }.
Proof.
  intros V G prog id_fun id_arg arg params A P Q SP (* INT *) Eparams Fparams id_in_G QFF arg_p.
  unfold find_params in Fparams.
  destruct (Genv.find_symbol (Genv.globalenv prog) id_fun) as [b|] eqn:Fid; [ | discriminate].
  destruct (Genv.find_funct_ptr (Genv.globalenv prog) b) as [[func|]|] eqn:Fb; try discriminate.
  subst params; injection Fparams as Eparams.
  
  exists b.
  intros rho0 rho1.
  simpl (semantics.initial_core _).
  unfold cl_initial_core.
  if_tac;[|tauto]. match goal with H : ?a = ?a |- _ => clear H end.
  replace (Genv.find_funct_ptr (globalenv prog)) with
  (Genv.find_funct_ptr (Genv.globalenv prog))
    by reflexivity.
  rewrite Fb.
  econstructor.
  split. apply Fid.
  split. reflexivity.
  rewrite Eparams.
  
  intros jm a m_sat_Pa m_funassert.
  
  destruct SP as [H0 [AL [HGG [[H2 H3] [GV _]]]]].
  apply compute_list_norepet_e in H0.
  specialize (H3 (globalenv prog) (prog_contains_prog_funct _ H0)).

  pose (rho3 := 
          construct_rho
            (filter_genv (globalenv prog)) empty_env
            (PTree.set 1 (Vptr b Int.zero)
                       (temp_bindings 2 (map fst ((arg, Tpointer Tvoid noattr) :: nil))))).
  
  pose proof I.
  intros z.
  eapply
    (semax_call_aux
       Espec (Delta_types V G (Tpointer Tvoid noattr::nil)) A _
       (fun _ => Q a) _ a (fun _ => emp) (fun _ => emp)
       None ((id_arg, Tpointer Tvoid noattr)::nil, Tvoid) cc_default _ _
       (normal_ret_assert (fun rho => EX _ : val, emp * Q a (globals_only rho)))
       _ _ _ _ rho3
       _ _ b id_fun);
    try apply H3; try eassumption; auto.
  
  (* guard_environ *)
  split; try apply I.
  eapply semax_prog_typecheck_aux_types; eauto.
  now destruct arg; inversion arg_p; reflexivity.
  
  (* closed_wrt_modvars *)
  simpl.
  hnf; intros; intuition.
  hnf; intros; intuition.
  unfold normal_ret_assert; simpl.
  extensionality rho'.
  now normalize.
  
  (* funassert: not a goal anymore (in the hypotheses) *)
  
  (* guard_environ: we conclude because Q=>False *)
  repeat intro.
  repeat match goal with H : context [ Q ] |- _ => destruct H end.
  repeat match goal with H : context [ Q ] |- _ => apply QFF in H; inversion H end.
  
  (* globspecs *)
  simpl.
  rewrite find_id_maketycontext_s.
  eassumption.

  (* equivalence between Q and Q' *)
  intros vl; split; apply derives_imp; apply derives_refl'; reflexivity.
  
  (* precondition *)
  refine (derives_e _ _ _ _ m_sat_Pa).
  normalize.
  simpl.
  eapply derives_trans; [|apply now_later].
  unfold rho1.
  simpl.
  apply derives_refl'; f_equal.
  unfold globals_only, env_set, rho0, construct_rho.
  simpl.
  f_equal.
  extensionality i; destruct i; reflexivity.
  unfold make_tenv, force_val, sem_cast_neutral, eval_id.
  extensionality i.
  rewrite PTree.gsspec.
  unfold Map.set.
  if_tac; if_tac; try congruence; subst.
  unfold liftx, lift; simpl.
  now destruct arg; inversion arg_p; auto.
  now destruct i; reflexivity.
Qed.

End semax_prog.
