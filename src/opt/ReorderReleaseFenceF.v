Require Import Axioms.
Require Import Basics.
Require Import Bool.
Require Import List.

Require Import sflib.
Require Import paco.
Require Import respectful5.

Require Import Basic.
Require Import Event.
Require Import Language.
Require Import Time.
Require Import View.
Require Import Cell.
Require Import Memory.
Require Import TView.
Require Import Thread.
Require Import Configuration.
Require Import Progress.

Require Import SimMemory.
Require Import SimPromises.
Require Import SimLocal.
Require Import Compatibility.
Require Import Simulation.

Require Import ReorderStep.

Require Import Syntax.
Require Import Semantics.

Set Implicit Arguments.


Inductive reorder_release_fenceF: forall (i2:Instr.t), Prop :=
| reorder_release_fenceF_load
    r2 l2 o2:
    reorder_release_fenceF (Instr.load r2 l2 o2)
| reorder_release_fenceF_store
    l2 v2 o2
    (ORD2: Ordering.le o2 Ordering.unordered \/ Ordering.le Ordering.acqrel o2):
    reorder_release_fenceF (Instr.store l2 v2 o2)
| reorder_release_fenceF_update
    r2 l2 rmw2 or2 ow2
    (ORDW2: Ordering.le ow2 Ordering.unordered \/ Ordering.le Ordering.acqrel ow2):
    reorder_release_fenceF (Instr.update r2 l2 rmw2 or2 ow2)
| reorder_release_fenceF_fence:
    reorder_release_fenceF (Instr.fence Ordering.acqrel Ordering.relaxed)
.

Inductive sim_release_fenceF: forall (st_src:lang.(Language.state)) (lc_src:Local.t) (sc1_src:TimeMap.t) (mem1_src:Memory.t)
                        (st_tgt:lang.(Language.state)) (lc_tgt:Local.t) (sc1_tgt:TimeMap.t) (mem1_tgt:Memory.t), Prop :=
| sim_relese_fenceF_intro
    rs
    lc1_src sc1_src mem1_src
    lc1_tgt sc1_tgt mem1_tgt
    lc2_tgt sc2_tgt
    (FENCE: Local.fence_step lc1_tgt sc1_tgt Ordering.relaxed Ordering.acqrel lc2_tgt sc2_tgt)
    (LOCAL: sim_local lc1_src lc2_tgt):
    sim_release_fenceF
      (State.mk rs []) lc1_src sc1_src mem1_src
      (State.mk rs [Stmt.instr (Instr.fence Ordering.relaxed Ordering.acqrel)]) lc1_tgt sc1_tgt mem1_tgt
.

Lemma future_fence_step lc1 sc1 sc1' mem1 mem1' ordr ordw lc2 sc2
      (ORDW: Ordering.le ordw Ordering.acqrel)
      (SC_FUTURE: TimeMap.le sc1 sc1')
      (MEM_FUTURE: Memory.future mem1 mem1')
      (STEP: Local.fence_step lc1 sc1 ordr ordw lc2 sc2):
  Local.fence_step lc1 sc1' ordr ordw lc2 sc1'.
Proof.
  inv STEP.
  erewrite TViewFacts.write_fence_tview_acqrel; auto.
  erewrite <- TViewFacts.write_fence_sc_acqrel at 2; eauto.
  econs; auto.
Qed.

Lemma fence_step_fun
      lc1 sc1 ordr ordw lc2 sc2 lc2' sc2'
      (STEP: Local.fence_step lc1 sc1 ordr ordw lc2 sc2)
      (STEP': Local.fence_step lc1 sc1 ordr ordw lc2' sc2'):
  lc2 = lc2' /\ sc2 = sc2'.
Proof.
  inv STEP. inv STEP'. splits; auto.
Qed.

Lemma sim_release_fenceF_step
      st1_src lc1_src sc0_src mem0_src
      st1_tgt lc1_tgt sc0_tgt mem0_tgt
      (SIM: sim_release_fenceF st1_src lc1_src sc0_src mem0_src
                               st1_tgt lc1_tgt sc0_tgt mem0_tgt):
  forall sc1_src sc1_tgt
    mem1_src mem1_tgt
    (SC: TimeMap.le sc1_src sc1_tgt)
    (MEMORY: sim_memory mem1_src mem1_tgt)
    (SC_FUTURE_SRC: TimeMap.le sc0_src sc1_src)
    (SC_FUTURE_TGT: TimeMap.le sc0_tgt sc1_tgt)
    (MEM_FUTURE_SRC: Memory.future mem0_src mem1_src)
    (MEM_FUTURE_TGT: Memory.future mem0_tgt mem1_tgt)
    (WF_SRC: Local.wf lc1_src mem1_src)
    (WF_TGT: Local.wf lc1_tgt mem1_tgt)
    (SC_SRC: Memory.closed_timemap sc1_src mem1_src)
    (SC_TGT: Memory.closed_timemap sc1_tgt mem1_tgt)
    (MEM_SRC: Memory.closed mem1_src)
    (MEM_TGT: Memory.closed mem1_tgt),
    _sim_thread_step lang lang ((sim_thread (sim_terminal eq)) \8/ sim_release_fenceF)
                     st1_src lc1_src sc1_src mem1_src
                     st1_tgt lc1_tgt sc1_tgt mem1_tgt.
Proof.
  inv SIM; ii.
  exploit future_fence_step; try apply FENCE; eauto. i.
  inv STEP_TGT; inv STEP; try (inv STATE; inv INSTR; inv REORDER); ss.
  - (* promise *)
    inv FENCE. inv LOCAL0.
    exploit SimPromises.promise; eauto.
    { apply LOCAL. }
    { apply WF_SRC. }
    { apply WF_TGT. }
    i. des.
    exploit sim_memory_closed_view; eauto. i.
    exploit Memory.promise_future; try apply PROMISE_SRC; eauto.
    { apply WF_SRC. }
    i. des.
    esplits.
    + eauto.
    + econs 2. econs 1. econs. econs; eauto.
    + auto.
    + auto.
    + auto.
    + right. econs 1; eauto.
      * econs; eauto.
      * s. econs; eauto. s.
        inv LOCAL. ss.
  - (* fence *)
    inv STATE. inv INSTR.
    exploit fence_step_fun; [exact x0|exact LOCAL0|]. i. des. subst.
    esplits.
    + eauto.
    + econs 1.
    + auto.
    + auto.
    + auto.
    + left. eapply paco9_mon; [apply sim_stmts_nil|]; ss.
Qed.

Lemma sim_release_fenceF_sim_thread:
  sim_release_fenceF <8= (sim_thread (sim_terminal eq)).
Proof.
  pcofix CIH. i. pfold. ii. ss. splits; ss.
  - i. inv TERMINAL_TGT. inv PR; ss.
  - i. inv PR.
    exploit future_fence_step; try exact FENCE; eauto; try refl. i.
    exploit Local.fence_step_future; eauto. i. des.
    exploit Local.fence_step_future; eauto. i. des.
    exploit sim_local_future; try apply LOCAL; eauto. i. des.
    esplits.
    + etrans.
      { apply Memory.max_timemap_spec; eauto. viewtac. }
      { apply sim_memory_max_timemap; eauto. }
    + eauto.
    + etrans.
      { apply Memory.max_timemap_spec; eauto. viewtac. }
      { apply Memory.future_max_timemap; eauto. }
    + auto.
    + econs.
      { eapply WF_TGT. }
      { eapply TView.future_closed; eauto. apply WF_TGT. }
      { inv FENCE. apply WF2_TGT. }
    + apply Memory.max_timemap_closed. viewtac.
    + auto.
  - i. inv PR.
    esplits; eauto. inv FENCE.
    eapply sim_local_memory_bot; eauto.
  - ii. exploit sim_release_fenceF_step; try apply PR; try apply SC; eauto. i. des.
    + esplits; eauto.
      left. eapply paco9_mon; eauto. ss.
    + esplits; eauto.
Qed.

Lemma reorder_release_fenceF_sim_stmts
      i1 (REORDER: reorder_release_fenceF i1):
  sim_stmts eq
            [Stmt.instr (Instr.fence Ordering.relaxed Ordering.acqrel); Stmt.instr i1]
            [Stmt.instr i1; Stmt.instr (Instr.fence Ordering.relaxed Ordering.acqrel)]
            eq.
Proof.
  pcofix CIH. ii. subst. pfold. ii. splits; ii.
  { inv TERMINAL_TGT. }
  { exploit sim_local_future; try apply LOCAL; eauto. i. des.
    esplits; eauto.
    - etrans.
      + apply Memory.max_timemap_spec; eauto. viewtac.
      + apply sim_memory_max_timemap; eauto.
    - etrans.
      + apply Memory.max_timemap_spec; eauto. viewtac.
      + apply Memory.future_max_timemap; eauto.
    - apply Memory.max_timemap_closed. viewtac.
  }
  { esplits; eauto.
    inv LOCAL. apply SimPromises.sem_bot_inv in PROMISES; auto. rewrite PROMISES. auto.
  }
  inv STEP_TGT; inv STEP; try (inv STATE; inv INSTR; inv REORDER); ss.
  - (* promise *)
    exploit sim_local_promise; eauto. i. des.
    esplits; try apply SC; eauto.
    + econs 2. econs 1; eauto. econs; eauto.
    + auto.
  - (* load *)
    exploit Local.read_step_future; eauto. i. des.
    exploit progress_fence_step; eauto. i. des.
    exploit sim_local_read; eauto; try refl. i. des.
    exploit Local.read_step_future; eauto. i. des.
    exploit sim_local_fence; try exact SC; eauto; try refl. i. des.
    exploit reorder_read_fence; try exact STEP_SRC; eauto; try refl. i. des.
    esplits.
    + econs 2; eauto. econs.
      { econs 2. econs 5; eauto. econs. econs. }
      { auto. }
    + econs 2. econs 2. econs 2; eauto. econs. econs.
    + auto.
    + etrans; eauto. etrans; eauto.
      inv x0. unfold TView.write_fence_sc. condtac; ss. refl.
    + auto.
    + left. eapply paco9_mon; [apply sim_release_fenceF_sim_thread|]; ss.
      econs 1; eauto. etrans; eauto.
  - (* store *)
    guardH ORD2.
    exploit Local.write_step_future; eauto; try by viewtac. i. des.
    exploit progress_fence_step; eauto. i. des.
    hexploit sim_local_write; try exact LOCAL0; try exact LOCAL; try exact SC; try exact MEMORY;
      try refl; eauto; try by viewtac. i. des.
    exploit Local.write_step_future; eauto; try by viewtac. i. des.
    exploit sim_local_fence; try exact SC0; eauto; try refl. i. des.
    exploit reorder_write_fence; try exact STEP_SRC; eauto; try by viewtac. i. des.
    esplits.
    + econs 2; eauto. econs.
      * econs 2. econs 5; eauto. econs. econs.
      * auto.
    + econs 2. econs 2. econs 3; eauto. econs. econs.
    + auto.
    + etrans; eauto.
      inv x0. unfold TView.write_fence_sc. condtac; ss. refl.
    + auto.
    + left. eapply paco9_mon; [apply sim_release_fenceF_sim_thread|]; ss.
      econs 1; eauto. etrans; eauto.
  - (* update *)
    guardH ORDW2.
    exploit Local.read_step_future; eauto. i. des.
    exploit Local.write_step_future; eauto. i. des.
    exploit progress_fence_step; eauto. i. des.
    exploit sim_local_read; eauto; try refl. i. des.
    exploit Local.read_step_future; eauto. i. des.
    exploit reorder_write_fence; try exact LOCAL2; eauto. i. des.
    exploit Local.fence_step_future; eauto. i. des.
    exploit sim_local_fence; try exact SC; eauto; try refl. i. des.
    exploit reorder_read_fence; try exact STEP_SRC; eauto; try refl. i. des.
    exploit Local.fence_step_future; eauto. i. des.
    exploit Local.read_step_future; eauto. i. des.
    generalize LOCAL5. i. rewrite LOCAL4 in LOCAL6.
    generalize SC3. i. rewrite SC1 in SC5.
    hexploit sim_local_write; try exact STEP2; try exact LOCAL6; try exact SC5; eauto; try refl. i. des.
    esplits.
    + econs 2; eauto. econs.
      { econs 2. econs 5; eauto. econs. econs. }
      { auto. }
    + econs 2. econs 2. econs 4; eauto. econs. econs. eauto.
    + auto.
    + etrans; eauto.
      inv x0. unfold TView.write_fence_sc. condtac; ss. refl.
    + auto.
    + left. eapply paco9_mon; [apply sim_release_fenceF_sim_thread|]; ss.
      econs 1; eauto. etrans; eauto.
  - (* fence *)
    exploit Local.fence_step_future; eauto. i. des.
    exploit progress_fence_step; eauto. i. des.
    exploit sim_local_fence; try exact LOCAL0; try exact SC; eauto; try refl. i. des.
    exploit Local.fence_step_future; eauto. i. des.
    exploit sim_local_fence; try eexact x0; try exact SC0; eauto; try refl. i. des.
    exploit reorder_fence_fence; try exact STEP_SRC; eauto; try refl. i. des.
    esplits.
    + econs 2; eauto. econs.
      { econs 2. econs 5; eauto. econs. econs. }
      { auto. }
    + econs 2. econs 2. econs 5; eauto. econs. econs.
    + auto.
    + etrans; eauto. etrans; eauto.
      inv x0. unfold TView.write_fence_sc. condtac; ss. refl.
    + auto.
    + left. eapply paco9_mon; [apply sim_release_fenceF_sim_thread|]; ss.
      econs 1; eauto. etrans; eauto.
Qed.
