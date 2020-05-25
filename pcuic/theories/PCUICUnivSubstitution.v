(* Distributed under the terms of the MIT license.   *)

(** * Universe Substitution lemmas for typing derivations. *)

From Coq Require Import Bool List Lia ZArith CRelationClasses.
From MetaCoq.Template Require Import utils config.
From MetaCoq.PCUIC Require Import PCUICAst PCUICAstUtils PCUICInduction
     PCUICLiftSubst PCUICEquality
     PCUICUnivSubst PCUICTyping PCUICWeakeningEnv PCUICClosed PCUICPosition
     PCUICWeakening.

Local Set Keyed Unification.

Set Default Goal Selector "!".

Module CS := ConstraintSet.
Module LS := LevelSet.

Create HintDb univ_subst.

Local Ltac aa := rdest; eauto with univ_subst.

From MetaCoq.Template Require Import Universes uGraph.

Lemma subst_instance_level_val u l v v'
      (H1 : forall s, valuation_mono v s = valuation_mono v' s)
      (H2 : forall n, val v (nth n u Level.lSet) = Z.of_nat (valuation_poly v' n))
  : val v (subst_instance_level u l) = val v' l.
Proof.
  destruct l; cbn; try congruence. apply H2.
Qed.

Lemma eq_val v v'
      (H1 : forall s, valuation_mono v s = valuation_mono v' s)
      (H2 : forall n, valuation_poly v n = valuation_poly v' n)
  : forall u : Universe.t, val v u = val v' u.
Proof.
  assert (He : forall e : UnivExpr.t, val v e = val v' e). {
    intros [|[[] b]]; cbnr; rewrite ?H1, ?H2; reflexivity. }
  intro u. rewrite !val_fold_right.
  induction ((List.rev (Universe.exprs u).2)); cbn; congruence.
Qed.

Lemma is_prop_subst_instance_level u l
      (Hu : forallb (negb ∘ Level.is_prop) u)
  : Level.is_prop (subst_instance_level u l) = Level.is_prop l.
Proof.
  destruct l; cbn; try reflexivity.
  destruct (le_lt_dec #|u| n) as [HH|HH].
  + now rewrite nth_overflow.
  + eapply (forallb_nth _ _ _ Level.lSet Hu) in HH.
    destruct HH as [l [HH1 HH2]]. rewrite HH1. now apply ssrbool.negbTE.
Qed.

Lemma subst_instance_univ_val u l v v'
      (Hu : forallb (negb ∘ Level.is_prop) u)
      (H1 : forall s, valuation_mono v s = valuation_mono v' s)
      (H2 : forall n, val v (nth n u Level.lSet) = Z.of_nat (valuation_poly v' n))
  : val v (subst_instance_univ u l) = val v' l.
Proof.
  assert (He: forall e : UnivExpr.t, val v (subst_instance_level_expr u e) = val v' e). {
    clear l. intros [|[[] b]]; cbn; rewrite <- ?H1, <- ?H2; try reflexivity.
    rewrite nth_nth_error.
    destruct (le_lt_dec #|u| n) as [HH|HH].
    + apply nth_error_None in HH; now rewrite HH.
    + apply nth_error_Some' in HH. destruct HH as [l HH]; rewrite HH.
      destruct l; cbnr.
      eapply nth_error_forallb in Hu. rewrite HH in Hu. discriminate. }
  symmetry. apply val_caract. split.
  - intros e Xe. unfold subst_instance_univ.
    apply val_le_caract. eexists; split.
    + apply Universe.map_spec. eexists; split; tea. reflexivity.
    + now rewrite He.
  - destruct ((val_caract (subst_instance_univ u l) v _).p1 eq_refl)
      as [_ [e [He1 He2]]].
    apply Universe.map_spec in He1. destruct He1 as [e0 [He0 He1]]; subst.
    eexists; split; tea. now rewrite <- He2, He.
Qed.

Definition subst_instance_valuation (u : Instance.t) (v : valuation) :=
  {| valuation_mono := valuation_mono v ;
     valuation_poly := fun i => Z.to_nat (val v (nth i u Level.lSet)) |}.


Lemma subst_instance_univ_val' u l v
      (Hu : forallb (negb ∘ Level.is_prop) u)
  : val v (subst_instance_univ u l) = val (subst_instance_valuation u v) l.
Proof.
  eapply subst_instance_univ_val; auto.
  cbn. intro; rewrite Z2Nat.id; auto.
  destruct (le_lt_dec #|u| n) as [HH|HH].
  + now rewrite nth_overflow.
  + eapply (forallb_nth _ _ _ Level.lSet Hu) in HH.
    destruct HH as [?l [HH1 HH2]]. rewrite HH1.
    destruct l0; try discriminate; cbn.
    apply Zle_0_nat.
Qed.


Lemma subst_instance_univ_make l u :
  subst_instance_univ u (Universe.make l)
  = Universe.make (subst_instance_level u l).
Proof.
  destruct l; cbnr. rewrite nth_nth_error.
  destruct nth_error; cbnr.
Qed.


Class SubstUnivPreserving Re := Build_SubstUnivPreserving :
  forall s u1 u2, R_universe_instance Re u1 u2 ->
             Re (subst_instance_univ u1 s) (subst_instance_univ u2 s).

Lemma subst_equal_inst_inst Re :
  SubstUnivPreserving Re ->
  forall u u1 u2, R_universe_instance Re u1 u2 ->
             R_universe_instance Re (subst_instance_instance u1 u)
                                    (subst_instance_instance u2 u).
Proof.
  intros hRe u. induction u; cbnr; try now constructor.
  intros u1 u2; unfold R_universe_instance; cbn; constructor.
  - pose proof (hRe (Universe.make a) u1 u2 H) as HH.
    now rewrite !subst_instance_univ_make in HH.
  - exact (IHu u1 u2 H).
Qed.

Lemma subst_equal_inst_global_inst Σ Re gr :
  RelationClasses.Reflexive Re ->
  SubstUnivPreserving Re ->
  forall u u1 u2, R_universe_instance Re u1 u2 ->
             R_global_instance Σ Re Re gr (subst_instance_instance u1 u)
                                    (subst_instance_instance u2 u).
Proof.
  intros reflRe hRe u u1 u2 Ru1u2.
  unfold R_global_instance.
  destruct lookup_env as [[g|g]|]; auto using subst_equal_inst_inst.
  destruct ind_variance; auto using subst_equal_inst_inst.
  induction u in l |- *; cbnr; try now constructor.
  - destruct l; simpl; auto.
  - destruct l; simpl; auto.
    split; auto.
    destruct t; simpl; auto.
    * pose proof (hRe (Universe.make a) u1 u2 Ru1u2) as HH.
      now rewrite !subst_instance_univ_make in HH.
    * pose proof (hRe (Universe.make a) u1 u2 Ru1u2) as HH.
      now rewrite !subst_instance_univ_make in HH.
Qed.

Lemma eq_term_upto_univ_subst_instance_constr Σ Re :
  RelationClasses.Reflexive Re ->
  SubstUnivPreserving Re ->
  forall t u1 u2,
    R_universe_instance Re u1 u2 ->
    eq_term_upto_univ Σ Re Re (subst_instance_constr u1 t)
                            (subst_instance_constr u2 t).
Proof.
  intros ref hRe t.
  induction t using term_forall_list_ind; intros u1 u2 hu.
  all: cbn; try constructor; eauto using subst_equal_inst_inst.
  all: try eapply All2_map, All_All2; tea; cbn; intros; rdest; eauto.
  all:auto using subst_equal_inst_global_inst.
Qed.

Instance leq_term_SubstUnivPreserving {cf:checker_flags} φ :
  SubstUnivPreserving (eq_universe φ).
Proof.
  intros s u1 u2 hu.
  unfold eq_universe in *; destruct check_univs; [|trivial].
  intros v Hv; cbn.
  assert (He : forall e, val v (subst_instance_level_expr u1 e)
                    = val v (subst_instance_level_expr u2 e)). {
    destruct e as [|[[] b]]; cbnr.
    case_eq (nth_error u1 n).
    - intros l1 X. eapply Forall2_nth_error_Some_l in hu.
      2: now rewrite nth_error_map, X.
      destruct hu as [l2 [H1 H2]].
      rewrite nth_error_map in H1.
      destruct (nth_error u2 n) as [l2'|]; [|discriminate].
      apply some_inj in H1; subst. clear u1 u2 X.
      specialize (H2 v Hv).
      destruct l1, l2'; cbn in *; try lia.
    - intros X. eapply Forall2_nth_error_None_l in hu.
      2: now rewrite nth_error_map, X.
      rewrite nth_error_map in hu.
      destruct (nth_error u2 n); [discriminate|reflexivity]. }
  apply val_caract; split.
  - intros e Xe. apply Universe.map_spec in Xe as [e' [H1 H2]]; subst.
    apply val_le_caract. eexists; split.
    + apply Universe.map_spec; eexists; split; tea; reflexivity.
    + now rewrite He.
  - destruct ((val_caract (subst_instance_univ u2 s) v _).p1 eq_refl)
      as [_ [e [He1 He2]]]. rewrite <- He2.
    apply Universe.map_spec in He1. destruct He1 as [e0 [He0 He1]]; subst.
    eexists; split; [|eapply He]. eapply Universe.map_spec.
    now eexists; split; tea.
Qed.

Section CheckerFlags.

Global Instance subst_instance_list {A} `(UnivSubst A) : UnivSubst (list A)
  := fun u => map (subst_instance u).

Global Instance subst_instance_def {A} `(UnivSubst A) : UnivSubst (def A)
  := fun u => map_def (subst_instance u) (subst_instance u).

Global Instance subst_instance_prod {A B} `(UnivSubst A) `(UnivSubst B)
  : UnivSubst (A × B)
  := fun u => on_pair (subst_instance u) (subst_instance u).

Global Instance subst_instance_nat : UnivSubst nat
  := fun _ n => n.



Lemma subst_instance_instance_length u1 u2 :
  #|subst_instance_instance u2 u1| = #|u1|.
Proof.
  unfold subst_instance_instance.
  now rewrite map_length.
Qed.

Lemma subst_instance_level_two u1 u2 l :
  subst_instance_level u1 (subst_instance_level u2 l)
  = subst_instance_level (subst_instance_instance u1 u2) l.
Proof.
  destruct l; cbn; try reflexivity.
  unfold subst_instance_instance.
  rewrite <- (map_nth (subst_instance_level u1)); reflexivity.
Qed.

Lemma subst_instance_level_expr_two u1 u2 e :
  subst_instance_level_expr u1 (subst_instance_level_expr u2 e)
  = subst_instance_level_expr (subst_instance_instance u1 u2) e.
Proof.
  destruct e as [|[[] b]]; cbnr.
  unfold subst_instance_instance. erewrite nth_error_map.
  destruct nth_error; cbnr.
  destruct t; cbnr; [destruct b; reflexivity|].
  rewrite nth_nth_error. destruct nth_error; cbnr.
Qed.

Lemma subst_instance_univ_two u1 u2 s :
  subst_instance_univ u1 (subst_instance_univ u2 s)
  = subst_instance_univ (subst_instance_instance u1 u2) s.
Proof.
  unfold subst_instance_univ. apply eq_univ'.
  intro l; split; intro Hl; apply Universe.map_spec in Hl as [l' [H1 H2]];
    apply Universe.map_spec; subst.
  - apply Universe.map_spec in H1 as [l'' [H1 H2]]; subst.
    eexists; split; tea. apply subst_instance_level_expr_two.
  - eexists; split. 2: symmetry; eapply subst_instance_level_expr_two.
    apply Universe.map_spec. eexists; split; tea; reflexivity.
Qed.

Lemma subst_instance_instance_two u1 u2 u :
  subst_instance_instance u1 (subst_instance_instance u2 u)
  = subst_instance_instance (subst_instance_instance u1 u2) u.
Proof.
  unfold subst_instance_instance. rewrite map_map.
  apply map_ext, subst_instance_level_two.
Qed.

Lemma subst_instance_constr_two u1 u2 t :
  subst_instance_constr u1 (subst_instance_constr u2 t)
  = subst_instance_constr (subst_instance_instance u1 u2) t.
Proof.
  induction t using term_forall_list_ind; cbn; f_equal;
    auto using subst_instance_instance_two.
  - rewrite map_map. now apply All_map_eq.
  - apply subst_instance_univ_two.
  - rewrite map_map. apply All_map_eq.
    eapply All_impl; tea.
    cbn. intros [? ?]; unfold on_snd; cbn; congruence.
  - rewrite map_map. apply All_map_eq.
    eapply All_impl; tea.
    cbn. intros [? ? ?] [? ?]; cbn in *. unfold map_def; cbn; congruence.
  - rewrite map_map. apply All_map_eq.
    eapply All_impl; tea.
    cbn. intros [? ? ?] [? ?]; cbn in *. unfold map_def; cbn; congruence.
Qed.

Lemma subst_instance_context_two u1 u2 Γ :
  subst_instance_context u1 (subst_instance_context u2 Γ)
  = subst_instance_context (subst_instance_instance u1 u2) Γ.
Proof.
  induction Γ; try reflexivity.
  simpl. rewrite IHΓ; f_equal.
  destruct a as [? [] ?]; unfold map_decl; cbn;
    now rewrite !subst_instance_constr_two.
Qed.

Lemma subst_instance_cstr_two u1 u2 c :
  subst_instance_cstr u1 (subst_instance_cstr u2 c)
  = subst_instance_cstr (subst_instance_instance u1 u2) c.
Proof.
  destruct c as [[? ?] ?]; unfold subst_instance_cstr; cbn.
  now rewrite !subst_instance_level_two.
Qed.

Lemma In_subst_instance_cstrs u c ctrs :
  CS.In c (subst_instance_cstrs u ctrs)
  <-> exists c', c = subst_instance_cstr u c' /\ CS.In c' ctrs.
Proof.
  unfold subst_instance_cstrs.
  rewrite CS.fold_spec.
  transitivity (CS.In c CS.empty \/
                exists c', c = subst_instance_cstr u c'
                      /\ In c' (CS.elements ctrs)).
  - generalize (CS.elements ctrs), CS.empty.
    induction l; cbn.
    + firstorder.
    + intros t. etransitivity. 1: eapply IHl.
      split; intros [HH|HH].
      * destruct a as [[l1 a] l2]. apply CS.add_spec in HH.
        destruct HH as [HH|HH]. 2: now left.
        right; eexists. split; [|left; reflexivity]. assumption.
      * destruct HH as [c' ?]. right; exists c'; intuition.
      * left. destruct a as [[l1 a] l2]. apply CS.add_spec.
        now right.
      * destruct HH as [c' [HH1 [?|?]]]; subst.
        -- left. destruct c' as [[l1 c'] l2];
           apply CS.add_spec; now left.
        -- right. exists c'. intuition.
  - rewrite ConstraintSetFact.empty_iff.
    transitivity (exists c', c = subst_instance_cstr u c'
                        /\ In c' (CS.elements ctrs)).
    1: intuition.
    apply iff_ex; intro. apply and_iff_compat_l. symmetry.
    etransitivity. 1: eapply CS.elements_spec1.
    etransitivity. 1: eapply SetoidList.InA_alt.
    split; intro; eauto.
    now destruct H as [? [[] ?]].
Qed.

Lemma In_subst_instance_cstrs' u c ctrs :
  CS.In c ctrs ->
  CS.In (subst_instance_cstr u c) (subst_instance_cstrs u ctrs).
Proof.
  intro H. apply In_subst_instance_cstrs. now eexists.
Qed.

Lemma subst_instance_cstrs_two u1 u2 ctrs :
  CS.Equal
    (subst_instance_cstrs u1 (subst_instance_cstrs u2 ctrs))
    (subst_instance_cstrs (subst_instance_instance u1 u2) ctrs).
Proof.
  intro c; split; intro Hc; apply In_subst_instance_cstrs.
  - apply In_subst_instance_cstrs in Hc; destruct Hc as [c' [eq Hc']].
    apply In_subst_instance_cstrs in Hc'; destruct Hc' as [c'' [eq' Hc'']].
    exists c''. subst; now rewrite subst_instance_cstr_two.
  - apply In_subst_instance_cstrs in Hc; destruct Hc as [c' [eq Hc']].
    exists (subst_instance_cstr u2 c'). split.
    + now rewrite subst_instance_cstr_two.
    + now apply In_subst_instance_cstrs'.
Qed.

Lemma is_prop_subst_instance_univ u l
      (Hu : forallb (negb ∘ Level.is_prop) u)
  : Universe.is_prop (subst_instance_univ u l) = Universe.is_prop l.
Proof.
  assert (He : forall a, UnivExpr.is_prop (subst_instance_level_expr u a)
                    = UnivExpr.is_prop a). {
    clear l. intros [|[l b]]; cbnr.
    destruct l; cbnr.
    apply nth_error_forallb with (n0:=n) in Hu.
    destruct nth_error; cbnr.
    destruct t; cbnr. discriminate. }
  apply iff_is_true_eq_bool.
  split; intro H; apply UnivExprSet.for_all_spec in H; proper;
    apply UnivExprSet.for_all_spec; proper; intros e Xe.
  - rewrite <- He. apply H. apply Universe.map_spec.
    eexists; split; tea; reflexivity.
  - apply Universe.map_spec in Xe as [e' [H1 H2]]; subst.
    rewrite He. now apply H.
Qed.

Lemma is_prop_subst_instance u x0 :
  Universe.is_prop x0 -> Universe.is_prop (subst_instance_univ u x0).
Proof.
  assert (He : forall a, UnivExpr.is_prop a ->
             UnivExpr.is_prop (subst_instance_level_expr u a)). {
    intros [|[[][]]]; cbnr; auto. }
  intro H; apply UnivExprSet.for_all_spec in H; proper;
    apply UnivExprSet.for_all_spec; proper; intros e Xe.
  apply Universe.map_spec in Xe as [e' [H1 H2]]; subst.
  now apply He, H.
Qed.

Lemma is_small_subst_instance_univ u l
  : Universe.is_small l -> Universe.is_small (subst_instance_univ u l).
Proof.
  assert (He : forall a, UnivExpr.is_small a ->
             UnivExpr.is_small (subst_instance_level_expr u a)). {
    intros [|[[][]]]; cbnr; auto. }
  intro H; apply UnivExprSet.for_all_spec in H; proper;
    apply UnivExprSet.for_all_spec; proper; intros e Xe.
  apply Universe.map_spec in Xe as [e' [H1 H2]]; subst.
  now apply He, H.
Qed.

Lemma sup_subst_instance_univ u s1 s2 :
  subst_instance_univ u (Universe.sup s1 s2)
  = Universe.sup (subst_instance_univ u s1) (subst_instance_univ u s2).
Proof.
  apply eq_univ'. cbn.
  intro x; split; intro Hx.
  + apply Universe.map_spec in Hx as [y [H H']]; subst.
    apply UnivExprSet.union_spec.
    apply UnivExprSet.union_spec in H as [H|H]; [left|right].
    all: apply Universe.map_spec; eexists; split; tea; reflexivity.
  + apply Universe.map_spec.
    apply UnivExprSet.union_spec in Hx as [H|H];
      apply Universe.map_spec in H as [y [H H']]; subst.
    all: eexists; split; [eapply UnivExprSet.union_spec|reflexivity]; auto.
Qed.

Context {cf : checker_flags}.

Lemma consistent_instance_no_prop  lvs φ uctx u :
  consistent_instance lvs φ uctx u
  -> forallb (fun x => negb (Level.is_prop x)) u.
Proof.
  unfold consistent_instance. destruct uctx as [ctx|ctx].
  1: destruct u; [reflexivity|discriminate].
  intuition auto.
Qed.

Hint Resolve consistent_instance_no_prop : univ_subst.

Lemma consistent_instance_declared lvs φ uctx u :
  consistent_instance lvs φ uctx u
  -> forallb (fun l => LS.mem l lvs) u.
Proof.
  unfold consistent_instance. destruct uctx as [ctx|ctx].
  1: destruct u; [reflexivity|discriminate].
  intuition auto.
Qed.

Lemma monomorphic_level_notin_AUContext s φ :
  ~ LS.In (Level.Level s) (AUContext.levels φ).
Proof.
  destruct φ as [φ1 φ2].
  intro H. apply (proj1 (LevelSetProp.of_list_1 _ _)) in H. cbn in H.
  apply SetoidList.InA_alt in H.
  destruct H as [? [? H]]; subst. revert H.
  unfold mapi; generalize 0.
  induction φ1; cbn. 1: trivial.
  intros n [H|H].
  - discriminate.
  - eauto.
Qed.

Global Instance satisfies_equal_sets v :
  Morphisms.Proper (Morphisms.respectful CS.Equal iff) (satisfies v).
Proof.
  intros φ1 φ2 H; split; intros HH c Hc; now apply HH, H.
Qed.

Global Instance satisfies_subsets v :
  Morphisms.Proper (Morphisms.respectful CS.Subset (fun A B : Prop => B -> A))
                   (satisfies v).
Proof.
  intros φ1 φ2 H H2 c Hc; now apply H2, H.
Qed.

Hint Resolve subst_instance_cstrs_two
     satisfies_equal_sets satisfies_subsets : univ_subst.


Lemma val0_subst_instance_level u l v
      (Hu : forallb (negb ∘ Level.is_prop) u)
  : val v (subst_instance_level u l) = val (subst_instance_valuation u v) l.
Proof.
  destruct l; aa; cbn.
  rewrite Znat.Z2Nat.id; auto.
  apply (forallb_nth' n Level.lSet) in Hu.
  destruct Hu as [[?l [HH1 HH2]]|HH1]; rewrite HH1; cbn.
  - destruct l; try discriminate; cbn.
    apply Zorder.Zle_0_nat.
  - reflexivity.
Qed.

Lemma satisfies0_subst_instance_ctr u v c
      (Hu : forallb (negb ∘ Level.is_prop) u)
  : satisfies0 v (subst_instance_cstr u c)
    <-> satisfies0 (subst_instance_valuation u v) c.
Proof.
  destruct c as [[l1 []] l2]; unfold subst_instance_cstr; cbn;
    split; intro H; constructor; inv H.
  all: rewrite <- ?val0_subst_instance_level; tea.
  all: rewrite ?val0_subst_instance_level; tea.
Qed.

Lemma satisfies_subst_instance_ctr u v ctrs
      (Hu : forallb (negb ∘ Level.is_prop) u)
  : satisfies v (subst_instance_cstrs u ctrs)
    <-> satisfies (subst_instance_valuation u v) ctrs.
Proof.
  split; intros Hv c Hc.
  - apply satisfies0_subst_instance_ctr; tas. apply Hv.
    apply In_subst_instance_cstrs. exists c; now split.
  - apply In_subst_instance_cstrs in Hc.
    destruct Hc as [c' [? Hc']]; subst.
    apply satisfies0_subst_instance_ctr; auto.
Qed.

(** global constraints are monomorphic *)

Lemma not_var_global_levels Σ (hΣ : wf Σ) :
  LS.For_all (negb ∘ Level.is_var) (global_levels Σ).
Proof.
  induction hΣ as [|Σ kn d hΣ IH HH univs Hu Hd].
  - intros l Hl. apply LevelSet_pair_In in Hl.
    destruct Hl as [Hl|Hl]; subst; reflexivity.
  - subst univs. intros l Hl. simpl in Hl; apply LS.union_spec in Hl.
    destruct Hl as [Hl|Hl]; auto. clear -Hu Hl.
    destruct d as [[? ? [φ|?]]|[? ? ? ? [φ|?]]]; cbn in *;
      unfold monomorphic_levels_decl in *; cbn in *;
      try now apply LS.empty_spec in Hl.
    all: destruct Hu as [_ [_ [Hu _]]];
      apply LevelSetFact.for_all_2 in Hu; auto.
    all: now intros x y [].
Qed.

Definition wf_ext_wk (Σ : global_env_ext)
  := wf Σ.1 × on_udecl_prop Σ.1 Σ.2.


Lemma not_var_global_ext_levels Σ φ (hΣ : wf_ext_wk (Σ, Monomorphic_ctx φ)) :
  LS.For_all (negb ∘ Level.is_var)
                   (global_ext_levels (Σ, Monomorphic_ctx φ)).
Proof.
  destruct hΣ as [hΣ Hφ].
  intros l Hl; apply LS.union_spec in Hl; destruct Hl as [Hl|Hl].
  - destruct Hφ as [_ [Hφ _]]. apply LevelSetFact.for_all_2 in Hφ; auto.
    now intros x y [].
  - eapply not_var_global_levels; eassumption.
Qed.

Lemma levels_global_constraint Σ (hΣ : wf Σ) c :
  CS.In c (global_constraints Σ)
  -> LS.In c.1.1 (global_levels Σ)
    /\ LS.In c.2 (global_levels Σ).
Proof.
  induction hΣ as [|Σ kn d hΣ IH HH univs Hu Hd].
  - intro H; now apply CS.empty_spec in H.
  - subst univs. intro Hc. simpl in *; apply CS.union_spec in Hc.
    destruct Hc as [Hc|Hc]; auto.
    + clear -Hu Hc.
      destruct d as [[? ? [φ|?]]|[? ? ? ? [φ|?]]]; cbn in *;
        unfold monomorphic_levels_decl, monomorphic_constraints_decl in *; cbn in *;
          try now apply CS.empty_spec in Hc.
      all: destruct Hu as [_ [Hu [_ _]]].
      all: destruct c as [[l1 c] l2]; exact (Hu _ Hc).
    + split; apply LS.union_spec; now right.
Qed.

Lemma levels_global_ext_constraint Σ φ (hΣ : wf_ext_wk (Σ, φ)) c :
  CS.In c (global_ext_constraints (Σ, φ))
  -> LS.In c.1.1 (global_ext_levels (Σ, φ))
    /\ LS.In c.2 (global_ext_levels (Σ, φ)).
Proof.
  intro H. apply CS.union_spec in H; simpl in H.
  destruct hΣ as [hΣ Hφ], H as [Hc|H]; simpl in *.
  - destruct Hφ as [Hφ _]. unfold global_ext_levels. simpl.
    destruct c as [[l1 c] l2]; exact  (Hφ _ Hc).
  - apply levels_global_constraint in H; tas.
    split; apply LS.union_spec; right; apply H.
Qed.

Definition is_monomorphic_cstr (c : UnivConstraint.t)
  := negb (Level.is_var c.1.1) && negb (Level.is_var c.2).

Lemma monomorphic_global_constraint Σ (hΣ : wf Σ) c :
  CS.In c (global_constraints Σ)
  -> is_monomorphic_cstr c.
Proof.
  intros H. apply levels_global_constraint in H; tas.
  apply andb_and. split; destruct H as [H1 H2].
  - now apply not_var_global_levels in H1.
  - now apply not_var_global_levels in H2.
Qed.

Lemma monomorphic_global_constraint_ext Σ φ
      (hΣ : wf_ext_wk (Σ, Monomorphic_ctx φ)) c :
  CS.In c (global_ext_constraints (Σ, Monomorphic_ctx φ))
  -> is_monomorphic_cstr c.
Proof.
  intros H. apply levels_global_ext_constraint in H; tas.
  apply andb_and. split; destruct H as [H1 H2].
  - now apply not_var_global_ext_levels in H1.
  - now apply not_var_global_ext_levels in H2.
Qed.

Hint Resolve monomorphic_global_constraint monomorphic_global_constraint_ext
  : univ_subst.

Lemma subst_instance_monom_cstr inst c :
  is_monomorphic_cstr c
  -> subst_instance_cstr inst c = c.
Proof.
  intro H; apply andb_and in H. destruct H.
  destruct c as [[[] ?] []]; cbnr; discriminate.
Qed.

Lemma satisfies_union v φ1 φ2 :
  satisfies v (CS.union φ1 φ2)
  <-> (satisfies v φ1 /\ satisfies v φ2).
Proof.
  unfold satisfies. split.
  - intros H; split; intros c Hc; apply H; now apply CS.union_spec.
  - intros [H1 H2] c Hc; apply CS.union_spec in Hc; destruct Hc; auto.
Qed.

Lemma equal_subst_instance_cstrs_mono u cstrs :
  CS.For_all is_monomorphic_cstr cstrs ->
  CS.Equal (subst_instance_cstrs u cstrs) cstrs.
Proof.
  intros HH c. etransitivity.
  - eapply In_subst_instance_cstrs.
  - split; intro H.
    + destruct H as [c' [eq Hc']]. subst; rewrite subst_instance_monom_cstr; aa.
    + exists c. rewrite subst_instance_monom_cstr; aa.
Qed.

Lemma subst_instance_cstrs_union u φ φ' :
  CS.Equal (subst_instance_cstrs u (CS.union φ φ'))
           (CS.union (subst_instance_cstrs u φ) (subst_instance_cstrs u φ')).
Proof.
  intro c; split; intro Hc.
  - apply In_subst_instance_cstrs in Hc.
    destruct Hc as [c' [eq Hc]]; subst.
    apply CS.union_spec in Hc. apply CS.union_spec.
    destruct Hc; [left|right]; now apply In_subst_instance_cstrs'.
  - apply In_subst_instance_cstrs.
    apply CS.union_spec in Hc.
    destruct Hc as [Hc|Hc]; apply In_subst_instance_cstrs in Hc;
      destruct Hc as [c'[eq Hc]]; exists c'; aa; apply CS.union_spec;
        [left|right]; aa.
Qed.

Hint Unfold CS.For_all : univ_subst.

Definition sub_context_set (φ φ' : ContextSet.t)
  := LS.Subset φ.1 φ'.1 /\ CS.Subset φ.2 φ'.2.

Definition global_ext_context_set Σ : ContextSet.t
  := (global_ext_levels Σ, global_ext_constraints Σ).

Global Instance sub_context_set_trans : RelationClasses.Transitive sub_context_set.
Proof.
  split; (etransitivity; [eapply H | eapply H0]).
Qed.


Lemma consistent_ext_trans_polymorphic_case_aux {Σ φ1 φ2 φ' udecl inst inst'} :
  wf_ext_wk (Σ, Polymorphic_ctx (φ1, φ2)) ->
  valid_constraints0 (global_ext_constraints (Σ, Polymorphic_ctx (φ1, φ2)))
                     (subst_instance_cstrs inst udecl) ->
  valid_constraints0 (global_ext_constraints (Σ, φ'))
                     (subst_instance_cstrs inst' φ2) ->
  forallb (fun x : Level.t => negb (Level.is_prop x)) inst' ->
  valid_constraints0 (global_ext_constraints (Σ, φ'))
                     (subst_instance_cstrs
                        (subst_instance_instance inst' inst) udecl).
Proof.
  intros [HΣ Hφ] H3 H2 H2'.
  intros v Hv. rewrite <- subst_instance_cstrs_two.
  apply satisfies_subst_instance_ctr; tas. apply H3.
  apply satisfies_union; simpl. split.
  - apply satisfies_subst_instance_ctr; auto.
  - apply satisfies_subst_instance_ctr; tas.
    rewrite equal_subst_instance_cstrs_mono; aa.
    apply satisfies_union in Hv; apply Hv.
Qed.

Lemma consistent_ext_trans_polymorphic_cases Σ φ φ' udecl inst inst' :
  wf_ext_wk (Σ, φ) ->
  sub_context_set (monomorphic_udecl φ) (global_ext_context_set (Σ, φ')) ->
  consistent_instance_ext (Σ, φ) (Polymorphic_ctx udecl) inst ->
  consistent_instance_ext (Σ, φ') φ inst' ->
  consistent_instance_ext (Σ, φ') (Polymorphic_ctx udecl)
                          (subst_instance_instance inst' inst).
Proof.
  intros HΣφ Hφ [H [H0 [H1 H3]]] H2.
  apply consistent_instance_no_prop in H2 as H2'.
  repeat split.
  3: now rewrite subst_instance_instance_length.
  + clear -H H2'.
    assert (HH: forall l, negb (Level.is_prop l) ->
                     negb (Level.is_prop (subst_instance_level inst' l))). {
      destruct l; cbnr; aa.
      eapply (forallb_nth' n Level.lSet) in H2'.
      destruct H2' as [[? [H2 ?]]|H2]; rewrite H2; auto. }
    induction inst; cbnr. rewrite HH; cbn. 1: apply IHinst.
    all: apply andP in H; try apply H.
  + rewrite forallb_map. apply forallb_forall.
    intros l Hl. unfold global_ext_levels in *; simpl in *.
    eapply forallb_forall in H0; tea. clear -Hφ H0 H2 Hl.
    apply LevelSet_mem_union in H0. destruct H0 as [H|H].
    2: { destruct l; simpl; try (apply LevelSet_mem_union; right; assumption).
         apply consistent_instance_declared in H2.
         apply (forallb_nth' n Level.lSet) in H2.
         destruct H2 as [[? [H2 ?]]|H2]; rewrite H2; tas.
         apply LevelSet_mem_union; right.
         apply global_levels_Set. }
    *  destruct l; simpl.
       -- apply LevelSet_mem_union; right; apply global_levels_Prop.
       -- apply LevelSet_mem_union; right; apply global_levels_Set.
       -- apply LS.mem_spec in H.
          destruct φ as [φ|[φ1 φ2]]; simpl in *.
          1: apply Hφ in H. 1: now apply LS.mem_spec.
          all: now apply monomorphic_level_notin_AUContext in H.
       -- apply consistent_instance_declared in H2.
          apply (forallb_nth' n Level.lSet) in H2.
          destruct H2 as [[? [H2 ?]]|H2]; rewrite H2; tas.
          apply LevelSet_mem_union; right; apply global_levels_Set.
  + unfold consistent_instance_ext, consistent_instance in H2.
    unfold valid_constraints in *; destruct check_univs; [|trivial].
    destruct φ as [φ|[φ1 φ2]]; simpl in *.
    * intros v Hv. rewrite <- subst_instance_cstrs_two.
      apply satisfies_subst_instance_ctr; tas.
      apply H3. apply satisfies_subst_instance_ctr; tas.
      rewrite equal_subst_instance_cstrs_mono; aa.
      apply satisfies_union; simpl; split.
      -- intros c Hc. now apply Hv, Hφ.
      -- apply satisfies_union in Hv; apply Hv.
    * destruct H2 as [_ [_ [_ H2]]].
      eapply consistent_ext_trans_polymorphic_case_aux; try eassumption.
Qed.

Lemma consistent_ext_trans Σ φ φ' udecl inst inst' :
  wf_ext_wk (Σ, φ) ->
  sub_context_set (monomorphic_udecl φ) (global_ext_context_set (Σ, φ')) ->
  consistent_instance_ext (Σ, φ) udecl inst ->
  consistent_instance_ext (Σ, φ') φ inst' ->
  consistent_instance_ext (Σ, φ') udecl (subst_instance_instance inst' inst).
Proof.
  intros HΣφ Hφ H1 H2. destruct udecl as [?|udecl].
  - (* udecl monomorphic *)
    cbn; now rewrite subst_instance_instance_length.
  - (* udecl polymorphic *)
    eapply consistent_ext_trans_polymorphic_cases; eassumption.
Qed.

Hint Resolve consistent_ext_trans : univ_subst.


Lemma consistent_instance_valid_constraints Σ φ u univs :
  wf_ext_wk (Σ, φ) ->
  CS.Subset (monomorphic_constraints φ)
                       (global_ext_constraints (Σ, univs)) ->
  consistent_instance_ext (Σ, univs) φ u ->
  valid_constraints (global_ext_constraints (Σ, univs))
                    (subst_instance_cstrs u (global_ext_constraints (Σ, φ))).
Proof.
  intros HΣ Hsub HH.
  apply consistent_instance_no_prop in HH as Hu.
  unfold valid_constraints; case_eq check_univs; [intro Hcf|trivial].
  intros v Hv. apply satisfies_subst_instance_ctr; tas.
  apply satisfies_union; simpl; split.
  - destruct φ as [φ|[φ1 φ2]].
    + cbn. apply satisfies_subst_instance_ctr; tas.
      rewrite equal_subst_instance_cstrs_mono; aa.
      * intros c Hc; apply Hsub in Hc. now apply Hv in Hc.
      * intros c Hc; eapply monomorphic_global_constraint_ext; tea.
        apply CS.union_spec; now left.
    + destruct HH as [_ [_ [_ H1]]].
      unfold valid_constraints in H1; rewrite Hcf in H1.
      apply satisfies_subst_instance_ctr; aa.
  - apply satisfies_subst_instance_ctr; tas.
    apply satisfies_union in Hv. destruct HΣ.
    rewrite equal_subst_instance_cstrs_mono; aa.
Qed.

Hint Resolve consistent_instance_valid_constraints : univ_subst.

Class SubstUnivPreserved {A} `{UnivSubst A} (R : ConstraintSet.t -> crelation A)
  := Build_SubstUnivPreserved :
       forall φ φ' (u : Instance.t),
         forallb (fun x => negb (Level.is_prop x)) u ->
         valid_constraints φ' (subst_instance_cstrs u φ) ->
         subrelation (R φ)
                     (precompose (R φ') (subst_instance u)).

Lemma satisfies_subst_instance φ φ' u :
  check_univs = true ->
  forallb (fun x => negb (Level.is_prop x)) u ->
  valid_constraints φ' (subst_instance_cstrs u φ) ->
  forall v, satisfies v φ' ->
       satisfies (subst_instance_valuation u v) φ.
Proof.
  intros Hcf Hu HH v Hv.
  unfold valid_constraints in HH; rewrite Hcf in HH.
  apply satisfies_subst_instance_ctr; aa.
Qed.

Global Instance leq_universe_subst_instance : SubstUnivPreserved leq_universe.
Proof.
  intros φ φ' u Hu HH t t' Htt'.
  unfold leq_universe in *; case_eq check_univs;
    [intro Hcf; rewrite Hcf in *|trivial].
  intros v Hv; cbn.
  rewrite !subst_instance_univ_val'; tas.
  apply Htt'. clear t t' Htt'.
  eapply satisfies_subst_instance; tea.
Qed.

Global Instance eq_universe_subst_instance : SubstUnivPreserved eq_universe.
Proof.
  intros φ φ' u Hu HH t t' Htt'.
  unfold eq_universe in *; case_eq check_univs;
    [intro Hcf; rewrite Hcf in *|trivial].
  intros v Hv; cbn.
  rewrite !subst_instance_univ_val'; tas.
  apply Htt'. clear t t' Htt'.
  eapply satisfies_subst_instance; tea.
Qed.

Lemma precompose_subst_instance_instance Rle u i i' :
  precompose (R_universe_instance Rle) (subst_instance_instance u) i i'
  <~> R_universe_instance (precompose Rle (subst_instance_univ u)) i i'.
Proof.
  unfold R_universe_instance, subst_instance_instance.
  replace (map Universe.make (map (subst_instance_level u) i))
    with (map (subst_instance_univ u) (map Universe.make i)).
  1: replace (map Universe.make (map (subst_instance_level u) i'))
      with (map (subst_instance_univ u) (map Universe.make i')).
  1: split.
  1: apply Forall2_map_inv.
  1: apply Forall2_map.
  all: rewrite !map_map; apply map_ext.
  all: intro; apply subst_instance_univ_make.
Qed.

Definition precompose_subst_instance_instance__1 Rle u i i'
  := equiv _ _ (precompose_subst_instance_instance Rle u i i').

Definition precompose_subst_instance_instance__2 Rle u i i'
  := equiv_inv _ _ (precompose_subst_instance_instance Rle u i i').

Lemma precompose_subst_instance_global Σ Re Rle gr u i i' :
  precompose (R_global_instance Σ Re Rle gr) (subst_instance_instance u) i i'
  <~> R_global_instance Σ (precompose Re (subst_instance_univ u)) 
    (precompose Rle (subst_instance_univ u)) gr i i'.
Proof.
  unfold R_global_instance, subst_instance_instance.
  destruct lookup_env as [[g|g]|]; eauto using precompose_subst_instance_instance.
  destruct ind_variance; eauto using precompose_subst_instance_instance.
  induction i in i', l |- *; destruct i', l; simpl; try split; auto.
  - destruct (IHi i' l). intros []; split; auto.
    destruct t0; simpl in *; auto.
    * now rewrite !subst_instance_univ_make.
    * now rewrite !subst_instance_univ_make.
  - destruct (IHi i' l). intros []; split; auto.
    destruct t0; simpl in *; auto.
    * now rewrite !subst_instance_univ_make in H.
    * now rewrite !subst_instance_univ_make in H.
Qed.

Definition precompose_subst_instance_global__1 Σ Re Rle gr u i i'
  := equiv _ _ (precompose_subst_instance_global Σ Re Rle gr u i i').

Definition precompose_subst_instance_global__2 Σ Re Rle gr u i i'
  := equiv_inv _ _ (precompose_subst_instance_global Σ Re Rle gr u i i').

Global Instance eq_term_upto_univ_subst_instance Σ
         (Re Rle : ConstraintSet.t -> Universe.t -> Universe.t -> Prop)
      {he: SubstUnivPreserved Re} {hle: SubstUnivPreserved Rle}
  : SubstUnivPreserved (fun φ => eq_term_upto_univ Σ (Re φ) (Rle φ)).
Proof.
  intros φ φ' u Hu HH t t'.
  specialize (he _ _ _ Hu HH).
  specialize (hle _ _ _ Hu HH).
  clear Hu HH.
  induction t in t', Rle, hle |- * using term_forall_list_ind;
    inversion 1; subst; cbn; constructor;
      eauto using precompose_subst_instance_instance__2, R_universe_instance_impl'.
  all: try (apply All2_map; eapply All2_impl'; tea;
    eapply All_impl; eauto; cbn; intros; aa).
  - inv X.
    eapply precompose_subst_instance_global__2.
    eapply R_global_instance_impl; eauto.
  - inv X.
    eapply precompose_subst_instance_global__2.
    eapply R_global_instance_impl; eauto.
Qed.

Lemma leq_term_subst_instance Σ : SubstUnivPreserved (leq_term Σ).
Proof. exact _. Qed.

Lemma eq_term_subst_instance Σ : SubstUnivPreserved (eq_term Σ).
Proof. exact _. Qed.



(** Now routine lemmas ... *)

Lemma subst_instance_univ_super l u
      (Hu : forallb (negb ∘ Level.is_prop) u)
  : subst_instance_univ u (Universe.super l)
    = Universe.super (subst_instance_level u l).
Proof.
  destruct l; cbnr.
  rewrite nth_nth_error.
  destruct nth_error; cbnr.
  destruct t; cbnr.
Qed.


Lemma LevelIn_subst_instance Σ l u univs :
  LS.In l (global_ext_levels Σ) ->
  LS.Subset (monomorphic_levels Σ.2) (global_ext_levels (Σ.1, univs)) ->
  consistent_instance_ext (Σ.1, univs) Σ.2 u ->
  LS.In (subst_instance_level u l) (global_ext_levels (Σ.1, univs)).
Proof.
  intros H H0 H'. destruct l; simpl.
  - apply LS.union_spec; right; simpl.
    apply LS.mem_spec, global_levels_Prop.
  - apply LS.union_spec; right; simpl.
    apply LS.mem_spec, global_levels_Set.
  - apply LS.union_spec in H; destruct H as [H|H]; simpl in *.
    + apply H0. destruct Σ as [? φ]; cbn in *; clear -H.
      destruct φ as [?|?]; tas;
        now apply monomorphic_level_notin_AUContext in H.
    + apply LS.union_spec; now right.
  - apply consistent_instance_declared in H'.
    apply (forallb_nth' n Level.lSet) in H'.
    destruct H' as [[? [eq ?]]|eq]; rewrite eq.
    + now apply LS.mem_spec.
    + apply LS.union_spec; right; simpl.
      apply LS.mem_spec, global_levels_Set.
Qed.


Lemma product_subst_instance u s1 s2
      (Hu : forallb (negb ∘ Level.is_prop) u)
 : subst_instance_univ u (Universe.sort_of_product s1 s2)
   = Universe.sort_of_product (subst_instance_univ u s1) (subst_instance_univ u s2).
Proof.
  unfold Universe.sort_of_product.
  rewrite is_prop_subst_instance_univ; tas.
  destruct (Universe.is_prop s2); cbn; try reflexivity.
  apply sup_subst_instance_univ.
Qed.


Lemma iota_red_subst_instance pars c args brs u :
  subst_instance_constr u (iota_red pars c args brs)
  = iota_red pars c (subst_instance u args) (subst_instance u brs).
Proof.
  unfold iota_red. rewrite !subst_instance_constr_mkApps.
  f_equal; simpl; eauto using map_skipn.
  rewrite nth_map; simpl; auto.
Qed.

Lemma fix_subst_subst_instance u mfix :
  map (subst_instance_constr u) (fix_subst mfix)
  = fix_subst (subst_instance u mfix).
Proof.
  unfold fix_subst. rewrite map_length.
  generalize #|mfix|. induction n. 1: reflexivity.
  simpl. rewrite IHn; reflexivity.
Qed.


Lemma cofix_subst_subst_instance u mfix :
  map (subst_instance_constr u) (cofix_subst mfix)
  = cofix_subst (subst_instance u mfix).
Proof.
  unfold cofix_subst. rewrite map_length.
  generalize #|mfix|. induction n. 1: reflexivity.
  simpl. rewrite IHn; reflexivity.
Qed.


Lemma isConstruct_app_subst_instance u t :
  isConstruct_app (subst_instance_constr u t) = isConstruct_app t.
Proof.
  unfold isConstruct_app.
  assert (HH: (decompose_app (subst_instance_constr u t)).1
              = subst_instance_constr u (decompose_app t).1). {
    unfold decompose_app. generalize (nil term) at 1. generalize (nil term).
    induction t; cbn; try reflexivity.
    intros l l'. erewrite IHt1; reflexivity. }
  rewrite HH. destruct (decompose_app t).1; reflexivity.
Qed.

Lemma fix_context_subst_instance u mfix :
  subst_instance_context u (fix_context mfix)
  = fix_context (subst_instance u mfix).
Proof.
  unfold subst_instance_context, map_context, fix_context.
  rewrite map_rev. f_equal.
  rewrite map_mapi, mapi_map. eapply mapi_ext.
  intros n x. unfold map_decl, vass; cbn. f_equal.
  symmetry; apply lift_subst_instance_constr.
Qed.

Lemma subst_instance_context_app u L1 L2 :
  subst_instance_context u (L1,,,L2)
  = subst_instance_context u L1 ,,, subst_instance_context u L2.
Proof.
  unfold subst_instance_context, map_context; now rewrite map_app.
Qed.

Lemma red1_subst_instance Σ Γ u s t :
  red1 Σ Γ s t ->
  red1 Σ (subst_instance_context u Γ)
       (subst_instance_constr u s) (subst_instance_constr u t).
Proof.
  intros X0. pose proof I as X.
  intros. induction X0 using red1_ind_all.
  all: try (cbn; econstructor; eauto; fail).
  - cbn. rewrite <- subst_subst_instance_constr. econstructor.
  - cbn. rewrite <- subst_subst_instance_constr. econstructor.
  - cbn. rewrite <- lift_subst_instance_constr. econstructor.
    unfold subst_instance_context.
    unfold option_map in *. destruct (nth_error Γ) eqn:E; inversion H.
    unfold map_context. rewrite nth_error_map, E. cbn.
    rewrite map_decl_body. destruct c. cbn in H1. subst.
    reflexivity.
  - cbn. rewrite subst_instance_constr_mkApps. cbn.
    rewrite iota_red_subst_instance. econstructor.
  - cbn. rewrite !subst_instance_constr_mkApps. cbn.
    econstructor.
    + unfold unfold_fix in *. destruct (nth_error mfix idx) eqn:E.
      * inversion H.
        rewrite nth_error_map, E. cbn.
        destruct d. cbn in *. cbn in *; try congruence.
        repeat f_equal.
        all: rewrite <- subst_subst_instance_constr;
          rewrite fix_subst_subst_instance; reflexivity.
      * inversion H.
    + unfold is_constructor in *.
      destruct (nth_error args narg) eqn:E; inversion H0; clear H0.
      rewrite nth_error_map, E. cbn.
      eapply isConstruct_app_subst_instance.
  - cbn. rewrite !subst_instance_constr_mkApps.
    unfold unfold_cofix in *. destruct (nth_error mfix idx) eqn:E.
    + inversion H.
      econstructor. fold subst_instance_constr.
      unfold unfold_cofix.
      rewrite nth_error_map, E. cbn.
      rewrite <- subst_subst_instance_constr.
      now rewrite cofix_subst_subst_instance.
    + econstructor. fold subst_instance_constr.
      inversion H.
  - cbn. unfold unfold_cofix in *.
    destruct nth_error eqn:E; inversion H.
    rewrite !subst_instance_constr_mkApps.
    econstructor. fold subst_instance_constr.
    unfold unfold_cofix.
    rewrite nth_error_map. destruct nth_error; cbn.
    1: rewrite <- subst_subst_instance_constr, cofix_subst_subst_instance.
    all: now inversion E.
  - cbn. rewrite subst_instance_constr_two. econstructor; eauto.
  - cbn. rewrite !subst_instance_constr_mkApps.
    econstructor. now rewrite nth_error_map, H.
  - cbn. econstructor; eauto.
    eapply OnOne2_map. eapply OnOne2_impl. 1: eassumption.
    firstorder.
  - cbn; econstructor;
    eapply OnOne2_map; eapply OnOne2_impl; [ eassumption | firstorder].
  - cbn; econstructor;
      eapply OnOne2_map; eapply OnOne2_impl; [ eassumption | ].
    intros. destruct X1. destruct p. inversion e. destruct x, y; cbn in *; subst.
    red. split; cbn; eauto.
  - cbn. eapply fix_red_body.
      eapply OnOne2_map; eapply OnOne2_impl; [ eassumption | ].
    intros. destruct X1. destruct p. inversion e. destruct x, y; cbn in *; subst.
    red. split; cbn; eauto.
    rewrite <- (fix_context_subst_instance u mfix0).
    unfold subst_instance_context, map_context in *. rewrite map_app in *.
    eassumption.
  - cbn; econstructor;
      eapply OnOne2_map; eapply OnOne2_impl; [ eassumption | ].
    intros. destruct X1. destruct p. inversion e. destruct x, y; cbn in *; subst.
    red. split; cbn; eauto.
  - cbn. eapply cofix_red_body.
      eapply OnOne2_map; eapply OnOne2_impl; [ eassumption | ].
    intros. destruct X1. destruct p. inversion e. destruct x, y; cbn in *; subst.
    red. split; cbn; eauto.
    rewrite <- (fix_context_subst_instance u mfix0).
    unfold subst_instance_context, map_context in *. rewrite map_app in *.
    eassumption.
    Grab Existential Variables. all:repeat econstructor.
Qed.

Fixpoint subst_instance_stack l π :=
  match π with
  | ε => ε
  | App u π =>
      App (subst_instance_constr l u) (subst_instance_stack l π)
  | Fix mfix idx args π =>
      let mfix' := List.map (map_def (subst_instance_constr l) (subst_instance_constr l)) mfix in
      Fix mfix' idx (map (subst_instance_constr l) args) (subst_instance_stack l π)
  | Fix_mfix_ty na bo ra mfix1 mfix2 idx π =>
      let mfix1' := List.map (map_def (subst_instance_constr l) (subst_instance_constr l)) mfix1 in
      let mfix2' := List.map (map_def (subst_instance_constr l) (subst_instance_constr l)) mfix2 in
      Fix_mfix_ty na (subst_instance_constr l bo) ra mfix1' mfix2' idx (subst_instance_stack l π)
  | Fix_mfix_bd na ty ra mfix1 mfix2 idx π =>
      let mfix1' := List.map (map_def (subst_instance_constr l) (subst_instance_constr l)) mfix1 in
      let mfix2' := List.map (map_def (subst_instance_constr l) (subst_instance_constr l)) mfix2 in
      Fix_mfix_bd na (subst_instance_constr l ty) ra mfix1' mfix2' idx (subst_instance_stack l π)
  | CoFix mfix idx args π =>
      let mfix' := List.map (map_def (subst_instance_constr l) (subst_instance_constr l)) mfix in
      CoFix mfix' idx (map (subst_instance_constr l) args) (subst_instance_stack l π)
  | Case_p indn c brs π =>
      let brs' := List.map (on_snd (subst_instance_constr l)) brs in
      Case_p indn (subst_instance_constr l c) brs' (subst_instance_stack l π)
  | Case indn pred brs π =>
      let brs' := List.map (on_snd (subst_instance_constr l)) brs in
      Case indn (subst_instance_constr l pred) brs' (subst_instance_stack l π)
  | Case_brs indn pred c m brs1 brs2 π =>
      let brs1' := List.map (on_snd (subst_instance_constr l)) brs1 in
      let brs2' := List.map (on_snd (subst_instance_constr l)) brs2 in
      Case_brs indn (subst_instance_constr l pred) (subst_instance_constr l c) m brs1' brs2' (subst_instance_stack l π)
  | Proj p π =>
      Proj p (subst_instance_stack l π)
  | Prod_l na B π =>
      Prod_l na (subst_instance_constr l B) (subst_instance_stack l π)
  | Prod_r na A π =>
      Prod_r na (subst_instance_constr l A) (subst_instance_stack l π)
  | Lambda_ty na b π =>
      Lambda_ty na (subst_instance_constr l b) (subst_instance_stack l π)
  | Lambda_tm na A π =>
      Lambda_tm na (subst_instance_constr l A) (subst_instance_stack l π)
  | LetIn_bd na B u π =>
      LetIn_bd na (subst_instance_constr l B) (subst_instance_constr l u) (subst_instance_stack l π)
  | LetIn_ty na b u π =>
      LetIn_ty na (subst_instance_constr l b) (subst_instance_constr l u) (subst_instance_stack l π)
  | LetIn_in na b B π =>
      LetIn_in na (subst_instance_constr l b) (subst_instance_constr l B) (subst_instance_stack l π)
  | coApp u π =>
      coApp (subst_instance_constr l u) (subst_instance_stack l π)
  end.

Lemma subst_instance_constr_zipc :
  forall l t π,
    subst_instance_constr l (zipc t π) =
    zipc (subst_instance_constr l t) (subst_instance_stack l π).
Proof.
  intros l t π.
  induction π in l, t |- *.
  all: try reflexivity.
  all: try solve [
    simpl ; rewrite IHπ ; cbn ; reflexivity
  ].
  - simpl. rewrite IHπ. cbn. f_equal.
    rewrite subst_instance_constr_mkApps. cbn. reflexivity.
  - simpl. rewrite IHπ. cbn. f_equal. f_equal.
    rewrite map_app. cbn. reflexivity.
  - simpl. rewrite IHπ. cbn. f_equal. f_equal.
    rewrite map_app. cbn. reflexivity.
  - simpl. rewrite IHπ. cbn. f_equal. f_equal.
    rewrite subst_instance_constr_mkApps. cbn. reflexivity.
  - simpl. rewrite IHπ. cbn. f_equal. f_equal.
    rewrite map_app. cbn. reflexivity.
Qed.

Lemma eta_expands_subst_instance_constr :
  forall l u v,
    eta_expands u v ->
    eta_expands (subst_instance_constr l u) (subst_instance_constr l v).
Proof.
  intros l u v [na [A [f [π [? ?]]]]]. subst.
  rewrite 2!subst_instance_constr_zipc. cbn.
  eexists _, _, _, _. intuition eauto.
  f_equal. f_equal. f_equal.
  rewrite lift_subst_instance_constr. reflexivity.
Qed.

Lemma cumul_subst_instance (Σ : global_env_ext) Γ u A B univs :
  forallb (fun x => negb (Level.is_prop x)) u ->
  valid_constraints (global_ext_constraints (Σ.1, univs))
                    (subst_instance_cstrs u Σ) ->
  Σ ;;; Γ |- A <= B ->
  (Σ.1,univs) ;;; subst_instance_context u Γ
                   |- subst_instance_constr u A <= subst_instance_constr u B.
Proof.
  intros Hu HH X0. induction X0.
  - econstructor.
    eapply leq_term_subst_instance; tea.
  - econstructor 2. 1: eapply red1_subst_instance; cbn; eauto. eauto.
  - econstructor 3. 1: eauto. eapply red1_subst_instance; cbn; eauto.
  - eapply cumul_eta_l. 2: eauto.
    eapply eta_expands_subst_instance_constr. assumption.
  - eapply cumul_eta_r. 1: eauto.
    eapply eta_expands_subst_instance_constr. assumption.
Qed.

Global Instance eq_decl_subst_instance Σ : SubstUnivPreserved (eq_decl Σ).
Proof.
  intros φ1 φ2 u Hu HH [? [?|] ?] [? [?|] ?] [H1 H2]; split; cbn in *; auto.
  all: eapply eq_term_subst_instance; tea.
Qed.

Global Instance eq_context_subst_instance Σ : SubstUnivPreserved (eq_context Σ).
Proof.
  intros φ φ' u Hu HH Γ Γ' X. eapply All2_map, All2_impl; tea.
  eapply eq_decl_subst_instance; eassumption.
Qed.

Lemma subst_instance_destArity Γ A u :
  destArity (subst_instance_context u Γ) (subst_instance_constr u A)
  = match destArity Γ A with
    | Some (ctx, s) => Some (subst_instance_context u ctx, subst_instance_univ u s)
    | None => None
    end.
Proof.
  induction A in Γ |- *; simpl; try reflexivity.
  - change (subst_instance_context u Γ,, vass na (subst_instance_constr u A1))
      with (subst_instance_context u (Γ ,, vass na A1)).
    now rewrite IHA2.
  - change (subst_instance_context u Γ ,,
               vdef na (subst_instance_constr u A1) (subst_instance_constr u A2))
      with (subst_instance_context u (Γ ,, vdef na A1 A2)).
    now rewrite IHA3.
Qed.


Lemma subst_instance_instantiate_params_subst u0 params pars s ty :
  option_map (on_pair (map (subst_instance_constr u0)) (subst_instance_constr u0))
             (instantiate_params_subst params pars s ty)
  = instantiate_params_subst (subst_instance_context u0 params)
                             (map (subst_instance_constr u0) pars)
                             (map (subst_instance_constr u0) s)
                             (subst_instance_constr u0 ty).
Proof.
  induction params in pars, s, ty |- *; cbn.
  - destruct pars; cbnr.
  - destruct ?; cbnr; destruct ?; cbnr.
    + rewrite IHparams; cbn. repeat f_equal.
      symmetry; apply subst_subst_instance_constr.
    + destruct ?; cbnr. now rewrite IHparams.
Qed.

Lemma subst_instance_instantiate_params u0 params pars ty :
  option_map (subst_instance_constr u0)
             (instantiate_params params pars ty)
  = instantiate_params (subst_instance_context u0 params)
                       (map (subst_instance_constr u0) pars)
                       (subst_instance_constr u0 ty).
Proof.
  unfold instantiate_params.
  change (nil term) with (map (subst_instance_constr u0) []) at 2.
  rewrite rev_subst_instance_context.
  rewrite <- subst_instance_instantiate_params_subst.
  destruct ?; cbnr. destruct p; cbn.
  now rewrite subst_subst_instance_constr.
Qed.

Lemma subst_instance_inds u0 ind u bodies :
  subst_instance u0 (inds ind u bodies)
  = inds ind (subst_instance u0 u) bodies.
Proof.
  unfold inds.
  induction #|bodies|; cbnr.
  f_equal. apply IHn.
Qed.

Lemma subst_instance_decompose_prod_assum u Γ t :
  subst_instance u (decompose_prod_assum Γ t)
  = decompose_prod_assum (subst_instance_context u Γ) (subst_instance_constr u t).
Proof.
  induction t in Γ |- *; cbnr.
  - apply IHt2.
  - apply IHt3.
Qed.

Lemma subst_instance_decompose_app_rec u Γ t
  : subst_instance u (decompose_app_rec t Γ)
    = decompose_app_rec (subst_instance u t) (subst_instance u Γ).
Proof.
  induction t in Γ |- *; cbnr.
  now rewrite IHt1.
Qed.

Lemma subst_instance_decompose_app u t
  : subst_instance u (decompose_app t) = decompose_app (subst_instance u t).
Proof.
  unfold decompose_app. now rewrite (subst_instance_decompose_app_rec u []).
Qed.

Lemma subst_instance_to_extended_list u l
  : map (subst_instance_constr u) (to_extended_list l)
    = to_extended_list (subst_instance_context u l).
Proof.
  - unfold to_extended_list, to_extended_list_k.
    change [] with (map (subst_instance_constr u) []) at 2.
    unf_term. generalize (nil term), 0. induction l as [|[aa [ab|] ac] bb].
    + reflexivity.
    + intros l n; cbn. now rewrite IHbb.
    + intros l n; cbn. now rewrite IHbb.
Qed.

Lemma subst_instance_build_branches_type u0 ind mdecl idecl pars u p :
  map (option_map (on_snd (subst_instance_constr u0)))
      (build_branches_type ind mdecl idecl pars u p)
  = build_branches_type ind mdecl idecl (map (subst_instance_constr u0) pars)
                        (subst_instance_instance u0 u) (subst_instance_constr u0 p).
Proof.
  rewrite !build_branches_type_. rewrite map_mapi.
  eapply mapi_ext.
  intros n [[id t] k]; cbn.
  rewrite <- subst_instance_context_two.
  rewrite <- subst_instance_constr_two.
  rewrite <- subst_instance_inds.
  rewrite subst_subst_instance_constr.
  rewrite <- subst_instance_instantiate_params.
  rewrite !option_map_two. apply option_map_ext.
  intros x. rewrite <- (subst_instance_decompose_prod_assum u0 [] x).
  destruct (decompose_prod_assum [] x). simpl.
  unfold decompose_app; rewrite <- (subst_instance_decompose_app_rec u0 [] t0).
  destruct (decompose_app_rec t0 []); cbn.
  unfold subst_instance, subst_instance_list.
  case_eq (chop (ind_npars mdecl) l); intros l0 l1 H.
  eapply chop_map in H; rewrite H; clear H.
  unfold on_snd; cbn. f_equal.
  rewrite subst_instance_constr_it_mkProd_or_LetIn. f_equal.
  rewrite subst_instance_constr_mkApps; f_equal.
  - rewrite subst_instance_context_length.
    symmetry; apply lift_subst_instance_constr.
  - rewrite map_app; f_equal; cbn.
    rewrite subst_instance_constr_mkApps, map_app; cbn; repeat f_equal.
    apply subst_instance_to_extended_list.
Qed.

Lemma subst_instance_subst_context u s k Γ : 
  subst_instance_context u (subst_context s k Γ) =
  subst_context (map (subst_instance_constr u) s) k (subst_instance_context u Γ).
Proof.
  unfold subst_instance_context, map_context.
  rewrite !subst_context_alt.
  rewrite map_mapi, mapi_map. apply mapi_rec_ext.
  intros. unfold subst_decl; rewrite !PCUICAstUtils.compose_map_decl.
  apply PCUICAstUtils.map_decl_ext; intros decl.
  rewrite map_length. now rewrite subst_subst_instance_constr.
Qed.

Lemma subst_instance_context_smash u Γ Δ : 
  subst_instance_context u (smash_context Δ Γ) = 
  smash_context (subst_instance_context u Δ) (subst_instance_context u Γ).
Proof.
  induction Γ as [|[? [] ?] ?] in Δ |- *; simpl; auto.
  - rewrite IHΓ. f_equal.
    now rewrite subst_instance_subst_context.
  - rewrite IHΓ, subst_instance_context_app; trivial.
Qed.

Lemma destInd_subst_instance u t : 
  destInd (subst_instance u t) = option_map (fun '(i, u') => (i, subst_instance u u')) (destInd t).
Proof.
  destruct t; simpl; try congruence.
  f_equal.
Qed.

Lemma subst_instance_context_assumptions u ctx :
  context_assumptions (subst_instance_context u ctx)
  = context_assumptions ctx.
Proof.
  induction ctx; cbnr.
  destruct (decl_body a); cbn; now rewrite IHctx.
Qed.

Hint Rewrite subst_instance_context_assumptions : len.


Lemma subst_instance_check_one_fix u mfix :
  map
        (fun x : def term =>
        check_one_fix (map_def (subst_instance_constr u) (subst_instance_constr u) x)) mfix =
  map check_one_fix mfix.
Proof.
  apply map_ext. intros [na ty def rarg]; simpl.
  rewrite decompose_prod_assum_ctx.
  destruct (decompose_prod_assum _ ty) eqn:decomp.
  rewrite decompose_prod_assum_ctx in decomp.
  erewrite <-(subst_instance_decompose_prod_assum u []).
  destruct (decompose_prod_assum [] ty) eqn:decty.
  rewrite app_context_nil_l in decomp.
  injection decomp. intros -> ->. clear decomp.
  simpl. rewrite !app_context_nil_l, <- (subst_instance_context_smash u _ []).
  unfold subst_instance_context, map_context.
  rewrite <- map_rev. rewrite nth_error_map.
  destruct nth_error as [d|] eqn:Hnth; simpl; auto.
  rewrite <- subst_instance_decompose_app.
  destruct (decompose_app (decl_type d)) eqn:Happ.
  simpl.
  rewrite destInd_subst_instance.
  destruct destInd as [[i u']|]; simpl; auto.
Qed.

Lemma subst_instance_check_one_cofix u mfix :
  map
        (fun x : def term =>
        check_one_cofix (map_def (subst_instance_constr u) (subst_instance_constr u) x)) mfix =
  map check_one_cofix mfix.
Proof.
  apply map_ext. intros [na ty def rarg]; simpl.
  rewrite decompose_prod_assum_ctx.
  destruct (decompose_prod_assum _ ty) eqn:decomp.
  rewrite decompose_prod_assum_ctx in decomp.
  rewrite <- (subst_instance_decompose_prod_assum _ []).
  destruct (decompose_prod_assum [] ty) eqn:decty.
  rewrite app_context_nil_l in decomp.
  injection decomp; intros -> ->; clear decomp.
  simpl.
  destruct (decompose_app t) eqn:Happ.
  rewrite <- subst_instance_decompose_app, Happ. simpl.
  rewrite destInd_subst_instance.
  destruct destInd as [[i u']|]; simpl; auto.
Qed.

Axiom fix_guard_subst_instance :
  forall mfix u,
    fix_guard mfix ->
    fix_guard (map (map_def (subst_instance_constr u) (subst_instance_constr u))
                   mfix).


Axiom cofix_guard_subst_instance :
  forall mfix u,
  cofix_guard mfix ->
  cofix_guard (map (map_def (subst_instance_constr u) (subst_instance_constr u))
                  mfix).

                 
Lemma All_local_env_over_subst_instance Σ Γ (wfΓ : wf_local Σ Γ) :
  All_local_env_over typing
                     (fun Σ0 Γ0 (_ : wf_local Σ0 Γ0) t T (_ : Σ0;;; Γ0 |- t : T) =>
       forall u univs, wf_ext_wk Σ0 ->
                  sub_context_set (monomorphic_udecl Σ0.2)
                                  (global_ext_context_set (Σ0.1, univs)) ->
                  consistent_instance_ext (Σ0.1, univs) Σ0.2 u ->
                  (Σ0.1, univs) ;;; subst_instance_context u Γ0
                  |- subst_instance_constr u t : subst_instance_constr u T)
                     Σ Γ wfΓ ->
  forall u univs,
    wf_ext_wk Σ ->
    sub_context_set (monomorphic_udecl Σ.2)
                    (global_ext_context_set (Σ.1, univs)) ->
    consistent_instance_ext (Σ.1, univs) Σ.2 u ->
    wf_local (Σ.1, univs) (subst_instance_context u Γ).
Proof.
  induction 1; simpl; constructor; cbn in *; auto.
  all: destruct tu; eexists; cbn in *; eauto.
Qed.

Hint Resolve All_local_env_over_subst_instance : univ_subst.

Lemma typing_subst_instance :
  env_prop (fun Σ Γ t T => forall u univs,
                wf_ext_wk Σ ->
                sub_context_set (monomorphic_udecl Σ.2)
                                (global_ext_context_set (Σ.1, univs)) ->
                consistent_instance_ext (Σ.1, univs) Σ.2 u ->
                (Σ.1,univs) ;;; subst_instance_context u Γ
                |- subst_instance_constr u t : subst_instance_constr u T)
          (fun Σ Γ wfΓ => forall u univs,
          wf_ext_wk Σ ->
          sub_context_set (monomorphic_udecl Σ.2)
                          (global_ext_context_set (Σ.1, univs)) ->
          consistent_instance_ext (Σ.1, univs) Σ.2 u ->
          wf_local(Σ.1,univs) (subst_instance_context u Γ)).
Proof.
  apply typing_ind_env; intros Σ wfΣ Γ wfΓ; cbn  -[Universe.make] in *.
  - induction 1.
    + constructor.
    + simpl. constructor; auto.
      exists (subst_instance_univ u tu.π1). eapply p; auto.
    + simpl. constructor; auto.
      ++ exists (subst_instance_univ u tu.π1). eapply p0; auto.
      ++ apply p; auto. 

  - intros n decl eq X u univs wfΣ' H Hsub. rewrite <- lift_subst_instance_constr.
    rewrite map_decl_type. econstructor; aa.
    unfold subst_instance_context, map_context.
    now rewrite nth_error_map, eq.
  - intros l X Hl u univs wfΣ' HSub H.
    rewrite subst_instance_univ_super, subst_instance_univ_make.
    + econstructor.
      * aa.
      * destruct HSub. eapply LevelIn_subst_instance; eauto.
    + eapply consistent_instance_no_prop; eassumption.
  - intros n t0 b s1 s2 X X0 X1 X2 X3 u univs wfΣ' HSub H.
    rewrite product_subst_instance; aa. econstructor.
    + eapply X1; eauto.
    + eapply X3; eauto.
  - intros n t0 b s1 bty X X0 X1 X2 X3 u univs wfΣ' HSub H.
    econstructor.
    + eapply X1; aa.
    + eapply X3; aa.
  - intros n b b_ty b' s1 b'_ty X X0 X1 X2 X3 X4 X5 u univs wfΣ' HSub H.
    econstructor; eauto. eapply X5; aa.
  - intros t0 na A B u X X0 X1 X2 X3 u0 univs wfΣ' HSub H.
    rewrite <- subst_subst_instance_constr. cbn. econstructor.
    + eapply X1; eauto.
    + eapply X3; eauto.
  - intros. rewrite subst_instance_constr_two. econstructor; [aa|aa|].
    clear X X0; cbn in *.
    eapply consistent_ext_trans; eauto.
  - intros. rewrite subst_instance_constr_two. econstructor; [aa|aa|].
    clear X X0; cbn in *.
    eapply consistent_ext_trans; eauto.
  - intros. eapply meta_conv. 1: econstructor; aa.
    clear.
    unfold type_of_constructor; cbn.
    rewrite <- subst_subst_instance_constr. f_equal.
    + unfold inds. induction #|ind_bodies mdecl|. 1: reflexivity.
      cbn. now rewrite IHn.
    + symmetry; apply subst_instance_constr_two.

  - intros ind u npar p c brs args mdecl idecl isdecl X X0 H ps pty H0 X1
           X2 H1 X3 notCoFinite X4 btys H2 X5 u0 univs X6 HSub H4.
    rewrite subst_instance_constr_mkApps in *.
    rewrite map_app. cbn. rewrite map_skipn.
    eapply type_Case with (u1:=subst_instance_instance u0 u)
                          (ps0 :=subst_instance_univ u0 ps)
                          (btys0:=map (on_snd (subst_instance_constr u0)) btys);
      eauto.
    + clear -H0. rewrite firstn_map. unfold build_case_predicate_type. simpl.
      rewrite <- subst_instance_constr_two, <- subst_instance_context_two.
      set (param' := subst_instance_context u (ind_params mdecl)) in *.
      set (type' := subst_instance_constr u (ind_type idecl)) in *.
      rewrite <- subst_instance_instantiate_params.
      destruct (instantiate_params param' (firstn npar args) type');
        [|discriminate].
      simpl. rewrite (subst_instance_destArity []).
      destruct (destArity [] t) as [[ctx s']|]; [|discriminate].
      apply some_inj in H0; subst; simpl in *. f_equal.
      rewrite subst_instance_constr_it_mkProd_or_LetIn. f_equal; cbn.
      unf_term. f_equal. rewrite subst_instance_constr_mkApps; cbn.
      f_equal. rewrite map_app. f_equal.
      * rewrite !map_map, subst_instance_context_length; apply map_ext. clear.
        intro. now apply lift_subst_instance_constr.
      * symmetry; apply subst_instance_to_extended_list.
    + clear -H1 H4.
      unfold universe_family in *.
      rewrite is_prop_subst_instance_univ; [|aa].
      destruct (Universe.is_prop ps); cbnr.
      case_eq (Universe.is_small ps); intro HH; rewrite HH in H1.
      ++ apply (is_small_subst_instance_univ u0) in HH.
         now rewrite HH.
      ++ destruct (ind_kelim idecl); inv H1.
         destruct ?; constructor.
    + eapply X4 in H4; tea.
      rewrite subst_instance_constr_mkApps in H4; eassumption.
    + cbn. rewrite firstn_map. rewrite <- subst_instance_build_branches_type.
      now rewrite map_option_out_map_option_map, H2.
    + eapply All2_map with (f := (on_snd (subst_instance_constr u0)))
                           (g:= (on_snd (subst_instance_constr u0))).
      eapply All2_impl. 1: eassumption.
      intros.
      simpl in X7. destruct X7 as [[[? ?] ?] ?]. intuition eauto.
      * cbn. eauto.
      * cbn.
        destruct x, y; cbn in *; subst.
        eapply t1; assumption.

  - intros p c u mdecl idecl pdecl isdecl args X X0 X1 X2 H u0 univs wfΣ' HSub H0.
    rewrite <- subst_subst_instance_constr. cbn.
    rewrite !subst_instance_constr_two.
    rewrite map_rev. econstructor; eauto. 2:now rewrite map_length.
    eapply X2 in H0; tas. rewrite subst_instance_constr_mkApps in H0.
    eassumption.

  - intros mfix n decl H H0 H1 X X0 wffix u univs wfΣ' HSub.
    erewrite map_dtype. econstructor.
    + now apply fix_guard_subst_instance.
    + rewrite nth_error_map, H0. reflexivity.
    + eapply H1; eauto. 
    + apply All_map, (All_impl X); simpl; intuition auto.
      destruct X1 as [s Hs]. exists (subst_instance_univ u s).
      now apply Hs.
    + eapply All_map, All_impl; tea.
      intros x [[X1 X2] X3]. split.
      * specialize (X3 u univs wfΣ' HSub H2). erewrite map_dbody in X3.
        rewrite <- lift_subst_instance_constr in X3.
        rewrite fix_context_length, map_length in *.
        erewrite map_dtype with (d := x) in X3.
        unfold subst_instance_context, map_context in *.
        rewrite map_app in *.
        rewrite <- (fix_context_subst_instance u mfix).
        eapply X3.
      * destruct x as [? ? []]; cbn in *; tea.
    + red; rewrite <- wffix.
      unfold wf_fixpoint.
      rewrite map_map_compose.
      now rewrite subst_instance_check_one_fix.

  - intros mfix n decl guard H X X0 X1 wfcofix u univs wfΣ' HSub H1.
    erewrite map_dtype. econstructor; tas.
    + now apply cofix_guard_subst_instance.
    + rewrite nth_error_map, H. reflexivity.
    + apply X; eauto.
    + apply All_map, (All_impl X0); simpl; intuition auto.
      destruct X2 as [s Hs]. exists (subst_instance_univ u s).
      now apply Hs.
    + eapply All_map, All_impl; tea.
      intros x [X1' X3].
      * specialize (X3 u univs wfΣ' HSub H1). erewrite map_dbody in X3.
        rewrite <- lift_subst_instance_constr in X3.
        rewrite fix_context_length, map_length in *.
        unfold subst_instance_context, map_context in *.
        rewrite map_app in *.
        rewrite <- (fix_context_subst_instance u mfix).
        rewrite <- map_dtype. eapply X3.
    + red; rewrite <- wfcofix.
      unfold wf_cofixpoint.
      rewrite map_map_compose.
      now rewrite subst_instance_check_one_cofix.
      
  - intros t0 A B X X0 X1 X2 X3 u univs wfΣ' HSub H.
    econstructor.
    + eapply X1; aa.
    + destruct X2; [left|right].
      * clear -i H wfΣ' HSub. destruct i as [[ctx [s [H1 H2]]] HH]; cbn in HH.
        exists (subst_instance_context u ctx), (subst_instance_univ u s). split.
        1: now rewrite (subst_instance_destArity []), H1.
        rewrite <- subst_instance_context_app. unfold app_context in *.
        revert H2 HH. generalize (ctx ++ Γ).
        induction 1; simpl; constructor; auto; cbn in *.
        -- eexists. eapply p; tas.
        -- eexists. eapply p0; tas.
        -- eapply p; tas.
      * aa.
    + destruct HSub. eapply cumul_subst_instance; aa.
Qed.


Lemma typing_subst_instance' Σ φ Γ t T u univs :
  wf_ext_wk (Σ, univs) ->
  (Σ, univs) ;;; Γ |- t : T ->
  sub_context_set (monomorphic_udecl univs) (global_ext_context_set (Σ, φ)) ->
  consistent_instance_ext (Σ, φ) univs u ->
  (Σ, φ) ;;; subst_instance_context u Γ
            |- subst_instance_constr u t : subst_instance_constr u T.
Proof.
  intros X X0 X1.
  eapply (typing_subst_instance (Σ, univs)); tas. apply X.
Qed.

Lemma typing_subst_instance_wf_local Σ φ Γ u univs :
  wf_ext_wk (Σ, univs) ->
  wf_local (Σ, univs) Γ ->
  sub_context_set (monomorphic_udecl univs) (global_ext_context_set (Σ, φ)) ->
  consistent_instance_ext (Σ, φ) univs u ->
  wf_local (Σ, φ) (subst_instance_context u Γ).
Proof.
  intros X X0 X1.
  eapply (env_prop_wf_local _ _ typing_subst_instance (Σ, univs)); tas. 1: apply X.
Qed.


Definition global_context_set Σ : ContextSet.t
  := (global_levels Σ, global_constraints Σ).

Lemma global_context_set_sub_ext Σ φ :
  sub_context_set (global_context_set Σ) (global_ext_context_set (Σ, φ)).
Proof.
  split.
  - cbn. apply LevelSetProp.union_subset_2.
  - apply ConstraintSetProp.union_subset_2.
Qed.


Lemma weaken_lookup_on_global_env'' Σ c decl :
  wf Σ ->
  lookup_env Σ c = Some decl ->
  sub_context_set (monomorphic_udecl (universes_decl_of_decl decl))
                  (global_context_set Σ).
Proof.
  intros X1 X2; pose proof (weaken_lookup_on_global_env' _ _ _ X1 X2) as XX.
  set (φ := universes_decl_of_decl decl) in *; clearbody φ. clear -XX.
  destruct φ as [φ|φ].
  - split; apply XX.
  - split;
    [apply LevelSetProp.subset_empty|apply ConstraintSetProp.subset_empty].
Qed.


Lemma typing_subst_instance'' Σ φ Γ t T u univs :
  wf_ext_wk (Σ, univs) ->
  (Σ, univs) ;;; Γ |- t : T ->
  sub_context_set (monomorphic_udecl univs) (global_context_set Σ) ->
  consistent_instance_ext (Σ, φ) univs u ->
  (Σ, φ) ;;; subst_instance_context u Γ
            |- subst_instance_constr u t : subst_instance_constr u T.
Proof.
  intros X X0 X1.
  eapply (typing_subst_instance (Σ, univs)); tas. 1: apply X.
  etransitivity; tea. apply global_context_set_sub_ext.
Qed.


Lemma typing_subst_instance_decl Σ Γ t T c decl u :
  wf Σ.1 ->
  lookup_env Σ.1 c = Some decl ->
  (Σ.1, universes_decl_of_decl decl) ;;; Γ |- t : T ->
  consistent_instance_ext Σ (universes_decl_of_decl decl) u ->
  Σ ;;; subst_instance_context u Γ
            |- subst_instance_constr u t : subst_instance_constr u T.
Proof.
  destruct Σ as [Σ φ]. intros X X0 X1 X2.
  eapply typing_subst_instance''; tea.
  - split; tas.
    eapply weaken_lookup_on_global_env'; tea.
  - eapply weaken_lookup_on_global_env''; tea.
Qed.

Definition wf_global_ext Σ ext :=
  (wf_ext_wk (Σ, ext) * sub_context_set (monomorphic_udecl ext) (global_context_set Σ))%type.

Lemma wf_local_subst_instance Σ Γ ext u :
  wf_global_ext Σ.1 ext ->
  consistent_instance_ext Σ ext u ->
  wf_local (Σ.1, ext) Γ ->
  wf_local Σ (subst_instance_context u Γ).
Proof.
  destruct Σ as [Σ φ]. intros X X0 X1. simpl in *.
  induction X1; cbn; constructor; auto.
  - destruct t0 as [s Hs]. hnf.
    eapply typing_subst_instance'' in Hs; eauto; apply X.
  - destruct t0 as [s Hs]. hnf.
    eapply typing_subst_instance'' in Hs; eauto; apply X. 
  - hnf in t1 |- *.
    eapply typing_subst_instance'' in t1; eauto; apply X.
Qed.

Lemma wf_local_subst_instance_decl Σ Γ c decl u :
  wf Σ.1 ->
  lookup_env Σ.1 c = Some decl ->
  wf_local (Σ.1, universes_decl_of_decl decl) Γ ->
  consistent_instance_ext Σ (universes_decl_of_decl decl) u ->
  wf_local Σ (subst_instance_context u Γ).
Proof.
  destruct Σ as [Σ φ]. intros X X0 X1 X2.
  induction X1; cbn; constructor; auto.
  - destruct t0 as [s Hs]. hnf.
    eapply typing_subst_instance_decl in Hs; eauto.
  - destruct t0 as [s Hs]. hnf.
    eapply typing_subst_instance_decl in Hs; eauto.
  - hnf in t1 |- *.
    eapply typing_subst_instance_decl in t1; eauto.
Qed.


End CheckerFlags.
