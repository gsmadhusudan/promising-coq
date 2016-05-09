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
Require Import Memory.
Require Import Commit.
Require Import Thread.

Require Import Configuration.
Require Import Simulation.
Require Import Compatibility.
Require Import MemInv.
Require Import Progress.
Require Import ReorderBase.

Require Import Syntax.
Require Import Semantics.

Set Implicit Arguments.


Inductive reorder_store l1 v1 o1: forall (i2:Instr.t), Prop :=
| reorder_store_load
    r2 l2 o2
    (ORD1: Ordering.le o1 Ordering.relaxed)
    (ORD2: Ordering.le o2 Ordering.relaxed)
    (LOC: l1 <> l2)
    (REGS: RegSet.disjoint (Instr.regs_of (Instr.store l1 v1 o1))
                           (Instr.regs_of (Instr.load r2 l2 o2))):
    reorder_store l1 v1 o1 (Instr.load r2 l2 o2)
| reorder_store_store
    l2 v2 o2
    (ORD1: Ordering.le o1 Ordering.relaxed)
    (LOC: l1 <> l2)
    (REGS: RegSet.disjoint (Instr.regs_of (Instr.store l1 v1 o1))
                           (Instr.regs_of (Instr.store l2 v2 o2))):
    reorder_store l1 v1 o1 (Instr.store l2 v2 o2)
| reorder_store_update
    r2 l2 rmw2 or2 ow2
    (ORD1: Ordering.le o1 Ordering.relaxed)
    (ORDR2: Ordering.le or2 Ordering.relaxed)
    (LOC: l1 <> l2)
    (REGS: RegSet.disjoint (Instr.regs_of (Instr.store l1 v1 o1))
                           (Instr.regs_of (Instr.update r2 l2 rmw2 or2 ow2))):
    reorder_store l1 v1 o1 (Instr.update r2 l2 rmw2 or2 ow2)
.

Inductive sim_store: forall (st_src:lang.(Language.state)) (th_src:Local.t) (mem_k_src:Memory.t)
                       (st_tgt:lang.(Language.state)) (th_tgt:Local.t) (mem_k_tgt:Memory.t), Prop :=
| sim_store_intro
    l1 f1 t1 v1 released1 o1 i2
    rs th1_src th1_tgt th2_src
    mem_k_src mem_k_tgt
    (REORDER: reorder_store l1 v1 o1 i2)
    (FULFILL: Local.fulfill_step th1_src mem_k_src l1 f1 t1 (RegFile.eval_value rs v1) released1 o1 th2_src)
    (LOCAL: sim_local th2_src th1_tgt):
    sim_store
      (State.mk rs [Stmt.instr i2; Stmt.instr (Instr.store l1 v1 o1)]) th1_src mem_k_src
      (State.mk rs [Stmt.instr i2]) th1_tgt mem_k_tgt
.

Lemma sim_store_step
      st1_src th1_src mem_k_src
      st1_tgt th1_tgt mem_k_tgt
      (SIM: sim_store st1_src th1_src mem_k_src
                      st1_tgt th1_tgt mem_k_tgt):
  forall mem1_src mem1_tgt
    (MEMORY: sim_memory mem1_src mem1_tgt)
    (FUTURE_SRC: Memory.future mem_k_src mem1_src)
    (FUTURE_TGT: Memory.future mem_k_tgt mem1_tgt)
    (WF_SRC: Local.wf th1_src mem1_src)
    (WF_TGT: Local.wf th1_tgt mem1_tgt),
    _sim_thread_step lang lang ((sim_thread (sim_terminal eq)) \6/ sim_store)
                     st1_src th1_src mem1_src
                     st1_tgt th1_tgt mem1_tgt.
Proof.
  inv SIM. ii.
  exploit Local.future_fulfill_step; try apply FULFILL; eauto. i.
  inv STEP_TGT; inv STEP; try (inv STATE; inv INSTR; inv REORDER).
  - (* promise *)
    exploit sim_local_promise; eauto.
    { eapply Local.fulfill_step_future; eauto. }
    i. des.
    exploit reorder_fulfill_promise; try apply x0; try apply STEP_SRC; eauto. i. des.
    eexists _, _, _, _, _, _. splits; eauto.
    + econs 1. econs; eauto.
    + right. econs; eauto.
  - (* load *)
    exploit sim_local_read; eauto.
    { eapply Local.fulfill_step_future; eauto. }
    i. des.
    exploit reorder_fulfill_read; try apply x0; try apply STEP_SRC; eauto. i. des.
    eexists _, _, _, _, _, _. splits.
    + econs 2; [|econs 1]. econs 2. econs 2; eauto. econs. econs.
    + econs 2. econs 3; eauto. econs.
      * econs.
      * s. econs 1. erewrite RegFile.eq_except_value; eauto.
        { admit. (* RegSet.disjoint symmetry *) }
        { apply RegFile.eq_except_singleton. }
        { i. rewrite ORD1 in H. inv H. }
    + eauto.
    + left. eapply paco7_mon; [apply sim_stmts_nil|]; ss.
  - (* store *)
    exploit sim_local_write; eauto.
    { eapply Local.fulfill_step_future; eauto. }
    i. des.
    exploit reorder_fulfill_write; try apply x0; try apply STEP_SRC; eauto.
    i. des.
    eexists _, _, _, _, _, _. splits.
    + econs 2; [|econs 1]. econs 2. econs 3; eauto. econs. econs.
    + econs 2. econs 3; eauto. econs.
      * econs.
      * s. econs 1; eauto.
        i. rewrite ORD1 in H. inv H.
    + s. eauto.
    + s. left. eapply paco7_mon; [apply sim_stmts_nil|]; ss.
  - (* update *)
    exploit sim_local_read; eauto.
    { eapply Local.fulfill_step_future; eauto. }
    i. des.
    exploit sim_local_write; eauto.
    { eapply Local.read_step_future; eauto.
      eapply Local.fulfill_step_future; eauto.
    }
    { eapply Local.read_step_future; eauto. }
    i. des.
    exploit reorder_fulfill_read; try apply x0; try apply STEP_SRC; eauto. i. des.
    exploit reorder_fulfill_write; try apply STEP2; try apply STEP_SRC0; eauto.
    { eapply Local.read_step_future; eauto. }
    i. des.
    eexists _, _, _, _, _, _. splits.
    + econs 2; [|econs 1]. econs 2. econs 4; eauto. econs. econs. eauto.
    + econs 2. econs 3; eauto.
      * econs. econs.
      * s. econs 1. erewrite RegFile.eq_except_value; eauto.
        { admit. (* RegSet.disjoint symmetry *) }
        { apply RegFile.eq_except_singleton. }
        { i. rewrite ORD1 in H. inv H. }
    +  s. eauto.
    + s. left. eapply paco7_mon; [apply sim_stmts_nil|]; ss.
Admitted.

Lemma sim_store_sim_thread:
  sim_store <6= (sim_thread (sim_terminal eq)).
Proof.
  pcofix CIH. i. pfold. ii. ss. splits; ss.
  - i. inv TERMINAL_TGT. inv PR; ss.
  - i. inv PR. eapply sim_local_future; try apply LOCAL; eauto.
    + eapply Local.fulfill_step_future; eauto.
      eapply Local.future_fulfill_step; eauto.
    + eapply Local.fulfill_step_future; eauto.
      eapply Local.future_fulfill_step; eauto.
      eapply Local.future_fulfill_step; eauto.
  - inversion PR. subst. i.
    exploit (progress_step rs i2 nil); eauto.
    i. des; [|by inv STEP; inv STATE; inv INSTR; inv REORDER].
    destruct th2. exploit sim_store_step; eauto.
    { econs 2. eauto. }
    i. des.
    + exploit internal_step_promise; eauto. i.
      punfold SIM. exploit SIM; eauto; try reflexivity.
      { exploit Thread.rtc_step_future; eauto. s. i. des.
        exploit Thread.step_future; eauto. s. i. des. auto.
      }
      { exploit Thread.internal_step_future; eauto. s. i. des. auto. }
      i. des. exploit PROMISE; eauto. i. des.
      eexists _, _, _. splits; [|eauto].
      etransitivity; eauto.
      etransitivity; [econs 2; eauto|].
      etransitivity; eauto.
    + inv SIM. inv STEP; inv STATE.
  - ii. exploit sim_store_step; eauto. i. des.
    + eexists _, _, _, _, _, _. splits; eauto.
      left. eapply paco7_mon; eauto. ss.
    + eexists _, _, _, _, _, _. splits; eauto.
Qed.
