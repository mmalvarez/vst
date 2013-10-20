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
  WITH sh : share, contents : list int
  PRE [ _p OF (tptr t_struct_list)] 
                       `(lseg LS sh contents) (eval_id _p) `nullval
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
  WITH sh : share, contents : list int
  PRE  [ _p OF (tptr t_struct_list) ] !! writable_share sh &&
              `(lseg LS sh contents) (eval_id _p) `nullval
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

(** The [prog] definition in reverse.v lists several compiler-builtins
 ** in addition to the user-defined sumlist,reverse,main.
 ** The [do_builtins] tactic adds vacuous (but sound) declarations
 ** for them, turning Gprog in to Gtot.
 **)
Definition Gtot := do_builtins (prog_defs prog) ++ Gprog.

(** Two little equations about the list_cell predicate *)
Lemma list_cell_eq: forall sh v i,
   list_cell LS sh v i = field_mapsto sh t_struct_list _head v (Vint i).
Proof.  reflexivity. Qed.

Lemma lift_list_cell_eq:
  forall sh e v,
   `(list_cell LS sh) e v = `(field_mapsto sh t_struct_list _head) e (`Vint v).
Proof. reflexivity. Qed.

(** Here's a loop invariant for use in the body_sumlist proof *)
Definition sumlist_Inv (sh: share) (contents: list int) : environ->mpred :=
          (EX cts: list int, 
            PROP () LOCAL (`(eq (Vint (Int.sub (sum_int contents) (sum_int cts)))) (eval_id _s)) 
            SEP ( TT ; `(lseg LS sh cts) (eval_id _t) `nullval)).

(** For every function definition in the C program, prove that the
 ** function-body (in this case, f_sumlist) satisfies its specification
 ** (in this case, sumlist_spec).  
 **)
Lemma body_sumlist: semax_body Vprog Gtot f_sumlist sumlist_spec.
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
name p _p.
name s _s.
name h _h.
forward.  (* s = 0; *) 
forward.  (* t = p; *)
forward_while (sumlist_Inv sh contents)
    (PROP() LOCAL (`((fun v => sum_int contents = force_int v) : val->Prop) (eval_id _s)) SEP(TT)).
(* Prove that current precondition implies loop invariant *)
unfold sumlist_Inv.
apply exp_right with contents.
entailer!.
(* Prove that loop invariant implies typechecking condition *)
entailer!.
(* Prove that invariant && not loop-cond implies postcondition *)
entailer!.
(* Prove that loop body preserves invariant *)
focus_SEP 1; apply semax_lseg_nonnull; [ | intros h' r y ?].
entailer!.
subst cts.
rewrite lift_list_cell_eq.
forward.  (* h = t->head; *)
forward.  (*  t = t->tail; *)
forward.  (* s = s + h; *)
(* Prove postcondition of loop body implies loop invariant *)
unfold sumlist_Inv.
apply exp_right with r.
entailer!.
   rewrite Int.sub_add_r, Int.add_assoc, (Int.add_commut (Int.neg h)),
             Int.add_neg_zero, Int.add_zero; auto.
(* After the loop *)
forward.  (* return s; *)
Qed.

Definition reverse_Inv (sh: share) (contents: list int) : environ->mpred :=
          (EX cts1: list int, EX cts2 : list int,
            PROP (contents = rev cts1 ++ cts2) 
            LOCAL ()
            SEP (`(lseg LS sh cts1) (eval_id _w) `nullval;
                   `(lseg LS sh cts2) (eval_id _v) `nullval)).

Lemma body_reverse: semax_body Vprog Gtot f_reverse reverse_spec.
Proof.
start_function.
name p _p.
name v _v.
name w _w.
name t _t.
forward.  (* w = NULL; *)
forward.  (* v = p; *)
forward_while (reverse_Inv sh contents)
     (PROP() LOCAL () 
      SEP( `(lseg LS sh (rev contents)) (eval_id _w) `nullval)).
(* precondition implies loop invariant *)
unfold reverse_Inv.
apply exp_right with nil.
apply exp_right with contents.
entailer!.
(* loop invariant implies typechecking of loop condition *)
entailer!.
(* loop invariant (and not loop condition) implies loop postcondition *)
entailer!. rewrite <- app_nil_end, rev_involutive. auto.
(* loop body preserves invariant *)
normalize.
focus_SEP 1; apply semax_lseg_nonnull;
        [entailer | intros h r y ?].
subst cts2.
forward.  (* t = v->tail; *)  
forward. (*  v->tail = w; *)
unfold replace_nth.
fold t_struct_list.
simpl eval_lvalue.
forward.  (*  w = v; *)
simpl. autorewrite with subst.
forward.  (* v = t; *)
(* at end of loop body, re-establish invariant *)
{apply exp_right with (h::cts1).
 apply exp_right with r.
 entailer!.
 * rewrite app_ass. auto.
 * rewrite (lseg_unroll _ sh (h::cts1)).
   cancel.
   apply orp_right2.
   unfold lseg_cons.
   apply andp_right.
   + apply prop_right.
      destruct v0; inv Pv0; simpl; auto.
   + apply exp_right with h.
      apply exp_right with cts1.
      apply exp_right with w0.
      entailer!.
}
(* after the loop *)
forward.  (* return w; *)
Qed.

(** this setup_globals lemma demonstrates that the initialized global variables
 ** satisfy a particular separation-logic predicate.  Here, this lemma is
 ** fairly automated; the "repeat" walks down a list of arbitrary length
 ** (in this case, the initialized array is three elements long).  But
 ** the automation and proof is not very beautiful or self-explanatory;
 ** this needs improvement.
 **)
Lemma setup_globals:
  forall u rho,  tc_environ (func_tycontext f_main Vprog Gtot) rho ->
   main_pre prog u rho
   |-- lseg LS Ews (Int.repr 1 :: Int.repr 2 :: Int.repr 3 :: nil)
             (eval_var _three (Tarray t_struct_list 3 noattr) rho)
      nullval.
Proof.
 unfold main_pre.
 intros _ rho; normalize.
 simpl.
 destruct (globvar_eval_var _ _ _three _ H (eq_refl _) (eq_refl _))
  as [b [z [H97 H99]]]. simpl in *.
 rewrite H97.
 unfold globvar2pred. simpl. rewrite H99. simpl.
 clear.
 rewrite sepcon_emp.
repeat match goal with |- _ * (umapsto _ _ _ ?v * _) |-- _ =>
                apply @lseg_unroll_nonempty1 with v; simpl; auto; 
                apply sepcon_derives; 
                  [rewrite list_cell_eq; umapsto_field_mapsto_tac
                  | ];
                apply sepcon_derives; [umapsto_field_mapsto_tac | ]
           end.
 rewrite lseg_unroll. apply orp_right1.
 unfold ptr_eq;simpl; normalize.
Qed.

Lemma body_main:  semax_body Vprog Gtot f_main main_spec.
Proof.
start_function.
name r _r.
name s _s.
forward.  (*  r = reverse(three); *)
instantiate (1:= (Ews, Int.repr 1 :: Int.repr 2 :: Int.repr 3 :: nil)) in (Value of witness).
 entailer!.
 eapply derives_trans; [apply setup_globals; auto | ].
 cancel.
auto with closed.
forward.  (* s = sumlist(r); *)
instantiate (1:= (Ews, Int.repr 3 :: Int.repr 2 :: Int.repr 1 :: nil)) in (Value of witness).
entailer!.
hnf; auto. (* not sure why this is needed now *)
auto with closed.
forward.  (* return s; *)
Qed.

Existing Instance NullExtension.Espec.

Lemma all_funcs_correct:
  semax_func Vprog Gtot (prog_funct prog) Gtot.
Proof.
unfold Gtot, Gprog, prog, prog_funct; simpl.
repeat (apply semax_func_cons_ext; [ reflexivity | apply semax_external_FF | ]).
apply semax_func_cons; [ reflexivity | apply body_sumlist | ].
apply semax_func_cons; [ reflexivity | apply body_reverse | ].
apply semax_func_cons; [ reflexivity | apply body_main | ].
apply semax_func_nil.
Qed.
