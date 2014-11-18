(** Heavily annotated for a tutorial introduction.
 ** See the Makefile for how to strip the annotations
 **)

(** First, import the entire Floyd proof automation system, which 
 ** includes the VeriC program logic and the MSL theory of separation logic
 **)
Require Import floyd.proofauto.

(** Import the theory of list segments.  This is not, strictly speaking,
 ** part of the Floyd system.  In principle, any user of Floyd can build
 ** theories of new data structures (list segments, trees, doubly linked
 ** lists, trees with cross edges, etc.).  We emphasize this by putting
 ** list_dt in the progs directory.   "dt" stands for "dependent types",
 ** as the theory uses Coq's dependent types to handle user-defined
 ** record fields.
 **)
Require Import progs.list_dt.

(** Import the [reverse.v] file, which is produced by CompCert's clightgen
 ** from reverse.c 
 **)
Require Import progs.reverse.

(** Open the notation scope containing  !! * && operators of separation logic *)
Local Open Scope logic.

(** The reverse.c program uses the linked list structure [struct list].
 ** This satisfies the linked-list pattern, in that it has one self-reference
 ** field (in this case, called [tail]) and arbitrary other fields.  The [Instance]
 ** explains (and proves) how [struct list] satisfies the [listspec] pattern.
 **)
Instance LS: listspec t_struct_list _tail.
Proof. eapply mk_listspec; reflexivity. Defined.

(**  An auxiliary definition useful in the specification of [sumlist] *)
Definition sum_int := fold_right Int.add Int.zero.

(** Specification of the [sumlist] function from reverse.c.  All the functions
 ** defined in the file, AND extern functions imported by the .c file,
 ** must be declared in this way.
 **)
Definition sumlist_spec :=
 DECLARE _sumlist
  WITH sh : share, contents : list int, p: val
  PRE [ _p OF (tptr t_struct_list)] 
     PROP() LOCAL (temp _p p)
     SEP (`(lseg LS sh (map Vint contents) p nullval))
  POST [ tint ]  local (`(eq (Vint (sum_int contents))) retval).
(** This specification has an imprecise and leaky postcondition:
 ** it neglects to say that the original list [p] is still there.
 ** Because the postcondition has no spatial part, it makes no
 ** claim at all: the list [p] leaks away, and arbitrary other stuff
 ** might have been allocated.  All the postcondition specifies
 ** is that the contents of the list has been added up correctly.
 ** One could easily make a more precise specification of this function.
 **)

Definition reverse_spec :=
 DECLARE _reverse
  WITH sh : share, contents : list val, p: val
  PRE  [ _p OF (tptr t_struct_list) ]
     PROP (writable_share sh)
     LOCAL (temp _p p)
     SEP (`(lseg LS sh contents p nullval))
  POST [ (tptr t_struct_list) ]
            `(lseg LS sh (rev contents)) retval `nullval.

Definition main_spec :=
 DECLARE _main
  WITH u : unit
  PRE  [] main_pre prog u
  POST [ tint ] main_post prog u.

(** Declare the types of all the global variables.  [Vprog] must list
 ** the globals in the same order as in reverse.c file (and as in reverse.v).
 **)
Definition Vprog : varspecs := 
          (_three, Tarray t_struct_list 3 noattr)::nil.

(** Declare all the functions, in exactly the same order as they
 ** appear in reverse.c (and in reverse.v).
 **)
Definition Gprog : funspecs := 
    sumlist_spec :: reverse_spec :: main_spec::nil.

(** Two little equations about the list_cell predicate *)
Lemma list_cell_eq: forall sh i,
   list_cell LS sh (Vint i) = field_at sh t_struct_list [StructField _head] (Vint i).
Proof.
  intros.
  unfold list_cell; extensionality p; simpl.
  unfold_data_at 1%nat.
  unfold field_at_; simpl.
  admit.
Qed.

(** Here's a loop invariant for use in the body_sumlist proof *)
Definition sumlist_Inv (sh: share) (contents: list int) : environ->mpred :=
          (EX cts: list int, EX t: val, 
            PROP () 
            LOCAL (temp _t t; 
                        temp _s (Vint (Int.sub (sum_int contents) (sum_int cts))))
            SEP ( TT ; `(lseg LS sh (map Vint cts) t nullval))).

(** For every function definition in the C program, prove that the
 ** function-body (in this case, f_sumlist) satisfies its specification
 ** (in this case, sumlist_spec).  
 **)
Lemma body_sumlist: semax_body Vprog Gprog f_sumlist sumlist_spec.
Proof.
(** Here is the standard way to start a function-body proof:  First,
 ** start-function; then for every function-parameter and every
 ** nonadressable local variable ("temp"), do the "name" tactic.
 ** The second argument of "name" is the identifier of the variable
 ** generated by CompCert; the first argument is whatever you like,
 ** how you want the "go_lower" tactic to refer to the value of the variable.
 **)
start_function.
name t _t.
name p_ _p.
name s _s.
name h _h.
forward.  (* s = 0; *) 
forward.  (* t = p; *)
forward_while (sumlist_Inv sh contents)
    (PROP() LOCAL (`((fun v => sum_int contents = force_int v) : val->Prop) (eval_id _s)) SEP(TT)).
(* Prove that current precondition implies loop invariant *)
apply exp_right with contents.
apply exp_right with p.
entailer!.
(* Prove that loop invariant implies typechecking condition *)
entailer!.
(* Prove that invariant && not loop-cond implies postcondition *)
entailer!.
destruct H0 as [H0 _]; specialize (H0 (eq_refl _)).
destruct cts; inv H0; normalize.
(* Prove that loop body preserves invariant *)
assert_PROP (isptr t0); [entailer | ].
drop_LOCAL 0%nat.
focus_SEP 1; apply semax_lseg_nonnull; [ | intros h' r y ? ?].
entailer!.
simpl valinject.
unfold POSTCONDITION, abbreviate.
destruct cts; inv H0.
rewrite list_cell_eq.
forward.  (* h = t->head; *)
forward.  (*  t = t->tail; *)
normalize. subst t0.
forward.  (* s = s + h; *)
(* Prove postcondition of loop body implies loop invariant *)
unfold sumlist_Inv.
apply exp_right with cts.
apply exp_right with y.
entailer!.
   rewrite Int.sub_add_r, Int.add_assoc, (Int.add_commut (Int.neg h)),
             Int.add_neg_zero, Int.add_zero; auto.
(* After the loop *)
forward.  (* return s; *)
Qed.

Definition reverse_Inv (sh: share) (contents: list val) : environ->mpred :=
          (EX cts1: list val, EX cts2 : list val, EX w: val, EX v: val,
            PROP (contents = rev cts1 ++ cts2) 
            LOCAL (temp _w w; temp _v v)
            SEP (`(lseg LS sh cts1 w nullval);
                   `(lseg LS sh cts2 v nullval))).

Lemma body_reverse: semax_body Vprog Gprog f_reverse reverse_spec.
Proof.
start_function.
name p_ _p.
name v_ _v.
name w_ _w.
name t_ _t.
forward.  (* w = NULL; *)
forward.  (* v = p; *)
forward_while (reverse_Inv sh contents)
     (EX w: val, 
      PROP() LOCAL (temp _w w)
      SEP( `(lseg LS sh (rev contents) w nullval))).
(* precondition implies loop invariant *)
unfold reverse_Inv.
apply exp_right with nil.
apply exp_right with contents.
apply exp_right with (Vint (Int.repr 0)).
apply exp_right with p.
entailer!.
(* loop invariant implies typechecking of loop condition *)
entailer!.
(* loop invariant (and not loop condition) implies loop postcondition *)
apply exp_right with w.
entailer!. 
rewrite <- app_nil_end, rev_involutive. auto.
(* loop body preserves invariant *)
assert_PROP (isptr v). entailer. drop_LOCAL 0%nat.
normalize.
focus_SEP 1; apply semax_lseg_nonnull;
        [entailer | intros h r y ? ?].
simpl valinject.
subst cts2.
forward.  (* t = v->tail; *)
forward. (*  v->tail = w; *)
replace_SEP 1 (`(field_at sh t_struct_list [StructField _tail] w v)).
entailer.
forward.  (*  w = v; *)
forward.  (* v = t; *)
(* at end of loop body, re-establish invariant *)
apply exp_right with (h::cts1).
apply exp_right with r.
apply exp_right with v.
apply exp_right with y.
entailer!.
 * rewrite app_ass. auto.
 * rewrite (lseg_unroll _ sh (h::cts1)).
   apply orp_right2.
   unfold lseg_cons.
   apply andp_right.
   + apply prop_right.
      destruct v_0; try contradiction; intro Hx; inv Hx.
   + apply exp_right with h.
      apply exp_right with cts1.
      apply exp_right with w_0.
      entailer!.
* (* after the loop *)
apply extract_exists_pre; intro w.
forward.  (* return w; *)
Qed.

(** The next two lemmas concern the extern global initializer, 
 ** struct list three[] = {{1, three+1}, {2, three+2}, {3, NULL}};
 ** This is equivalent to a linked list of three elements [1,2,3].
 ** Here is how we prove that.
 **)

(** First, "list_init_rep three 0 [1,2,3]" is computes to the initializer sequence,
**      {1, three+1, 2, three+2, 3, NULL}
**) 
Fixpoint list_init_rep (i: ident) (ofs: Z) (l: list int) :=
 match l with 
 | nil => nil
 | j::nil => Init_int32 j :: Init_int32 Int.zero :: nil
 | j::jl => Init_int32 j :: Init_addrof i (Int.repr (ofs+8)) :: list_init_rep i (ofs+8) jl
 end.

(** Second, we prove that in general, no matter how long the list,
 **  an initializer sequence like that is equivalent to a list-segment
 **  terminating in nullval.
**)

Lemma linked_list_in_array:
 forall Delta sh i data idata n,
  (length data > 0)%nat -> 
  (var_types Delta) ! i = None ->
  (glob_types Delta) ! i = Some (tarray t_struct_list n) ->
  idata =  list_init_rep i 0 data ->
   id2pred_star Delta sh (tarray t_struct_list n)
      (eval_var i (tarray t_struct_list n)) 0 idata
  |-- `(lseg LS sh (map Vint data)) (eval_var i (tarray t_struct_list n)) `nullval.
Proof. 
 pose proof I.
 intros.
 subst idata.
 intro rho.
 unfold_lift.
 clear H.
 match goal with |- ?A |-- ?B =>
   assert (A |-- !! isptr (eval_var i (tarray t_struct_list n) rho) && A)
 end.
   destruct data.
   clear - H0; simpl in H0; omega.
   destruct data; simpl list_init_rep; unfold id2pred_star; fold id2pred_star;
   apply andp_right; auto;
   match goal with |- (_ * ?A) rho |-- _ => forget A as JJ end;
   simpl; unfold_lift; entailer!.
 eapply derives_trans; [apply H | clear H; apply derives_extract_prop; intro ].
 replace (eval_var i (tarray t_struct_list n) rho)
   with (offset_val (Int.repr 0) (eval_var i (tarray t_struct_list n) rho))
  by normalize.
 set (ofs:=0). clearbody ofs.
 revert ofs; induction data; intro.
 + simpl in H0. omega.
 + simpl list_init_rep.
   destruct data.
   - clear.
     simpl.
     unfold_lift. 
     rewrite mapsto_isptr; rewrite sepcon_andp_prop'; apply derives_extract_prop; intro.
     destruct (eval_var i (tarray t_struct_list n) rho); inv H. 
     apply @lseg_unroll_nonempty1 with nullval; simpl; auto.
     rewrite mapsto_tuint_tint.
     rewrite list_cell_eq.
     match goal with |- context [mapsto ?sh tint ?v1 ?v2 * emp] =>
       replace (mapsto sh tint v1 v2) with 
           (mapsto sh (tptr t_struct_list) v1 nullval)
      by (symmetry; apply mapsto_null_mapsto_pointer)
     end.
     apply sepcon_derives.
     rewrite mapsto_size_compatible by reflexivity.
    rewrite mapsto_align_compatible by reflexivity.
    normalize. eapply mapsto_field_at'; try reflexivity; try apply I;
   unfold offset_val; repeat rewrite Int.add_assoc.
   simpl in *. forget (Int.unsigned (Int.add i0 (Int.repr ofs))) as j.
   admit.  (* Need a proof that the list cell does not cross the end of memory *)
   simpl in *; auto.
   apply legal_nested_field_cons_lemma; simpl.
   split; [|auto].
   apply legal_nested_field_nil_lemma.
 rewrite @lseg_nil_eq; auto.
 entailer!. compute; auto.
 unfold t_struct_list at 2.
  eapply mapsto_field_at'; try reflexivity; try apply I;
  unfold offset_val; repeat rewrite Int.add_assoc.
  simpl.  admit. (* need to adjust mapsto_field_at' for Tcomp_ptr *)
  normalize.
  simpl. admit.  (* Need a proof that the list cell does not cross the end of memory *)
  simpl. admit.  (* Need to keep track of alignment constraint *)
  solve_legal_nested_field.
 -
  unfold offset_val; repeat rewrite Int.add_assoc.
 spec IHdata. simpl length in H0|-*. repeat rewrite inj_S in H0|-*. omega.
 specialize (IHdata (ofs+8)).
 forget (list_init_rep i (ofs+8)(i0::data)) as rep'.
 unfold id2pred_star. fold id2pred_star.
 simpl init_data2pred'.
 repeat (rewrite H1; rewrite H2). unfold tarray at 2.
  apply @lseg_unroll_nonempty1 with (offset_val (Int.repr (ofs + 8))
       (eval_var i (tarray t_struct_list n) rho)).
  destruct (eval_var i (tarray t_struct_list n) rho); inv H; clear; compute; auto.
  destruct (eval_var i (tarray t_struct_list n) rho); inv H; clear; compute; auto.
 rewrite mapsto_tuint_tint.
 rewrite list_cell_eq.
 destruct (eval_var i (tarray t_struct_list n) rho) eqn:H8; inv H.
 unfold_lift;
 apply sepcon_derives;
 [eapply mapsto_field_at'; try reflexivity; try apply I
 | ]; simpl; try rewrite H8; simpl.
 unfold nested_field_offset2; simpl; reflexivity.
 admit.  (* Need a proof that the list cell does not cross the end of memory *)
 admit.  (* Need to keep track of alignment constraint *)
  solve_legal_nested_field.

 fold (tarray t_struct_list n).
 rewrite H8.
 apply sepcon_derives;
  [eapply mapsto_field_at'; try reflexivity; try apply I
 | ].
 simpl.   admit. (* need to adjust mapsto_field_at' for Tcomp_ptr *)
 simpl. unfold nested_field_offset2; simpl. 
 f_equal. rewrite Int.add_assoc. rewrite Int.add_zero.
 rewrite Int.add_assoc. rewrite add_repr. reflexivity.
 simpl. admit.  (* Need a proof that the list cell does not cross the end of memory *)
 simpl.  admit.  (* Need to keep track of alignment constraint *)
  solve_legal_nested_field.

 replace (ofs + 4 + 4)
   with (ofs+8) by omega.
 apply IHdata.
Qed.

(**  Third, we specialize it to the precondition of our main function: **)
Lemma setup_globals:
  PROP () LOCAL() SEP (
   id2pred_star (func_tycontext f_main Vprog Gprog) Ews (tarray t_struct_list 3)
      (eval_var _three (tarray t_struct_list 3)) 0
      (Init_int32 (Int.repr 1)
       :: Init_addrof _three (Int.repr 8)
          :: Init_int32 (Int.repr 2)
             :: Init_addrof _three (Int.repr 16)
                :: Init_int32 (Int.repr 3) :: Init_int32 (Int.repr 0) :: nil))
  |-- PROP() LOCAL() SEP (
         `(lseg LS Ews (map Vint (Int.repr 1 :: Int.repr 2 :: Int.repr 3 :: nil)))
             (eval_var _three (tarray t_struct_list 3))
            `nullval).
Proof.
 intros;  do 2 (apply andp_derives; [entailer |]).
 apply sepcon_derives; [ |  normalize].
 apply linked_list_in_array; try reflexivity.
 simpl; omega.
Qed. 

Lemma body_main:  semax_body Vprog Gprog f_main main_spec.
Proof.
start_function.
name r _r.
name s _s.
eapply semax_pre0; [apply setup_globals | ].
apply (remember_value (eval_var _three (tarray t_struct_list 3)));
  intro p.
forward_call (*  r = reverse(three); *)
  (Ews, map Vint (Int.repr 1 :: Int.repr 2 :: Int.repr 3 :: nil), p).
 entailer!.
auto with closed.
after_call.
apply (remember_value (eval_id _r)); intro r'.
forward_call  (* s = sumlist(r); *)
   (Ews, Int.repr 3 :: Int.repr 2 :: Int.repr 1 :: nil, r').
entailer!.
auto with closed.
after_call.
forward.  (* return s; *)
Qed.

Existing Instance NullExtension.Espec.

Lemma all_funcs_correct:
  semax_func Vprog Gprog (prog_funct prog) Gprog.
Proof.
unfold Gprog, prog, prog_funct; simpl.
semax_func_skipn.
semax_func_cons body_sumlist.
semax_func_cons body_reverse.
semax_func_cons body_main.
apply semax_func_nil.
Qed.
