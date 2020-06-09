From Coq Require Import Bool String List Program Arith Lia CRelationClasses.
From MetaCoq.Template Require Import config utils monad_utils EnvironmentTyping.
From MetaCoq.PCUIC Require Import PCUICAst PCUICAstUtils PCUICLiftSubst
     PCUICUnivSubst PCUICEquality PCUICUtils PCUICPosition.

Set Asymmetric Patterns.
Require Import Equations.Type.Relation.
From Equations Require Import Equations.
Import MonadNotation.


Module PCUICLookup := Lookup PCUICTerm PCUICEnvironment.
Include PCUICLookup.

(* todo move *)
Lemma app_cons {A} (x y : list A) a :
  x ++ a :: y = (x ++ [a]) ++ y.
Proof. now rewrite <- app_assoc. Qed.

Lemma OnOne2_All2 {A}:
  forall (ts ts' : list A) P Q,
    OnOne2 P ts ts' ->
    (forall x y, P x y -> Q x y)%type ->
    (forall x, Q x x) ->
    All2 Q ts ts'.
Proof.
  intros ts ts' P Q X.
  induction X; intuition auto.
  constructor; auto. now apply All2_refl.
Qed.

Ltac OnOne2_All2 :=
  match goal with
  | [ H : OnOne2 ?P ?ts ?ts' |- All2 ?Q ?ts ?ts' ] =>
    unshelve eapply (OnOne2_All2 _ _ P Q H); simpl; intros
  end.


(** * Definition of β-reduction, η-reduction, conversion and cumulativity *)

(** ** β Reduction *)

(** *** Helper functions for reduction *)

Definition fix_subst (l : mfixpoint term) :=
  let fix aux n :=
      match n with
      | 0 => []
      | S n => tFix l n :: aux n
      end
  in aux (List.length l).

Definition unfold_fix (mfix : mfixpoint term) (idx : nat) :=
  match List.nth_error mfix idx with
  | Some d => Some (d.(rarg), subst0 (fix_subst mfix) d.(dbody))
  | None => None
  end.

Definition cofix_subst (l : mfixpoint term) :=
  let fix aux n :=
      match n with
      | 0 => []
      | S n => tCoFix l n :: aux n
      end
  in aux (List.length l).

Definition unfold_cofix (mfix : mfixpoint term) (idx : nat) :=
  match List.nth_error mfix idx with
  | Some d => Some (d.(rarg), subst0 (cofix_subst mfix) d.(dbody))
  | None => None
  end.

Definition is_constructor n ts :=
  match List.nth_error ts n with
  | Some a => isConstruct_app a
  | None => false
  end.

Lemma fix_subst_length mfix : #|fix_subst mfix| = #|mfix|.
Proof.
  unfold fix_subst. generalize (tFix mfix). intros.
  induction mfix; simpl; auto.
Qed.

Lemma cofix_subst_length mfix : #|cofix_subst mfix| = #|mfix|.
Proof.
  unfold cofix_subst. generalize (tCoFix mfix). intros.
  induction mfix; simpl; auto.
Qed.

Lemma fix_context_length mfix : #|fix_context mfix| = #|mfix|.
Proof. unfold fix_context. now rewrite List.rev_length, mapi_length. Qed.

Definition tDummy := tVar ""%string.

Definition iota_red npar c args brs :=
  (mkApps (snd (List.nth c brs (0, tDummy))) (List.skipn npar args)).


(** *** One step strong beta-zeta-iota-fix-delta reduction

  Inspired by the reduction relation from Coq in Coq [Barras'99].
*)

Local Open Scope type_scope.
Arguments OnOne2 {A} P%type l l'.

Inductive red1 (Σ : global_env) (Γ : context) : term -> term -> Type :=
(** Reductions *)
(** Beta *)
| red_beta na t b a :
    red1 Σ Γ (tApp (tLambda na t b) a) (subst10 a b)

(** Let *)
| red_zeta na b t b' :
    red1 Σ Γ (tLetIn na b t b') (subst10 b b')

| red_rel i body :
    option_map decl_body (nth_error Γ i) = Some (Some body) ->
    red1 Σ Γ (tRel i) (lift0 (S i) body)

(** Case *)
| red_iota ind pars c u args p brs :
    red1 Σ Γ (tCase (ind, pars) p (mkApps (tConstruct ind c u) args) brs)
         (iota_red pars c args brs)

(** Fix unfolding, with guard *)
| red_fix mfix idx args narg fn :
    unfold_fix mfix idx = Some (narg, fn) ->
    is_constructor narg args = true ->
    red1 Σ Γ (mkApps (tFix mfix idx) args) (mkApps fn args)

(** CoFix-case unfolding *)
| red_cofix_case ip p mfix idx args narg fn brs :
    unfold_cofix mfix idx = Some (narg, fn) ->
    red1 Σ Γ (tCase ip p (mkApps (tCoFix mfix idx) args) brs)
         (tCase ip p (mkApps fn args) brs)

(** CoFix-proj unfolding *)
| red_cofix_proj p mfix idx args narg fn :
    unfold_cofix mfix idx = Some (narg, fn) ->
    red1 Σ Γ (tProj p (mkApps (tCoFix mfix idx) args))
         (tProj p (mkApps fn args))

(** Constant unfolding *)
| red_delta c decl body (isdecl : declared_constant Σ c decl) u :
    decl.(cst_body) = Some body ->
    red1 Σ Γ (tConst c u) (subst_instance_constr u body)

(** Proj *)
| red_proj i pars narg args k u arg:
    nth_error args (pars + narg) = Some arg ->
    red1 Σ Γ (tProj (i, pars, narg) (mkApps (tConstruct i k u) args)) arg


| abs_red_l na M M' N : red1 Σ Γ M M' -> red1 Σ Γ (tLambda na M N) (tLambda na M' N)
| abs_red_r na M M' N : red1 Σ (Γ ,, vass na N) M M' -> red1 Σ Γ (tLambda na N M) (tLambda na N M')

| letin_red_def na b t b' r : red1 Σ Γ b r -> red1 Σ Γ (tLetIn na b t b') (tLetIn na r t b')
| letin_red_ty na b t b' r : red1 Σ Γ t r -> red1 Σ Γ (tLetIn na b t b') (tLetIn na b r b')
| letin_red_body na b t b' r : red1 Σ (Γ ,, vdef na b t) b' r -> red1 Σ Γ (tLetIn na b t b') (tLetIn na b t r)

| case_red_pred ind p p' c brs : red1 Σ Γ p p' -> red1 Σ Γ (tCase ind p c brs) (tCase ind p' c brs)
| case_red_discr ind p c c' brs : red1 Σ Γ c c' -> red1 Σ Γ (tCase ind p c brs) (tCase ind p c' brs)
| case_red_brs ind p c brs brs' :
    OnOne2 (on_Trel_eq (red1 Σ Γ) snd fst) brs brs' ->
    red1 Σ Γ (tCase ind p c brs) (tCase ind p c brs')

| proj_red p c c' : red1 Σ Γ c c' -> red1 Σ Γ (tProj p c) (tProj p c')

| app_red_l M1 N1 M2 : red1 Σ Γ M1 N1 -> red1 Σ Γ (tApp M1 M2) (tApp N1 M2)
| app_red_r M2 N2 M1 : red1 Σ Γ M2 N2 -> red1 Σ Γ (tApp M1 M2) (tApp M1 N2)

| prod_red_l na M1 M2 N1 : red1 Σ Γ M1 N1 -> red1 Σ Γ (tProd na M1 M2) (tProd na N1 M2)
| prod_red_r na M2 N2 M1 : red1 Σ (Γ ,, vass na M1) M2 N2 ->
                               red1 Σ Γ (tProd na M1 M2) (tProd na M1 N2)

| evar_red ev l l' : OnOne2 (red1 Σ Γ) l l' -> red1 Σ Γ (tEvar ev l) (tEvar ev l')

| fix_red_ty mfix0 mfix1 idx :
    OnOne2 (on_Trel_eq (red1 Σ Γ) dtype (fun x => (dname x, dbody x, rarg x))) mfix0 mfix1 ->
    red1 Σ Γ (tFix mfix0 idx) (tFix mfix1 idx)

| fix_red_body mfix0 mfix1 idx :
    OnOne2 (on_Trel_eq (red1 Σ (Γ ,,, fix_context mfix0)) dbody (fun x => (dname x, dtype x, rarg x)))
           mfix0 mfix1 ->
    red1 Σ Γ (tFix mfix0 idx) (tFix mfix1 idx)

| cofix_red_ty mfix0 mfix1 idx :
    OnOne2 (on_Trel_eq (red1 Σ Γ) dtype (fun x => (dname x, dbody x, rarg x))) mfix0 mfix1 ->
    red1 Σ Γ (tCoFix mfix0 idx) (tCoFix mfix1 idx)

| cofix_red_body mfix0 mfix1 idx :
    OnOne2 (on_Trel_eq (red1 Σ (Γ ,,, fix_context mfix0)) dbody (fun x => (dname x, dtype x, rarg x))) mfix0 mfix1 ->
    red1 Σ Γ (tCoFix mfix0 idx) (tCoFix mfix1 idx).

Lemma red1_ind_all :
  forall (Σ : global_env) (P : context -> term -> term -> Type),

       (forall (Γ : context) (na : name) (t b a : term),
        P Γ (tApp (tLambda na t b) a) (b {0 := a})) ->

       (forall (Γ : context) (na : name) (b t b' : term), P Γ (tLetIn na b t b') (b' {0 := b})) ->

       (forall (Γ : context) (i : nat) (body : term),
        option_map decl_body (nth_error Γ i) = Some (Some body) -> P Γ (tRel i) ((lift0 (S i)) body)) ->

       (forall (Γ : context) (ind : inductive) (pars c : nat) (u : Instance.t) (args : list term)
          (p : term) (brs : list (nat * term)),
        P Γ (tCase (ind, pars) p (mkApps (tConstruct ind c u) args) brs) (iota_red pars c args brs)) ->

       (forall (Γ : context) (mfix : mfixpoint term) (idx : nat) (args : list term) (narg : nat) (fn : term),
        unfold_fix mfix idx = Some (narg, fn) ->
        is_constructor narg args = true -> P Γ (mkApps (tFix mfix idx) args) (mkApps fn args)) ->

       (forall (Γ : context) (ip : inductive * nat) (p : term) (mfix : mfixpoint term) (idx : nat)
          (args : list term) (narg : nat) (fn : term) (brs : list (nat * term)),
        unfold_cofix mfix idx = Some (narg, fn) ->
        P Γ (tCase ip p (mkApps (tCoFix mfix idx) args) brs) (tCase ip p (mkApps fn args) brs)) ->

       (forall (Γ : context) (p : projection) (mfix : mfixpoint term) (idx : nat) (args : list term)
          (narg : nat) (fn : term),
        unfold_cofix mfix idx = Some (narg, fn) -> P Γ (tProj p (mkApps (tCoFix mfix idx) args)) (tProj p (mkApps fn args))) ->

       (forall (Γ : context) c (decl : constant_body) (body : term),
        declared_constant Σ c decl ->
        forall u : Instance.t, cst_body decl = Some body -> P Γ (tConst c u) (subst_instance_constr u body)) ->

       (forall (Γ : context) (i : inductive) (pars narg : nat) (args : list term) (k : nat) (u : Instance.t)
         (arg : term),
           nth_error args (pars + narg) = Some arg ->
           P Γ (tProj (i, pars, narg) (mkApps (tConstruct i k u) args)) arg) ->

       (forall (Γ : context) (na : name) (M M' N : term),
        red1 Σ Γ M M' -> P Γ M M' -> P Γ (tLambda na M N) (tLambda na M' N)) ->

       (forall (Γ : context) (na : name) (M M' N : term),
        red1 Σ (Γ,, vass na N) M M' -> P (Γ,, vass na N) M M' -> P Γ (tLambda na N M) (tLambda na N M')) ->

       (forall (Γ : context) (na : name) (b t b' r : term),
        red1 Σ Γ b r -> P Γ b r -> P Γ (tLetIn na b t b') (tLetIn na r t b')) ->

       (forall (Γ : context) (na : name) (b t b' r : term),
        red1 Σ Γ t r -> P Γ t r -> P Γ (tLetIn na b t b') (tLetIn na b r b')) ->

       (forall (Γ : context) (na : name) (b t b' r : term),
        red1 Σ (Γ,, vdef na b t) b' r -> P (Γ,, vdef na b t) b' r -> P Γ (tLetIn na b t b') (tLetIn na b t r)) ->

       (forall (Γ : context) (ind : inductive * nat) (p p' c : term) (brs : list (nat * term)),
        red1 Σ Γ p p' -> P Γ p p' -> P Γ (tCase ind p c brs) (tCase ind p' c brs)) ->

       (forall (Γ : context) (ind : inductive * nat) (p c c' : term) (brs : list (nat * term)),
        red1 Σ Γ c c' -> P Γ c c' -> P Γ (tCase ind p c brs) (tCase ind p c' brs)) ->

       (forall (Γ : context) (ind : inductive * nat) (p c : term) (brs brs' : list (nat * term)),
           OnOne2 (on_Trel_eq (Trel_conj (red1 Σ Γ) (P Γ)) snd fst) brs brs' ->
           P Γ (tCase ind p c brs) (tCase ind p c brs')) ->

       (forall (Γ : context) (p : projection) (c c' : term), red1 Σ Γ c c' -> P Γ c c' ->
                                                             P Γ (tProj p c) (tProj p c')) ->

       (forall (Γ : context) (M1 N1 : term) (M2 : term), red1 Σ Γ M1 N1 -> P Γ M1 N1 ->
                                                         P Γ (tApp M1 M2) (tApp N1 M2)) ->

       (forall (Γ : context) (M2 N2 : term) (M1 : term), red1 Σ Γ M2 N2 -> P Γ M2 N2 ->
                                                         P Γ (tApp M1 M2) (tApp M1 N2)) ->

       (forall (Γ : context) (na : name) (M1 M2 N1 : term),
        red1 Σ Γ M1 N1 -> P Γ M1 N1 -> P Γ (tProd na M1 M2) (tProd na N1 M2)) ->

       (forall (Γ : context) (na : name) (M2 N2 M1 : term),
        red1 Σ (Γ,, vass na M1) M2 N2 -> P (Γ,, vass na M1) M2 N2 -> P Γ (tProd na M1 M2) (tProd na M1 N2)) ->

       (forall (Γ : context) (ev : nat) (l l' : list term),
           OnOne2 (Trel_conj (red1 Σ Γ) (P Γ)) l l' -> P Γ (tEvar ev l) (tEvar ev l')) ->

       (forall (Γ : context) (mfix0 mfix1 : list (def term)) (idx : nat),
        OnOne2 (on_Trel_eq (Trel_conj (red1 Σ Γ) (P Γ)) dtype (fun x => (dname x, dbody x, rarg x))) mfix0 mfix1 ->
        P Γ (tFix mfix0 idx) (tFix mfix1 idx)) ->

       (forall (Γ : context) (mfix0 mfix1 : list (def term)) (idx : nat),
        OnOne2 (on_Trel_eq (Trel_conj (red1 Σ (Γ ,,, fix_context mfix0))
                                      (P (Γ ,,, fix_context mfix0))) dbody
                           (fun x => (dname x, dtype x, rarg x))) mfix0 mfix1 ->
        P Γ (tFix mfix0 idx) (tFix mfix1 idx)) ->

       (forall (Γ : context) (mfix0 mfix1 : list (def term)) (idx : nat),
        OnOne2 (on_Trel_eq (Trel_conj (red1 Σ Γ) (P Γ)) dtype (fun x => (dname x, dbody x, rarg x))) mfix0 mfix1 ->
        P Γ (tCoFix mfix0 idx) (tCoFix mfix1 idx)) ->

       (forall (Γ : context) (mfix0 mfix1 : list (def term)) (idx : nat),
        OnOne2 (on_Trel_eq (Trel_conj (red1 Σ (Γ ,,, fix_context mfix0))
                                      (P (Γ ,,, fix_context mfix0))) dbody
                           (fun x => (dname x, dtype x, rarg x))) mfix0 mfix1 ->
        P Γ (tCoFix mfix0 idx) (tCoFix mfix1 idx)) ->

       forall (Γ : context) (t t0 : term), red1 Σ Γ t t0 -> P Γ t t0.
Proof.
  intros. rename X26 into Xlast. revert Γ t t0 Xlast.
  fix aux 4. intros Γ t T.
  move aux at top.
  destruct 1; match goal with
              | |- P _ (tFix _ _) (tFix _ _) => idtac
              | |- P _ (tCoFix _ _) (tCoFix _ _) => idtac
              | |- P _ (mkApps (tFix _ _) _) _ => idtac
              | |- P _ (tCase _ _ (mkApps (tCoFix _ _) _) _) _ => idtac
              | |- P _ (tProj _ (mkApps (tCoFix _ _) _)) _ => idtac
              | H : _ |- _ => eapply H; eauto
              end.
  - eapply X3; eauto.
  - eapply X4; eauto.
  - eapply X5; eauto.

  - revert brs brs' o.
    fix auxl 3.
    intros l l' Hl. destruct Hl.
    constructor. intuition auto. constructor. intuition auto.

  - revert l l' o.
    fix auxl 3.
    intros l l' Hl. destruct Hl.
    constructor. split; auto.
    constructor. auto.

  - eapply X22.
    revert mfix0 mfix1 o; fix auxl 3; intros l l' Hl; destruct Hl;
      constructor; try split; auto; intuition.

  - eapply X23.
    revert o. generalize (fix_context mfix0). intros c Xnew.
    revert mfix0 mfix1 Xnew; fix auxl 3; intros l l' Hl;
    destruct Hl; constructor; try split; auto; intuition.

  - eapply X24.
    revert mfix0 mfix1 o.
    fix auxl 3; intros l l' Hl; destruct Hl;
      constructor; try split; auto; intuition.

  - eapply X25.
    revert o. generalize (fix_context mfix0). intros c new.
    revert mfix0 mfix1 new; fix auxl 3; intros l l' Hl; destruct Hl;
      constructor; try split; auto; intuition.
Defined.



(** ** η Expansion *)

Notation " 'eta_redex' na A t " := (tLambda na A (tApp (lift0 1 t) (tRel 0)))
                   (at level 30, na at level 0, A at level 0, t at level 0).

Inductive eta1 : term -> term -> Type :=
(* Reduction at head *)
| eta_red na t A :
    eta1 (eta_redex na A t) t

(* Congruence *)
| abs_eta_l na M M' N : eta1 M M' -> eta1 (tLambda na M N) (tLambda na M' N)
| abs_eta_r na M M' N : eta1 M M' -> eta1 (tLambda na N M) (tLambda na N M')

| letin_eta_def na b t b' r : eta1 b r -> eta1 (tLetIn na b t b') (tLetIn na r t b')
| letin_eta_ty na b t b' r : eta1 t r -> eta1 (tLetIn na b t b') (tLetIn na b r b')
| letin_eta_body na b t b' r : eta1 b' r -> eta1 (tLetIn na b t b') (tLetIn na b t r)

| case_eta_peta ind p p' c brs : eta1 p p' -> eta1 (tCase ind p c brs) (tCase ind p' c brs)
| case_eta_discr ind p c c' brs : eta1 c c' -> eta1 (tCase ind p c brs) (tCase ind p c' brs)
| case_eta_brs ind p c brs brs' :
    OnOne2 (on_Trel_eq eta1 snd fst) brs brs' ->
    eta1 (tCase ind p c brs) (tCase ind p c brs')

| proj_eta p c c' : eta1 c c' -> eta1 (tProj p c) (tProj p c')

| app_eta_l M1 N1 M2 : eta1 M1 N1 -> eta1 (tApp M1 M2) (tApp N1 M2)
| app_eta_r M2 N2 M1 : eta1 M2 N2 -> eta1 (tApp M1 M2) (tApp M1 N2)

| prod_eta_l na M1 M2 N1 : eta1 M1 N1 -> eta1 (tProd na M1 M2) (tProd na N1 M2)
| prod_eta_r na M2 N2 M1 : eta1 M2 N2 ->
                               eta1 (tProd na M1 M2) (tProd na M1 N2)

| evar_eta ev l l' : OnOne2 eta1 l l' -> eta1 (tEvar ev l) (tEvar ev l')

| fix_eta_ty mfix0 mfix1 idx :
    OnOne2 (on_Trel_eq eta1 dtype (fun x => (dname x, dbody x, rarg x))) mfix0 mfix1 ->
    eta1 (tFix mfix0 idx) (tFix mfix1 idx)

| fix_eta_body mfix0 mfix1 idx :
    OnOne2 (on_Trel_eq eta1 dbody (fun x => (dname x, dtype x, rarg x)))
           mfix0 mfix1 ->
    eta1 (tFix mfix0 idx) (tFix mfix1 idx)

| cofix_eta_ty mfix0 mfix1 idx :
    OnOne2 (on_Trel_eq eta1 dtype (fun x => (dname x, dbody x, rarg x))) mfix0 mfix1 ->
    eta1 (tCoFix mfix0 idx) (tCoFix mfix1 idx)

| cofix_eta_body mfix0 mfix1 idx :
    OnOne2 (on_Trel_eq eta1 dbody (fun x => (dname x, dtype x, rarg x))) mfix0 mfix1 ->
    eta1 (tCoFix mfix0 idx) (tCoFix mfix1 idx).

Lemma eta1_ind_all (P : term -> term -> Type) :

  (forall na (t A : term),
   P (eta_redex na A t) t) ->
  
  (forall na (M M' N : term),
   eta1 M M' -> P M M' -> P (tLambda na M N) (tLambda na M' N)) ->
  
  (forall na (M M' N : term),
   eta1 M M' -> P M M' -> P (tLambda na N M) (tLambda na N M')) ->
  
  (forall na (b t b' r : term),
   eta1 b r -> P b r -> P (tLetIn na b t b') (tLetIn na r t b')) ->
  
  (forall na (b t b' r : term),
   eta1 t r -> P t r -> P (tLetIn na b t b') (tLetIn na b r b')) ->
  
  (forall na (b t b' r : term),
   eta1 b' r -> P b' r -> P (tLetIn na b t b') (tLetIn na b t r)) ->
  
  (forall (ind : inductive * nat) (p p' c : term) (brs : list (nat * term)),
   eta1 p p' -> P p p' -> P (tCase ind p c brs) (tCase ind p' c brs)) ->
  
  (forall (ind : inductive * nat) (p c c' : term) (brs : list (nat * term)),
   eta1 c c' -> P c c' -> P (tCase ind p c brs) (tCase ind p c' brs)) ->
  
  (forall (ind : inductive * nat) (p c : term) (brs brs' : list (nat * term)),
      OnOne2 (on_Trel_eq (Trel_conj eta1 P) snd fst) brs brs' ->
      P (tCase ind p c brs) (tCase ind p c brs')) ->
  
  (forall (p : projection) (c c' : term), eta1 c c' -> P c c' ->
                                                        P (tProj p c) (tProj p c')) ->
  
  (forall (M1 N1 : term) (M2 : term), eta1 M1 N1 -> P M1 N1 ->
                                                    P (tApp M1 M2) (tApp N1 M2)) ->
  
  (forall (M2 N2 : term) (M1 : term), eta1 M2 N2 -> P M2 N2 ->
                                                    P (tApp M1 M2) (tApp M1 N2)) ->
  
  (forall na (M1 M2 N1 : term),
   eta1 M1 N1 -> P M1 N1 -> P (tProd na M1 M2) (tProd na N1 M2)) ->
  
  (forall na (M2 N2 M1 : term),
   eta1 M2 N2 -> P M2 N2 -> P (tProd na M1 M2) (tProd na M1 N2)) ->
  
  (forall (ev : nat) (l l' : list term),
      OnOne2 (Trel_conj eta1 P) l l' -> P (tEvar ev l) (tEvar ev l')) ->
  
  (forall (mfix0 mfix1 : list (def term)) (idx : nat),
   OnOne2 (on_Trel_eq (Trel_conj eta1 P) dtype (fun x => (dname x, dbody x, rarg x))) mfix0 mfix1 ->
   P (tFix mfix0 idx) (tFix mfix1 idx)) ->
  
  (forall (mfix0 mfix1 : list (def term)) (idx : nat),
   OnOne2 (on_Trel_eq (Trel_conj eta1
                                 P) dbody
                      (fun x => (dname x, dtype x, rarg x))) mfix0 mfix1 ->
   P (tFix mfix0 idx) (tFix mfix1 idx)) ->
  
  (forall (mfix0 mfix1 : list (def term)) (idx : nat),
   OnOne2 (on_Trel_eq (Trel_conj eta1 P) dtype (fun x => (dname x, dbody x, rarg x))) mfix0 mfix1 ->
   P (tCoFix mfix0 idx) (tCoFix mfix1 idx)) ->
  
  (forall (mfix0 mfix1 : list (def term)) (idx : nat),
   OnOne2 (on_Trel_eq (Trel_conj eta1
                                 P) dbody
                      (fun x => (dname x, dtype x, rarg x))) mfix0 mfix1 ->
   P (tCoFix mfix0 idx) (tCoFix mfix1 idx)) ->
  
  forall (t t0 : term), eta1 t t0 -> P t t0.
Proof.
  intros. rename X18 into Xlast. revert t t0 Xlast.
  fix aux 3. intros t T.
  move aux at top.
  destruct 1; match goal with
              | |- P (tFix _ _) (tFix _ _) => idtac
              | |- P (tCoFix _ _) (tCoFix _ _) => idtac
              | |- P (mkApps (tFix _ _) _) _ => idtac
              | |- P (tCase _ _ (mkApps (tCoFix _ _) _) _) _ => idtac
              | |- P (tProj _ (mkApps (tCoFix _ _) _)) _ => idtac
              | H : _ |- _ => eapply H; eauto
              end.

  - revert brs brs' o.
    fix auxl 3.
    intros l l' Hl. destruct Hl.
    constructor. intuition auto. constructor. intuition auto.

  - revert l l' o.
    fix auxl 3.
    intros l l' Hl. destruct Hl.
    constructor. split; auto.
    constructor. auto.

  - eapply X14.
    revert mfix0 mfix1 o; fix auxl 3; intros l l' Hl; destruct Hl;
      constructor; try split; auto; intuition.

  - eapply X15.
    revert o. generalize (fix_context mfix0). intros c Xnew.
    revert mfix0 mfix1 Xnew; fix auxl 3; intros l l' Hl;
    destruct Hl; constructor; try split; auto; intuition.

  - eapply X16.
    revert mfix0 mfix1 o.
    fix auxl 3; intros l l' Hl; destruct Hl;
      constructor; try split; auto; intuition.

  - eapply X17.
    revert o. generalize (fix_context mfix0). intros c new.
    revert mfix0 mfix1 new; fix auxl 3; intros l l' Hl; destruct Hl;
      constructor; try split; auto; intuition.
Defined.


Definition red Σ Γ := clos_refl_trans (red1 Σ Γ).

(* [eta u v] states v is a reduction of u *)
Definition eta := clos_refl_trans eta1.

Definition beta_eta1 Σ Γ := union (red1 Σ Γ) eta1.
Definition beta_eta Σ Γ := clos_refl_trans (beta_eta1 Σ Γ).

Definition beu1 Σ Γ := union (beta_eta1 Σ Γ) upto_domain.
Definition beu Σ Γ := clos_refl_trans (beu1 Σ Γ).



(** ** Cumulativity and conversion *)

(** Two terms are in cumulativity/conversion relation if they β-reduce/η-expand
    to two equal terms up to universes and in the cumul/conv relation *)   

Definition cumul `{checker_flags} (Σ : global_env_ext) (Γ : context) (t u : term)
  := ∑ t' u', beu Σ Γ t t' ×
              leq_term Σ t' u' ×
              beu Σ Γ u u'.

Definition conv `{checker_flags} (Σ : global_env_ext) (Γ : context) (t u : term)
  := ∑ t' u', beu Σ Γ t t' ×
              eq_term Σ t' u' ×
              beu Σ Γ u u'.

Notation " Σ ;;; Γ |- t <= u " := (cumul Σ Γ t u) (at level 50, Γ, t, u at next level).
Notation " Σ ;;; Γ |- t = u " := (conv Σ Γ t u) (at level 50, Γ, t, u at next level).



(** ** Basic Properties of beta *)

(* todo move *)
Instance clos_refl_trans_refl {A} (R : relation A) : Reflexive (clos_refl_trans R).
Proof. constructor 2. Defined.

Instance clos_refl_trans_trans {A} (R : relation A)
  : Transitive (clos_refl_trans R).
Proof. econstructor 3; eassumption. Defined.


Lemma refl_red Σ Γ M : red Σ Γ M M.
Proof. constructor 2. Qed.

Lemma trans_red Σ Γ M N P : red Σ Γ M P -> red1 Σ Γ P N -> red Σ Γ M N.
Proof.
  intros. econstructor 3; tea.
  now constructor.
Qed.

Lemma red1_red (Σ : global_env) Γ t u : red1 Σ Γ t u -> red Σ Γ t u.
Proof. now constructor. Qed.
Hint Resolve red1_red refl_red : core pcuic.


Lemma red_step Σ Γ t u v : red1 Σ Γ t u -> red Σ Γ u v -> red Σ Γ t v.
Proof.
  intros; etransitivity; tea.
  now constructor.
Qed.

Lemma red_trans Σ Γ t u v : red Σ Γ t u -> red Σ Γ u v -> red Σ Γ t v.
Proof.
  econstructor 3; tea.
Defined.


(** ** Basic Properties of eta *)

Lemma eta1_eta M N : eta1 M N -> eta M N.
Proof. now constructor. Defined.

Lemma eta_refl M : eta M M.
Proof. constructor 2. Defined.

Lemma eta_trans M N P : eta M N -> eta N P -> eta M P.
Proof. econstructor 3; eassumption. Defined.


Instance eta_refl' : Reflexive eta := eta_refl.
Instance eta_trans' : Transitive eta := eta_trans.

Hint Constructors eta1 : eta.
Hint Resolve eta1_eta eta_refl eta_trans : eta.

Ltac eta := match goal with
            | |- _ × _ => split
            | _ => idtac 
            end; auto with eta.


(** *** Congruences for eta *)

Lemma eta_Evar n l l' :
  All2 eta l l' ->
  eta (tEvar n l) (tEvar n l').
Proof.
  intro X.
  enough (forall l0, eta (tEvar n (l0 ++ l)) (tEvar n (l0 ++ l'))) as XX;
    [apply (XX [])|].
  induction X; auto with eta.
  intro l0; transitivity (tEvar n (l0 ++ y :: l)); eauto with eta.
  - clear -r.
    induction r; [econstructor 1|econstructor 2|econstructor 3];
      eauto with eta.
    constructor. apply OnOne2_app. now constructor.
  - now rewrite (app_cons l0 l), (app_cons l0 l').
Defined.

Lemma eta_Prod na M M' N N' :
  eta M M' -> eta N N' ->
  eta (tProd na M N) (tProd na M' N').
Proof.
  transitivity (tProd na M' N).
  - induction X; eauto with eta.
  - induction X0; eauto with eta.
Defined.

Lemma eta_Lambda na M M' N N' :
  eta M M' -> eta N N' ->
  eta (tLambda na M N) (tLambda na M' N').
Proof.
  transitivity (tLambda na M' N).
  - induction X; eauto with eta.
  - induction X0; eauto with eta.
Defined.

Lemma eta_LetIn na d0 d1 t0 t1 b0 b1 :
  eta d0 d1 -> eta t0 t1 -> eta b0 b1 ->
  eta (tLetIn na d0 t0 b0) (tLetIn na d1 t1 b1).
Proof.
  transitivity (tLetIn na d1 t0 b0).
  - induction X; eauto with eta.
  - transitivity (tLetIn na d1 t1 b0).
    + induction X0; eauto with eta.
    + induction X1; eauto with eta.
Defined.

Lemma eta_App M M' N N' :
  eta M M' -> eta N N' ->
  eta (tApp M N) (tApp M' N').
Proof.
  transitivity (tApp M' N).
  - induction X; eauto with eta.
  - induction X0; eauto with eta.
Defined.

Lemma eta_Case indn p c brs p' c' brs' :
  eta p p' ->
  eta c c' ->
  All2 (on_Trel_eq (eta) snd fst) brs brs' ->
  eta (tCase indn p c brs) (tCase indn p' c' brs').
Proof.
  transitivity (tCase indn p' c brs). {
    induction X; eauto with eta. }
  transitivity (tCase indn p' c' brs). {
    induction X0; eauto with eta. }
  clear -X1. rename X1 into X.
  enough (forall brs0, eta (tCase indn p' c'  (brs0 ++ brs))
                      (tCase indn p' c'  (brs0 ++ brs'))) as XX;
    [apply (XX [])|].
  induction X; auto with eta.
  destruct x as [n ?], y as [n0 ?], r as [r ?]; cbn in *; subst.
  intro brs0.
  transitivity (tCase indn p' c' (brs0 ++ (n0, t0) :: l)); eauto with eta.
  - induction r; [econstructor 1| | ]; eauto with eta.
    constructor. apply OnOne2_app. now constructor.
  - now rewrite (app_cons brs0 l), (app_cons brs0 l').
Defined.

Lemma eta_Case0 indn p c brs p' c' :
  eta p p' ->
  eta c c' ->
  eta (tCase indn p c brs) (tCase indn p' c' brs).
Proof.
  intros; apply eta_Case; tea.
  apply All2_refl. split; reflexivity.
Defined.

Lemma eta_Proj p t0 t1 :
  eta t0 t1 -> 
  eta (tProj p t0) (tProj p t1).
Proof.
  induction 1; eauto with eta.
Defined.

Lemma eta_Fix mfix mfix' idx :
  All2 (fun d0 d1 => eta (dtype d0) (dtype d1)
                  × eta (dbody d0) (dbody d1)
                  × dname d0 = dname d1
                  × rarg d0 = rarg d1) mfix mfix' ->
  eta (tFix mfix idx) (tFix mfix' idx).
Proof.
  intro X.
  enough (forall mfix0, eta (tFix (mfix0 ++ mfix) idx) (tFix (mfix0 ++ mfix') idx))
    as XX; [apply (XX [])|].
  induction X; auto with eta.
  destruct x, y; rdestruct r; cbn in *; subst.
  intro mfix0.
  transitivity (tFix (mfix0 ++ {| dname := dname0; dtype := dtype0;
                                  dbody := dbody; rarg := rarg0 |} :: l) idx). {
    induction r; [econstructor 1| | ]; eauto with eta.
    constructor. apply OnOne2_app. now constructor. }
  transitivity (tFix (mfix0 ++ {| dname := dname0; dtype := dtype0;
                                  dbody := dbody0; rarg := rarg0 |} :: l) idx). {
    induction r0; [econstructor 1| | ]; eauto with eta.
    eapply fix_eta_body. apply OnOne2_app. now constructor. }
  now rewrite (app_cons mfix0 l), (app_cons mfix0 l').
Defined.

Lemma eta_CoFix mfix mfix' idx :
  All2 (fun d0 d1 => eta (dtype d0) (dtype d1)
                  × eta (dbody d0) (dbody d1)
                  × dname d0 = dname d1
                  × rarg d0 = rarg d1) mfix mfix' ->
  eta (tCoFix mfix idx) (tCoFix mfix' idx).
Proof.
  intro X.
  enough (forall mfix0, eta (tCoFix (mfix0 ++ mfix) idx) (tCoFix (mfix0 ++ mfix') idx))
    as XX; [apply (XX [])|].
  induction X; auto with eta.
  destruct x, y; rdestruct r; cbn in *; subst.
  intro mfix0.
  transitivity (tCoFix (mfix0 ++ {| dname := dname0; dtype := dtype0;
                                  dbody := dbody; rarg := rarg0 |} :: l) idx). {
    induction r; [econstructor 1| | ]; eauto with eta.
    constructor. apply OnOne2_app. now constructor. }
  transitivity (tCoFix (mfix0 ++ {| dname := dname0; dtype := dtype0;
                                  dbody := dbody0; rarg := rarg0 |} :: l) idx). {
    induction r0; [econstructor 1| | ]; eauto with eta.
    eapply cofix_eta_body. apply OnOne2_app. now constructor. }
  now rewrite (app_cons mfix0 l), (app_cons mfix0 l').
Defined.

Lemma eta_mkApps M M' l l' :
  eta M M' -> All2 eta l l' -> eta (mkApps M l) (mkApps M' l').
Proof.
  intros X Y.
  induction Y in M, M', X |- * ; cbn; eauto using eta_App.
Qed.


Hint Resolve eta_Evar eta_Prod eta_Lambda eta_LetIn eta_App
     eta_Case0 eta_Proj eta_Case eta_Fix eta_CoFix eta_mkApps : eta.
Hint Extern 0 (All2 _ _ _) => OnOne2_All2; intuition auto with eta : eta.
Hint Resolve All2_refl : eta.

 
(** ** Basic Properties of beta_eta *)

Create HintDb beta_eta.

Tactic Notation "beta_eta" integer(n) :=
  repeat match goal with
         | |- _ × _ => split
         end;
  match goal with
  | |- upto_domain _ _ => eauto n with utd
  | _ => idtac
  end;
  eauto n with beta_eta.

Tactic Notation "beta_eta" := beta_eta 5.
Hint Constructors eta1 : beta_eta.
Hint Constructors red1 : beta_eta.

Definition beta_eta_refl Σ Γ x : beta_eta Σ Γ x x := clos_refl_trans_refl _ _.
Hint Resolve beta_eta_refl : beta_eta.

Definition beta_eta_trans Σ Γ x y z :
  beta_eta Σ Γ x y -> beta_eta Σ Γ y z -> beta_eta Σ Γ x z
  := clos_refl_trans_trans _ x y z.
Hint Resolve beta_eta_trans : beta_eta.

Lemma red_beta_eta Σ Γ M N :
  red Σ Γ M N -> beta_eta Σ Γ M N.
Proof.
  induction 1; try reflexivity.
  - constructor. now left.
  - etransitivity; tea.
Defined.
Hint Resolve red_beta_eta : beta_eta.

Lemma eta_beta_eta Σ Γ M N :
  eta M N -> beta_eta Σ Γ M N.
Proof.
  induction 1; try reflexivity.
  - constructor. now right.
  - etransitivity; tea.
Defined.
Hint Resolve eta_beta_eta : beta_eta.

Hint Resolve eta1_eta : beta_eta.
Hint Resolve red1_red : beta_eta.

Lemma red1_beta_eta Σ Γ M N :
  red1 Σ Γ M N -> beta_eta Σ Γ M N.
Proof. beta_eta. Defined.

Lemma eta1_beta_eta Σ Γ M N :
  eta1 M N -> beta_eta Σ Γ M N.
Proof. beta_eta. Defined.

Lemma beta_eta_Evar Σ Γ n l l' :
  All2 (beta_eta Σ Γ) l l' ->
  beta_eta Σ Γ (tEvar n l) (tEvar n l').
Proof.
  intro X.
  enough (forall l0, beta_eta Σ Γ (tEvar n (l0 ++ l)) (tEvar n (l0 ++ l'))) as XX;
    [apply (XX [])|].
  induction X; auto with beta_eta.
  intro l0; transitivity (tEvar n (l0 ++ y :: l)); beta_eta.
  - clear -r.
    induction r; [econstructor 1|econstructor 2|econstructor 3]; beta_eta.
    destruct r; [left|right]; constructor; apply OnOne2_app; now constructor.
  - now rewrite (app_cons l0 l), (app_cons l0 l').
Defined.
Hint Resolve beta_eta_Evar : beta_eta.

Lemma beta_eta_Prod Σ Γ na M M' N N' :
  beta_eta Σ Γ M M' ->
  beta_eta Σ (Γ ,, vass na M') N N' ->
  beta_eta Σ Γ (tProd na M N) (tProd na M' N').
Proof.
  intros X Y; transitivity (tProd na M' N).
  - clear Y. induction X; beta_eta.
    destruct r; beta_eta.
  - clear X. induction Y; beta_eta.
    destruct r; beta_eta.
Defined.
Hint Resolve beta_eta_Prod : beta_eta.

Lemma beta_eta_Lambda Σ Γ na M M' N N' :
  beta_eta Σ Γ M M' ->
  beta_eta Σ (Γ ,, vass na M') N N' ->
  beta_eta Σ Γ (tLambda na M N) (tLambda na M' N').
Proof.
  intros X Y; transitivity (tLambda na M' N).
  - clear Y. induction X; beta_eta.
    destruct r; beta_eta.
  - clear X. induction Y; beta_eta.
    destruct r; beta_eta.
Defined.
Hint Resolve beta_eta_Lambda : beta_eta.

Lemma beta_eta_LetIn Σ Γ na d0 d1 t0 t1 b0 b1 :
  beta_eta Σ Γ d0 d1 -> beta_eta Σ Γ t0 t1 -> beta_eta Σ (Γ ,, vdef na d1 t1) b0 b1 ->
  beta_eta Σ Γ (tLetIn na d0 t0 b0) (tLetIn na d1 t1 b1).
Proof.
  intros X Y Z;
    transitivity (tLetIn na d1 t0 b0); [|transitivity (tLetIn na d1 t1 b0)].
  - clear Y Z. induction X; beta_eta.
    destruct r; beta_eta.
  - clear X Z. induction Y; beta_eta.
    destruct r; beta_eta.
  - clear X Y. induction Z; beta_eta.
    destruct r; beta_eta.
Defined.
Hint Resolve beta_eta_LetIn : beta_eta.

Lemma beta_eta_App Σ Γ M M' N N' :
  beta_eta Σ Γ M M' ->
  beta_eta Σ Γ N N' ->
  beta_eta Σ Γ (tApp M N) (tApp M' N').
Proof.
  intros X Y; transitivity (tApp M' N).
  - clear Y. induction X; beta_eta.
    destruct r; beta_eta.
  - clear X. induction Y; beta_eta.
    destruct r; beta_eta.
Defined.
Hint Resolve beta_eta_App : beta_eta.

Lemma beta_eta_Case Σ Γ indn p c brs p' c' brs' :
  beta_eta Σ Γ p p' ->
  beta_eta Σ Γ c c' ->
  All2 (on_Trel_eq (beta_eta Σ Γ) snd fst) brs brs' ->
  beta_eta Σ Γ (tCase indn p c brs) (tCase indn p' c' brs').
Proof.
  intros X Y Z.
  transitivity (tCase indn p' c brs). {
    induction X; beta_eta. destruct r; beta_eta. }
  transitivity (tCase indn p' c' brs). {
    induction Y; beta_eta. destruct r; beta_eta. }
  clear -Z.
  enough (forall brs0, beta_eta Σ Γ (tCase indn p' c'  (brs0 ++ brs))
                               (tCase indn p' c'  (brs0 ++ brs'))) as XX;
    [apply (XX [])|].
  induction Z; beta_eta.
  destruct x as [n ?], y as [n0 ?], r as [r ?]; cbn in *; subst.
  intro brs0.
  transitivity (tCase indn p' c' (brs0 ++ (n0, t0) :: l)); beta_eta.
  - induction r; [econstructor 1| | ]; beta_eta.
    destruct r; [left|right];
    constructor; apply OnOne2_app; now constructor.
  - now rewrite (app_cons brs0 l), (app_cons brs0 l').
Defined.
Hint Resolve beta_eta_Case : beta_eta.

Lemma beta_eta_Case0 Σ Γ indn p c brs p' c' :
  beta_eta Σ Γ p p' ->
  beta_eta Σ Γ c c' ->
  beta_eta Σ Γ (tCase indn p c brs) (tCase indn p' c' brs).
Proof.
  intros; apply beta_eta_Case; tea.
  apply All2_refl. split; reflexivity.
Defined.
Hint Resolve beta_eta_Case0 : beta_eta.

Lemma beta_eta_Proj Σ Γ p t0 t1 :
  beta_eta Σ Γ t0 t1 ->
  beta_eta Σ Γ (tProj p t0) (tProj p t1).
Proof.
  induction 1; beta_eta. destruct r; beta_eta.
Defined.
Hint Resolve beta_eta_Proj : beta_eta.


Lemma beta_eta_Fix_ty mfix mfix' idx Σ Γ :
  All2 (fun d0 d1 => beta_eta Σ Γ (dtype d0) (dtype d1)
                  × dbody d0 = dbody d1
                  × dname d0 = dname d1
                  × rarg d0 = rarg d1) mfix mfix' ->
  beta_eta Σ Γ (tFix mfix idx) (tFix mfix' idx).
Proof.
  intro XX.
  assert (clos_refl_trans (OnOne2 (fun d0 d1 =>
                  (beta_eta1 Σ Γ (dtype d0) (dtype d1))
                  × dbody d0 = dbody d1
                  × dname d0 = dname d1
                  × rarg d0 = rarg d1)) mfix mfix') as YY; [|clear XX]. {
    induction XX; [reflexivity|].
    transitivity (y :: l).
    - rdestruct r. destruct x, y; cbn in *; subst.
      induction r.
      + constructor. now constructor.
      + reflexivity.
      + etransitivity; eassumption.
    - clear XX. induction IHXX.
      + constructor. now constructor.
      + reflexivity.
      + etransitivity; eassumption. }
  induction YY; beta_eta.
  assert (((OnOne2 (on_Trel_eq (red1 Σ Γ) dtype
                      (fun x0 => (dname x0, dbody x0, rarg x0)))) x y)
          + ((OnOne2 (on_Trel_eq eta1 dtype
                        (fun x0 => (dname x0, dbody x0, rarg x0)))) x y)) as ZZ. {
    induction r.
    - destruct p as [[] ?]; [left|right]; constructor; now split.
    - destruct IHr; [left|right]; now constructor.
  }
  destruct ZZ; beta_eta.
Qed.

Lemma beta_eta_Fix_bo mfix mfix' idx Σ Γ :
  All2 (fun d0 d1 => beta_eta Σ (Γ ,,, fix_context mfix) (dbody d0) (dbody d1)
                  × dtype d0 = dtype d1
                  × dname d0 = dname d1
                  × rarg d0 = rarg d1) mfix mfix' ->
  beta_eta Σ Γ (tFix mfix idx) (tFix mfix' idx).
Proof.
  intro XX.
  assert (clos_refl_trans (OnOne2 (fun d0 d1 =>
                  beta_eta1 Σ (Γ ,,, fix_context mfix) (dbody d0) (dbody d1)
                  × dtype d0 = dtype d1
                  × dname d0 = dname d1
                  × rarg d0 = rarg d1)) mfix mfix') as YY; [|clear XX]. {
    set (Γ' := Γ ,,, fix_context mfix) in *; clearbody Γ'.
    induction XX; [reflexivity|].
    transitivity (y :: l).
    - rdestruct r. destruct x, y; cbn in *; subst.
      induction r.
      + constructor. now constructor.
      + reflexivity.
      + etransitivity; eassumption.
    - clear XX. induction IHXX.
      + constructor. now constructor.
      + reflexivity.
      + etransitivity; eassumption. }
  generalize_eq Γ' (fix_context mfix).
  dependent induction YY; trea.
  2: { intro e; etransitivity; eauto. apply IHYY2.
       rewrite e. clear -YY1. induction YY1; [|easy..].
       apply (f_equal (@List.rev _)). unfold mapi.
       generalize 0 at 2 4 as k.
       induction r; intro k; simpl.
       + rdest. congruence.
       + now rewrite IHr. }
  assert (((OnOne2 (on_Trel_eq (red1 Σ (Γ ,,, Γ')) dbody
                      (fun x0 => (dname x0, dtype x0, rarg x0)))) x y)
          + ((OnOne2 (on_Trel_eq eta1 dbody
                        (fun x0 => (dname x0, dtype x0, rarg x0)))) x y)) as ZZ. {
    induction r.
    - destruct p as [[] ?]; [left|right]; constructor; now split.
    - destruct IHr; [left|right]; now constructor.
  }
  intro; subst; destruct ZZ; beta_eta.
Qed.

Lemma beta_eta_Fix mfix mfix' idx Σ Γ :
  All2 (fun d0 d1 => beta_eta Σ Γ (dtype d0) (dtype d1)
                  × beta_eta Σ (Γ ,,, fix_context mfix) (dbody d0) (dbody d1)
                  × dname d0 = dname d1
                  × rarg d0 = rarg d1) mfix mfix' ->
  beta_eta Σ Γ (tFix mfix idx) (tFix mfix' idx).
Proof.
  intro h.
  assert (∑ mfixi, All2 (fun d0 d1 =>
     beta_eta Σ (Γ ,,, fix_context mfix) (dbody d0) (dbody d1)
     × dtype d0 = dtype d1 × dname d0 = dname d1 × rarg d0 = rarg d1) mfix mfixi
                 × All2 (fun d0 d1 =>
     beta_eta Σ Γ (dtype d0) (dtype d1)
     × dbody d0 = dbody d1 × dname d0 = dname d1 × rarg d0 = rarg d1) mfixi mfix'
         ) as [mfixi [h1 h2]].
  { revert h. generalize (Γ ,,, fix_context mfix). intros Δ h.
    induction h.
    - exists []. auto.
    - destruct r as [? [? e]]. inversion e.
      destruct IHh as [mfixi [? ?]].
      eexists (mkdef _ _ _ _ _ :: mfixi). split.
      + constructor ; auto. simpl. split ; eauto.
      + constructor ; auto. }
  etransitivity.
  - eapply beta_eta_Fix_bo. eassumption.
  - eapply beta_eta_Fix_ty. assumption.
Qed.
Hint Resolve beta_eta_Fix_ty beta_eta_Fix_bo beta_eta_Fix : beta_eta.


Lemma beta_eta_CoFix_ty mfix mfix' idx Σ Γ :
  All2 (fun d0 d1 => beta_eta Σ Γ (dtype d0) (dtype d1)
                  × dbody d0 = dbody d1
                  × dname d0 = dname d1
                  × rarg d0 = rarg d1) mfix mfix' ->
  beta_eta Σ Γ (tCoFix mfix idx) (tCoFix mfix' idx).
Proof.
  intro XX.
  assert (clos_refl_trans (OnOne2 (fun d0 d1 =>
                  (beta_eta1 Σ Γ (dtype d0) (dtype d1))
                  × dbody d0 = dbody d1
                  × dname d0 = dname d1
                  × rarg d0 = rarg d1)) mfix mfix') as YY; [|clear XX]. {
    induction XX; [reflexivity|].
    transitivity (y :: l).
    - rdestruct r. destruct x, y; cbn in *; subst.
      induction r.
      + constructor. now constructor.
      + reflexivity.
      + etransitivity; eassumption.
    - clear XX. induction IHXX.
      + constructor. now constructor.
      + reflexivity.
      + etransitivity; eassumption. }
  induction YY; beta_eta.
  assert (((OnOne2 (on_Trel_eq (red1 Σ Γ) dtype
                      (fun x0 => (dname x0, dbody x0, rarg x0)))) x y)
          + ((OnOne2 (on_Trel_eq eta1 dtype
                        (fun x0 => (dname x0, dbody x0, rarg x0)))) x y)) as ZZ. {
    induction r.
    - destruct p as [[] ?]; [left|right]; constructor; now split.
    - destruct IHr; [left|right]; now constructor.
  }
  destruct ZZ; beta_eta.
Qed.

Lemma beta_eta_CoFix_bo mfix mfix' idx Σ Γ :
  All2 (fun d0 d1 => beta_eta Σ (Γ ,,, fix_context mfix) (dbody d0) (dbody d1)
                  × dtype d0 = dtype d1
                  × dname d0 = dname d1
                  × rarg d0 = rarg d1) mfix mfix' ->
  beta_eta Σ Γ (tCoFix mfix idx) (tCoFix mfix' idx).
Proof.
  intro XX.
  assert (clos_refl_trans (OnOne2 (fun d0 d1 =>
                 beta_eta1 Σ (Γ ,,, fix_context mfix) (dbody d0) (dbody d1)
                  × dtype d0 = dtype d1
                  × dname d0 = dname d1
                  × rarg d0 = rarg d1)) mfix mfix') as YY; [|clear XX]. {
    set (Γ' := Γ ,,, fix_context mfix) in *; clearbody Γ'.
    induction XX; [reflexivity|].
    transitivity (y :: l).
    - rdestruct r. destruct x, y; cbn in *; subst.
      induction r.
      + constructor. now constructor.
      + reflexivity.
      + etransitivity; eassumption.
    - clear XX. induction IHXX.
      + constructor. now constructor.
      + reflexivity.
      + etransitivity; eassumption. }
  generalize_eq Γ' (fix_context mfix).
  dependent induction YY; trea.
  2: { intro e; etransitivity; eauto. apply IHYY2.
       rewrite e. clear -YY1. induction YY1; [|easy..].
       apply (f_equal (@List.rev _)). unfold mapi.
       generalize 0 at 2 4 as k.
       induction r; intro k; simpl.
       + rdest. congruence.
       + now rewrite IHr. }
  assert (((OnOne2 (on_Trel_eq (red1 Σ (Γ ,,, Γ')) dbody
                      (fun x0 => (dname x0, dtype x0, rarg x0)))) x y)
          + ((OnOne2 (on_Trel_eq eta1 dbody
                        (fun x0 => (dname x0, dtype x0, rarg x0)))) x y)) as ZZ. {
    induction r.
    - destruct p as [[] ?]; [left|right]; constructor; now split.
    - destruct IHr; [left|right]; now constructor.
  }
  intro; subst; destruct ZZ; beta_eta.
Qed.

Lemma beta_eta_CoFix mfix mfix' idx Σ Γ :
  All2 (fun d0 d1 => beta_eta Σ Γ (dtype d0) (dtype d1)
                  × beta_eta Σ (Γ ,,, fix_context mfix) (dbody d0) (dbody d1)
                  × dname d0 = dname d1
                  × rarg d0 = rarg d1) mfix mfix' ->
  beta_eta Σ Γ (tCoFix mfix idx) (tCoFix mfix' idx).
Proof.
  intro h.
  assert (∑ mfixi, All2 (fun d0 d1 =>
     beta_eta Σ (Γ ,,, fix_context mfix) (dbody d0) (dbody d1)
     × dtype d0 = dtype d1 × dname d0 = dname d1 × rarg d0 = rarg d1) mfix mfixi
                 × All2 (fun d0 d1 =>
     beta_eta Σ Γ (dtype d0) (dtype d1)
     × dbody d0 = dbody d1 × dname d0 = dname d1 × rarg d0 = rarg d1) mfixi mfix'
         ) as [mfixi [h1 h2]].
  { revert h. generalize (Γ ,,, fix_context mfix). intros Δ h.
    induction h.
    - exists []. auto.
    - destruct r as [? [? e]]. inversion e.
      destruct IHh as [mfixi [? ?]].
      eexists (mkdef _ _ _ _ _ :: mfixi). split.
      + constructor ; auto. simpl. split ; eauto.
      + constructor ; auto. }
  etransitivity.
  - eapply beta_eta_CoFix_bo. eassumption.
  - eapply beta_eta_CoFix_ty. assumption.
Qed.
Hint Resolve beta_eta_CoFix_ty beta_eta_CoFix_bo beta_eta_CoFix : beta_eta.

Lemma beta_eta_mkApps Σ Γ M M' l l' :
  beta_eta Σ Γ M M' -> All2 (beta_eta Σ Γ) l l' ->
  beta_eta Σ Γ (mkApps M l) (mkApps M' l').
Proof.
  intros X Y.
  induction Y in M, M', X |- * ; cbn; beta_eta.
Qed.
Hint Resolve beta_eta_mkApps : beta_eta.


(** ** Basic Properties of beu *)

Hint Constructors eta1 : beu.
Hint Constructors red1 : beu.

Definition beu_refl Σ Γ x : beu Σ Γ x x := clos_refl_trans_refl _ _.
Hint Resolve beu_refl : beu.

Definition beu_trans Σ Γ x y z :
  beu Σ Γ x y -> beu Σ Γ y z -> beu Σ Γ x z
  := clos_refl_trans_trans _ x y z.
Hint Resolve beu_trans : beu.

Lemma red_beu Σ Γ M N :
  red Σ Γ M N -> beu Σ Γ M N.
Proof.
  induction 1; try reflexivity.
  - constructor. left. now left.
  - etransitivity; tea.
Defined.
Hint Resolve red_beu : beu.

Lemma eta_beu Σ Γ M N :
  eta M N -> beu Σ Γ M N.
Proof.
  induction 1; try reflexivity.
  - constructor. left. now right.
  - etransitivity; tea.
Defined.
Hint Resolve eta_beu : beu.

Lemma upto_domain_beu Σ Γ M N :
  upto_domain M N -> beu Σ Γ M N.
Proof.
  constructor. now right.
Defined.
Hint Resolve upto_domain_beu : beu.

Hint Resolve eta1_eta : beu.
Hint Resolve red1_red : beu.

Lemma red1_beu Σ Γ M N :
  red1 Σ Γ M N -> beu Σ Γ M N.
Proof. eauto with beu. Defined.

Lemma eta1_beu Σ Γ M N :
  eta1 M N -> beu Σ Γ M N.
Proof. eauto with beu. Defined.

 
(** ** Basic Properties of cumul *)

Instance cumul_refl' {cf:checker_flags} Σ Γ : Reflexive (cumul Σ Γ).
Proof.
  intro x; repeat exists x; repeat split; reflexivity.
Qed.

Instance conv_refl' {cf:checker_flags} Σ Γ : Reflexive (conv Σ Γ).
Proof.
  intro x; repeat exists x; repeat split; reflexivity.
Qed.

(* Lemma red_cumul_cumul {cf:checker_flags} {Σ : global_env_ext} {Γ t u v} : *)
(*   red Σ Γ t u -> Σ ;;; Γ |- u <= v -> Σ ;;; Γ |- t <= v. *)
(* Proof. *)
(*   induction 1 in v |- *; auto. *)
(*   intro. apply IHX. econstructor 2; eassumption. *)
(* Qed. *)

(* Lemma red_cumul_cumul_inv {cf:checker_flags} {Σ : global_env_ext} {Γ t u v} : *)
(*   red Σ Γ t v -> Σ ;;; Γ |- u <= v -> Σ ;;; Γ |- u <= t. *)
(* Proof. *)
(*   induction 1 in u |- *; auto. *)
(*   intro. apply IHX. econstructor 3; eassumption. *)
(* Qed. *)

Lemma red_cumul {cf:checker_flags} {Σ : global_env_ext} {Γ t u} :
  red Σ Γ t u ->
  Σ ;;; Γ |- t <= u.
Proof.
  intros; repeat eexists.
  eapply red_beu; eassumption.
  all: reflexivity.
Qed.

Lemma red_cumul_inv {cf:checker_flags} {Σ : global_env_ext} {Γ t u} :
  red Σ Γ t u ->
  Σ ;;; Γ |- u <= t.
Proof.
  intros; repeat eexists.
  3: eapply red_beu; eassumption.
  all: reflexivity.
Qed.


(** ** Basic Properties of conv *)

(* Lemma red_conv_conv `{cf : checker_flags} Σ Γ t u v : *)
(*   red (fst Σ) Γ t u -> Σ ;;; Γ |- u = v -> Σ ;;; Γ |- t = v. *)
(* Proof. *)
(*   induction 1 in v |- *; auto. *)
(*   intro. apply IHX. econstructor 2; eassumption. *)
(* Qed. *)

(* Lemma red_conv_conv_inv `{cf : checker_flags} Σ Γ t u v : *)
(*   red (fst Σ) Γ t u -> Σ ;;; Γ |- v = u -> Σ ;;; Γ |- v = t. *)
(* Proof. *)
(*   induction 1 in v |- *; auto. *)
(*   intro. apply IHX. econstructor 3; eassumption. *)
(* Qed. *)

Lemma red_conv {cf:checker_flags} (Σ : global_env_ext) Γ t u :
  red Σ Γ t u -> Σ ;;; Γ |- t = u.
Proof.
  intros; repeat eexists.
  eapply red_beu; eassumption.
  all: reflexivity.
Qed.

Lemma red_conv_inv {cf:checker_flags} (Σ : global_env_ext) Γ t u :
  red Σ Γ t u -> Σ ;;; Γ |- u = t.
Proof.
  intros; repeat eexists.
  3: eapply red_beu; eassumption.
  all: reflexivity.
Qed.

(** ** Upto types: assumptions does not change reduction  ** **)

Inductive upto_types : context -> context -> Type :=
| upto_types_nil : upto_types [] []
| upto_types_vass {Γ Γ' na na' A A'} : upto_types Γ Γ' -> upto_types (Γ ,, vass na A) (Γ' ,, vass na' A')
| upto_types_vdef {Γ Γ' na na' t A A'} : upto_types Γ Γ' -> upto_types (Γ ,, vdef na t A) (Γ' ,, vdef na' t A').

Instance upto_types_refl : Reflexive upto_types.
Proof.
  intro Γ; induction Γ as [|[na [bo|] ty]]; now econstructor.
Qed.

Instance upto_types_sym : Symmetric upto_types.
Proof.
  intros Γ Γ' e; induction e; constructor; auto.
Qed.

Instance upto_types_trans : Transitive upto_types.
Proof.
  intros Γ Γ' Γ'' e e'; induction e in Γ'', e' |- *;
    invs e'; constructor; auto.
Qed.

Lemma upto_types_app {Γ Γ' Δ Δ'} :
  upto_types Γ Γ' -> upto_types Δ Δ' -> upto_types (Γ ,,, Δ) (Γ' ,,, Δ').
Proof.
  intros e1 e2; induction e2; simpl; try constructor; auto.
Qed.

Lemma lookup_upto_types {Γ Γ'} i :
  upto_types Γ Γ' ->
  option_map decl_body (nth_error Γ i)
  = option_map decl_body (nth_error Γ' i).
Proof.
  induction i in Γ, Γ' |- *; intro e; destruct e; cbn; auto.
Qed.

Hint Constructors red1 : upto_types.
Hint Constructors upto_types : upto_types.


Lemma red1_upto_types {Σ Γ Γ' t t'} :
  upto_types Γ Γ' -> red1 Σ Γ t t' -> red1 Σ Γ' t t'.
Proof.
  intros e X; induction X in Γ', e |- * using red1_ind_all;
    eauto with upto_types.
  1: constructor; erewrite <- lookup_upto_types; tea.
  all: try (constructor; solve_all; fail).
  - apply fix_red_body; solve_all.
    apply b0. now apply upto_types_app.
  - apply cofix_red_body; solve_all.
    apply b0. now apply upto_types_app.
Qed.

Lemma red_upto_types {Σ Γ Γ' t t'} :
  upto_types Γ Γ' -> red Σ Γ t t' -> red Σ Γ' t t'.
Proof.
  intros e X; induction X in Γ', e |- *.
  - constructor; eauto using red1_upto_types.
  - reflexivity.
  - etransitivity; [eapply IHX1|eapply IHX2]; assumption.
Qed.

Lemma beta_eta_upto_types {Σ Γ Γ' t t'} :
  upto_types Γ Γ' -> beta_eta Σ Γ t t' -> beta_eta Σ Γ' t t'.
Proof.
  intros e X; induction X in Γ', e |- *; [|beta_eta ..].
  constructor. destruct r; [left|right]; tas.
  eapply red1_upto_types; eassumption.
Qed.
Hint Resolve beta_eta_upto_types : beta_eta.

Lemma red1_upto_vass {Σ Γ na na' A A' t t'} :
  red1 Σ (Γ ,, vass na A) t t' -> red1 Σ (Γ ,, vass na' A') t t'.
Proof.
  apply red1_upto_types. now constructor.
Qed.
Hint Resolve red1_upto_vass : beta.

Lemma beta_eta_upto_vass {Σ Γ na na' A A' t t'} :
  beta_eta Σ (Γ ,, vass na A) t t' -> beta_eta Σ (Γ ,, vass na' A') t t'.
Proof.
  apply beta_eta_upto_types. now constructor.
Qed.
Hint Resolve beta_eta_upto_vass : beta_eta.

Lemma upto_types_fix_context mfix mfix' :
  #|mfix| = #|mfix'| -> upto_types (fix_context mfix) (fix_context mfix').
Proof.
  unfold fix_context, mapi. generalize 0 at 2 4 as k.
  induction mfix in mfix' |- *; destruct mfix'; try discriminate.
  - constructor.
  - simpl. intros k H. apply upto_types_app; eauto using upto_types.
Qed.

Lemma beta_eta_upto_fix_context {Σ Γ mfix mfix' t t'} :
  #|mfix| = #|mfix'| -> 
  beta_eta Σ (Γ ,,, fix_context mfix) t t' ->
  beta_eta Σ (Γ ,,, fix_context mfix') t t'.
Proof.
  intro H.
  apply beta_eta_upto_types. eapply upto_types_app; trea.
  now apply upto_types_fix_context.
Qed.
Hint Resolve beta_eta_upto_fix_context : beta_eta.



(* Why is ths needed??? *)
Arguments Datatypes.nil {_}, _.
