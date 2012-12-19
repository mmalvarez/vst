Load loadpath.
(* 
#include <stddef.h>

struct list {int h; struct list *t;};

struct list three[] = {
    {1, three+1}, {2, three+2}, {3, NULL}
};

int sumlist (struct list *p) {
  int s = 0;
  struct list *t = p;
  int h;
  while (t) {
     h = t->h;
     t = t->t;
     s = s + h;
  }
  return s;
}

struct list *reverse (struct list *p) {
  struct list *w, *t, *v;
  w = NULL; 
  v = p;
  while (v) {
    t = v->t;
    v->t = w;
    w = v;
    v = t;
  }
  return w;
}  

int main (void) {
  struct list *r; int s;
  r = reverse(three);
  s = sumlist(r);
  return s;
}
*)
Require Import veric.base.
Require Import Maps.
Import Cop.

Section idents.
Local Open Scope positive_scope.
Definition i_s : ident := 1.
Definition i_h : ident := 2.
Definition i_t : ident := 3.
Definition i_list : ident := 4.
Definition i_sumlist : ident := 5.
Definition i_p : ident := 6.
Definition i_three : ident := 7.
Definition i_reverse : ident := 8.
Definition i_w : ident := 9.
Definition i_v : ident := 10.
Definition i_main : ident := 11.
Definition i_r : ident := 12.
End idents.

Definition t_int := Tint I32 Signed noattr.

Definition t_list :=   Tstruct i_list (Fcons i_h t_int
               (Fcons i_t (Tcomp_ptr i_list noattr)
               Fnil)) noattr.

Definition t_listptr := Tpointer t_list noattr.
Definition t_voidptr := Tpointer Tvoid noattr.

Definition set: forall {A}, ident -> A -> PTree.t A -> PTree.t A := 
 @PTree.set.
Implicit Arguments set [A].

Definition zet {A} (i: Z) (x: A) (m: ZMap.t (option A)) : ZMap.t (option A) := 
 ZMap.set i (Some x) m.
Implicit Arguments zet [A].

Definition f_sumlist : function :=
  mkfunction
 (* return *) t_int
 (* params *) ((i_p, t_listptr)::nil)
 (* vars *)  nil
 (* temps *) ((i_s,t_int)::(i_t,t_listptr)::(i_h,t_int)::nil)
 (* body *) 
  (Ssequence (Sset i_s (Econst_int (Int.repr 0) t_int))
   (Ssequence (Sset i_t (Etempvar i_p t_listptr))
    (  (* Ssequence (Sset i_h (Econst_int (Int.repr 0) t_int)) *)
     (Ssequence 
         (Swhile (Etempvar i_t t_listptr)
          (Ssequence (Sset i_h (Efield (Ederef (Etempvar i_t t_listptr) t_list) i_h t_int))
           (Ssequence (Sset i_t (Efield (Ederef (Etempvar i_t t_listptr) t_list) i_t t_listptr))
            (Sset i_s (Ebinop Oadd (Etempvar i_s t_int) (Etempvar i_h t_int) t_int)))))
   (Sreturn (Some (Etempvar i_s t_int))))))).

Definition f_reverse: function :=
 mkfunction
 (* return *) t_listptr
 (* params *) ((i_p, t_listptr)::nil)
 (* vars *)  nil
 (* temps *) ((i_w,t_listptr)::(i_t,t_listptr)::(i_v,t_listptr)::nil)
 (* body *) 
  (Ssequence (Sset i_w (Ecast (Ecast (Econst_int (Int.repr 0) t_int) t_voidptr) (t_listptr)))
   (Ssequence (Sset i_v (Etempvar i_p t_listptr))
    ( (* Ssequence (Sset i_t (Econst_int (Int.repr 0) t_int)) *)
     (Ssequence 
         (Swhile (Etempvar i_v t_listptr)
          (Ssequence (Sset i_t (Efield (Ederef (Etempvar i_v t_listptr) t_list) i_t t_listptr))
           (Ssequence (Sassign (Efield (Ederef (Etempvar i_v t_listptr) t_list) i_t t_listptr) (Etempvar i_w t_listptr))
           (Ssequence (Sset i_w (Etempvar i_v t_listptr))
            (Sset i_v (Etempvar i_t t_listptr))))))
   (Sreturn (Some (Etempvar i_w t_listptr))))))).

Definition f_main: function :=
 mkfunction
 (* return *) t_int
 (* params *) nil
 (* vars *)  nil
 (* temps *)  ((i_r, t_listptr)::(i_s, t_int)::nil) 
 (* body *) 
  (Ssequence (Scall (Some i_r) 
                        (Eaddrof (Evar i_reverse (Tfunction (Tcons t_listptr Tnil) t_listptr))
                                   (Tpointer (Tfunction (Tcons t_listptr Tnil) t_listptr) noattr))
                        (Ecast (Eaddrof (Evar i_three (Tarray t_list 3 noattr)) (Tpointer (Tarray t_list 3 noattr) noattr)) t_listptr :: nil))
    (Ssequence (Scall (Some i_s) 
                           (Eaddrof (Evar i_sumlist (Tfunction (Tcons t_listptr Tnil) t_int))
                                             (Tpointer  (Tfunction (Tcons t_listptr Tnil) t_int)  noattr))
                          (Etempvar i_r t_listptr::nil)) 
     (Sreturn (Some (Etempvar i_s t_int))))).


Definition b_sumlist : block := 1.
Definition b_reverse : block := 2.
Definition b_main    : block := 3.
Definition b_three : block := 4.

Definition g_symb : PTree.t block :=
 set i_three b_three
  (set i_sumlist b_sumlist
   (set i_reverse b_reverse
    (set i_main b_main
      (PTree.empty block)))).

Definition g_funs: ZMap.t (option fundef) :=
 zet b_sumlist (Internal f_sumlist)
 (zet b_reverse (Internal f_reverse)
  (zet b_main (Internal f_main)
   (ZMap.init None))).

Definition gv_three : globvar type :=
  mkglobvar (Tarray t_list 3 noattr)
       (Init_int32 (Int.repr 1) :: Init_addrof i_three (Int.repr 8) ::
        Init_int32 (Int.repr 2) :: Init_addrof i_three (Int.repr 16) ::
        Init_int32 (Int.repr 3) :: Init_int32 (Int.repr 0) ::
        nil)
        false
        false.

Definition g_vars: ZMap.t (option (globvar type)) :=
 zet b_three gv_three 
   (ZMap.init None).

Definition g_next : block := 5.

Definition prog : program :=
  mkprogram ((i_sumlist, Gfun (Internal f_sumlist))::(i_reverse, Gfun (Internal f_reverse))
                            ::(i_main, Gfun (Internal f_main))
                            ::(i_three, Gvar gv_three)::nil)
                      i_main.

Definition ge : Genv.t fundef type.
 refine (@Genv.mkgenv _ _ g_symb g_funs g_vars g_next
               _ _ _ _ _ _).
unfold g_next; omega.
unfold g_next, g_symb, set; intros.
repeat rewrite PTree.gsspec in H.
repeat if_tac in H; 
try rewrite PTree.gempty in H;
inv H; split; match goal with |- ?A < ?B  =>
          try unfold A; try unfold B; omega
          end.
unfold g_funs, zet,  g_next; intros.
repeat rewrite ZMap.gsspec in H.
repeat if_tac in H; 
try rewrite ZMap.gi in H;
inv H; try match goal with |- _ < ?A < _ =>
          unfold A
         end; omega.
unfold g_vars, zet,  g_next; intros.
repeat rewrite ZMap.gsspec in H.
repeat if_tac in H; 
try rewrite ZMap.gi in H;
inv H; try match goal with |- _ < ?A < _ =>
          unfold A
         end; omega.
unfold g_funs, g_vars, zet; intros; intro; subst b2.
repeat rewrite ZMap.gsspec in *; repeat rewrite ZMap.gi in *; repeat if_tac in H; repeat if_tac in H0;
  inv H; inv H0; match goal with H: _ = _ |- _ => inv H end.
unfold g_symb, set; intros.
repeat rewrite PTree.gsspec in *; repeat rewrite PTree.gempty in *;
 repeat if_tac in H; repeat if_tac in H0; inv H; inv H0; auto.
Defined.



