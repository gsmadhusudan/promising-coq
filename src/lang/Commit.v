Require Import Omega.
Require Import RelationClasses.

Require Import sflib.
Require Import paco.

Require Import Axioms.
Require Import Basic.
Require Import DataStructure.
Require Import Event.
Require Import Time.
Require Import Language.
Require Import Memory.

Set Implicit Arguments.


Module Commit <: JoinableType.
  Structure t_ := mk {
    current: Snapshot.t;
    released: LocFun.t Snapshot.t;
    acquirable: Snapshot.t;
  }.
  Definition t := t_.

  Definition init: t := mk Snapshot.init (LocFun.init Snapshot.init) Snapshot.init.

  Inductive wf (commit:t) (mem:Memory.t): Prop :=
  | wf_intro
      (CURRENT: Memory.wf_snapshot commit.(current) mem)
      (RELEASED: forall loc, Memory.wf_snapshot (commit.(released) loc) mem)
      (ACQUIRABLE: Memory.wf_snapshot commit.(acquirable) mem)
  .

  Lemma future_wf
        commit mem1 mem2
        (WF: wf commit mem1)
        (FUTURE: Memory.future mem1 mem2):
    wf commit mem2.
  Proof.
    inv WF. econs; i; eapply Memory.future_wf_snapshot; eauto.
  Qed.

  Definition eq := @eq t.

  Inductive le_ (lhs rhs:t): Prop :=
  | le_intro
      (CURRENT: Snapshot.le lhs.(current) rhs.(current))
      (RELEASED: forall (loc:Loc.t), Snapshot.le (LocFun.find loc lhs.(released)) (LocFun.find loc rhs.(released)))
      (ACQUIRABLE: Snapshot.le lhs.(acquirable) rhs.(acquirable))
  .
  Definition le := le_.

  Global Program Instance le_PreOrder: PreOrder le.
  Next Obligation.
    ii. econs; reflexivity.
  Qed.
  Next Obligation.
    ii. inv H. inv H0. econs; etransitivity; eauto.
  Qed.

  Definition join (lhs rhs:t): t :=
    mk (Snapshot.join lhs.(current) rhs.(current))
       (fun loc => Snapshot.join (lhs.(released) loc) (rhs.(released) loc))
       (Snapshot.join lhs.(acquirable) rhs.(acquirable)).

  Lemma join_comm lhs rhs: join lhs rhs = join rhs lhs.
  Proof.
    unfold join. f_equal.
    - apply Snapshot.join_comm.
    - extensionality loc. apply Snapshot.join_comm.
    - apply Snapshot.join_comm.
  Qed.

  Lemma join_assoc a b c: join (join a b) c = join a (join b c).
  Proof.
    unfold join. s. f_equal.
    - apply Snapshot.join_assoc.
    - extensionality loc. apply Snapshot.join_assoc.
    - apply Snapshot.join_assoc.
  Qed.

  Lemma join_l lhs rhs: le lhs (join lhs rhs).
  Proof.
    econs.
    - apply Snapshot.join_l.
    - i. apply Snapshot.join_l.
    - apply Snapshot.join_l.
  Qed.

  Lemma join_r lhs rhs: le rhs (join lhs rhs).
  Proof.
    econs.
    - apply Snapshot.join_r.
    - i. apply Snapshot.join_r.
    - apply Snapshot.join_r.
  Qed.

  Lemma join_spec lhs rhs o
        (LHS: le lhs o)
        (RHS: le rhs o):
    le (join lhs rhs) o.
  Proof.
    inv LHS. inv RHS. econs.
    - apply Snapshot.join_spec; eauto.
    - i. apply Snapshot.join_spec; eauto.
    - apply Snapshot.join_spec; eauto.
  Qed.

  Inductive read
            (commit1:t) (loc:Loc.t) (ts:Time.t) (released:Snapshot.t) (ord:Ordering.t)
            (commit2:t): Prop :=
  | read_intro
      (MONOTONE: le commit1 commit2)
      (READABLE: Snapshot.readable commit1.(current) loc ts)
      (READ: Time.le ts (Times.get loc commit2.(current).(Snapshot.reads)))
      (ACQUIRE: forall (ORDERING: Ordering.le Ordering.acquire ord),
          Snapshot.le released commit2.(current))
      (ACQUIRABLE: Snapshot.le released commit2.(acquirable))
  .

  Inductive write
            (commit1:t) (loc:Loc.t) (ts:Time.t) (released:Snapshot.t) (ord:Ordering.t)
            (commit2:t): Prop :=
  | write_intro
      (MONOTONE: le commit1 commit2)
      (WRITABLE: Snapshot.writable commit1.(current) loc ts)
      (WRITE: Time.le ts (Times.get loc commit2.(current).(Snapshot.writes)))
      (RELEASED0: Ordering.le Ordering.release ord ->
                  Snapshot.le (Snapshot.incr_writes loc ts commit1.(current)) released)
      (RELEASED1: Snapshot.le (LocFun.find loc commit1.(Commit.released)) released)
      (RELEASED2: Snapshot.le released (LocFun.find loc commit2.(Commit.released)))
  .

  Inductive fence
            (commit1:t) (ord:Ordering.t)
            (commit2:t): Prop :=
  | fence_intro
      (MONOTONE: le commit1 commit2)
      (ACQUIRE: forall (ORDERING: Ordering.le Ordering.acquire ord),
          Snapshot.le commit1.(acquirable) commit2.(current))
      (RELEASE: forall (ORDERING: Ordering.le Ordering.release ord) loc,
          Snapshot.le commit1.(current) (LocFun.find loc commit2.(released)))
  .
End Commit.

Module CommitFacts.
  Lemma le_join_if2
        (cond:bool) a b c
        (B: cond -> Snapshot.le a b)
        (C: ~cond -> Snapshot.le a c):
    Snapshot.le a (if cond then b else c).
  Proof.
    destruct cond; auto.
  Qed.

  Ltac tac :=
    repeat
      (try match goal with
           | [|- Snapshot.le (Snapshot.join _ _) _] =>
             apply Snapshot.join_spec
           | [|- Snapshot.le (Snapshot.incr_reads _ _ _) _] =>
             apply Snapshot.incr_reads_spec
           | [|- Snapshot.le (Snapshot.incr_writes _ _ _) _] =>
             apply Snapshot.incr_writes_spec

           | [|- Snapshot.le ?s (Snapshot.incr_reads _ _ ?s)] =>
             apply Snapshot.incr_reads_le
           | [|- Snapshot.le ?s (Snapshot.incr_writes _ _ ?s)] =>
             apply Snapshot.incr_writes_le

           | [|- Snapshot.le ?s (Snapshot.join _ ?s)] =>
             apply Snapshot.join_r
           | [|- Snapshot.le ?s (Snapshot.join ?s _)] =>
             apply Snapshot.join_l

           | [|- Snapshot.le (if _ then Snapshot.join ?a ?b else ?b) _] =>
             apply Snapshot.le_join_if
           | [|- Snapshot.le _ (if _ then _ else _)] =>
             apply le_join_if2
           end; subst; ss; i).

  Ltac condtac :=
    match goal with
    | [|- context[if ?c then _ else _]] =>
      destruct c
    end.

  Lemma wf_get
        loc commit1 mem
        (WF1: Commit.wf commit1 mem):
    exists msg, Memory.get loc (Snapshot.writes (Commit.current commit1) loc) mem = Some msg.
  Proof.
    inversion WF1. inv CURRENT. inv WRITES.
    specialize (WF loc). des. destruct msg. eauto.
  Qed.

  Lemma read_mon1
        commit1 commit2
        (LE: Commit.le commit1 commit2):
    Commit.read commit2 <5= Commit.read commit1.
  Proof.
    i. inv PR. econs; auto.
    - rewrite LE. auto.
    - eapply Snapshot.readable_mon; eauto. apply LE.
  Qed.

  Lemma write_mon1
        commit1 commit2
        (LE: Commit.le commit1 commit2):
    Commit.write commit2 <5= Commit.write commit1.
  Proof.
    i. inv PR. econs; auto.
    - rewrite LE. auto.
    - eapply Snapshot.writable_mon; eauto. apply LE.
    - i. rewrite <- RELEASED0; auto. apply Snapshot.incr_writes_mon. apply LE.
    - etransitivity; eauto. apply LE.
  Qed.

  Lemma fence_mon1
        commit1 commit2
        (LE: Commit.le commit1 commit2):
    Commit.fence commit2 <2= Commit.fence commit1.
  Proof.
    i. inv PR. econs; auto.
    - rewrite LE. auto.
    - i. etransitivity; [apply LE|]. apply ACQUIRE. auto.
    - i. etransitivity; [apply LE|]. apply RELEASE. auto.
  Qed.

  Lemma read_mon2
        loc ts released ord
        commit1 commit2 commit3
        (READ: Commit.read commit1 loc ts released ord commit2)
        (LE: Commit.le commit2 commit3):
    Commit.read commit1 loc ts released ord commit3.
  Proof.
    inv READ. econs; eauto.
    - rewrite MONOTONE. auto.
    - rewrite READ0. apply LE.
    - i. rewrite ACQUIRE; auto. apply LE.
    - rewrite ACQUIRABLE. apply LE.
  Qed.

  Lemma write_mon2
        loc ts released ord
        commit1 commit2 commit3
        (WRITE: Commit.write commit1 loc ts released ord commit2)
        (LE: Commit.le commit2 commit3):
    Commit.write commit1 loc ts released ord commit3.
  Proof.
    inv WRITE. econs; auto.
    - rewrite MONOTONE. auto.
    - rewrite WRITE0. apply LE.
    - rewrite RELEASED2. apply LE.
  Qed.

  Lemma fence_mon2
        ord
        commit1 commit2 commit3
        (FENCE: Commit.fence commit1 ord commit2)
        (LE: Commit.le commit2 commit3):
    Commit.fence commit1 ord commit3.
  Proof.
    inv FENCE. econs; auto.
    - rewrite MONOTONE. auto.
    - i. rewrite ACQUIRE; auto. apply LE.
    - i. rewrite RELEASE; auto. apply LE.
  Qed.

  Definition read_min
             loc ts released ord commit: Commit.t :=
    (Commit.mk (if Ordering.le Ordering.acquire ord
                then Snapshot.join
                       released
                       (Snapshot.incr_reads loc ts commit.(Commit.current))
                else Snapshot.incr_reads loc ts commit.(Commit.current))
               commit.(Commit.released)
               (Snapshot.join released commit.(Commit.acquirable))).

  Lemma read_min_spec
        loc ts val released ord commit mem
        (READABLE: Snapshot.readable (Commit.current commit) loc ts)
        (MEMORY: Memory.wf mem)
        (WF1: Commit.wf commit mem)
        (WF2: Memory.get loc ts mem = Some (Message.mk val released)):
    <<READ: Commit.read commit loc ts released ord (read_min loc ts released ord commit)>> /\
    <<WF: Commit.wf (read_min loc ts released ord commit) mem>> /\
    <<CURRENT: Ordering.le ord Ordering.release -> forall loc' (LOC: loc' <> loc), Snapshot.le_on loc' (read_min loc ts released ord commit).(Commit.current) commit.(Commit.current)>>.
  Proof.
    unfold read_min. splits.
    - econs; eauto.
      + econs; try reflexivity; tac.
        etransitivity; [|apply Snapshot.join_r]. tac.
      + destruct (Ordering.le Ordering.acquire ord); s.
        * etransitivity; [|apply Times.join_r].
          apply Times.incr_ts.
        * apply Times.incr_ts.
      + tac.
      + tac.
    - econs.
      + destruct (Ordering.le Ordering.acquire ord); s.
        * apply Memory.wf_snapshot_join.
          { inv MEMORY. exploit WF; eauto. }
          { eapply Memory.wf_incr_reads; eauto. apply WF1. }
        * eapply Memory.wf_incr_reads; eauto. apply WF1.
      + s. apply WF1.
      + s. apply Memory.wf_snapshot_join.
        { inv MEMORY. exploit WF; eauto. }
        { apply WF1. }
    - destruct (Ordering.le Ordering.acquire ord) eqn:ORD.
      { destruct ord; ss. }
      s. econs; s; [|reflexivity].
      unfold Times.incr, LocFun.add, LocFun.find.
      destruct (Loc.eq_dec loc' loc); [congruence|].
      reflexivity.
  Qed.

  Lemma read_min_min
        loc ts released ord commit1 commit2
        (COMMIT2: Commit.read commit1 loc ts released ord commit2):
    Commit.le (read_min loc ts released ord commit1) commit2.
  Proof.
    inv COMMIT2. unfold read_min. econs.
    - destruct (Ordering.le Ordering.acquire ord); s.
      + apply Snapshot.join_spec; auto.
        apply Snapshot.incr_reads_spec; auto.
        apply MONOTONE.
      + apply Snapshot.incr_reads_spec; auto.
        apply MONOTONE.
    - apply MONOTONE.
    - apply Snapshot.join_spec; auto.
      apply MONOTONE.
  Qed.

  Definition write_min
             loc ts released commit: Commit.t :=
    (Commit.mk (Snapshot.incr_writes loc ts commit.(Commit.current))
               (LocFun.add loc released commit.(Commit.released))
               commit.(Commit.acquirable)).

  Lemma write_min_spec
        loc ts val released ord commit mem
        (WRITABLE: Snapshot.writable (Commit.current commit) loc ts)
        (RELEASED1: Snapshot.le (commit.(Commit.released) loc) released)
        (RELEASED2: Ordering.le Ordering.release ord -> Snapshot.le (Snapshot.incr_writes loc ts commit.(Commit.current)) released)
        (MEMORY: Memory.wf mem)
        (WF1: Commit.wf commit mem)
        (WF2: Memory.get loc ts mem = Some (Message.mk val released))
        (WF3: Memory.wf_snapshot released mem):
    <<WRITE: Commit.write commit loc ts released ord (write_min loc ts released commit)>> /\
    <<WF: Commit.wf (write_min loc ts released commit) mem>> /\
    <<CURRENT: forall loc' (LOC: loc' <> loc),
        Snapshot.le_on loc' (write_min loc ts released commit).(Commit.current) commit.(Commit.current)>> /\
    <<RELEASED1: forall loc' (LOC: loc' <> loc),
        Snapshot.le ((write_min loc ts released commit).(Commit.released) loc') (commit.(Commit.released) loc')>>.
  Proof.
    splits.
    - inv WRITABLE. econs; ss.
      + econs; s; try reflexivity.
        * econs; s; try reflexivity.
          apply Times.incr_le.
        * i. unfold LocFun.add, LocFun.find.
          condtac; tac. reflexivity.
      + apply Times.incr_ts.
      + unfold LocFun.add, LocFun.find.
        condtac; [|congruence]. reflexivity.
    - econs; ss.
      + econs; ss.
        * apply WF1.
        * eapply Memory.incr_wf_times; eauto. apply WF1.
      + i. unfold LocFun.add, LocFun.find.
        condtac; tac. apply WF1.
      + apply WF1.
    - i. econs; s; [reflexivity|].
      unfold Times.incr, LocFun.add, LocFun.find.
      condtac; [congruence|]. reflexivity.
    - ss. i. unfold LocFun.add, LocFun.find.
      condtac; ss. reflexivity.
  Qed.

  Lemma write_min_min
        loc ts released ord commit1 commit2
        (COMMIT2: Commit.write commit1 loc ts released ord commit2):
    Commit.le (write_min loc ts released commit1) commit2.
  Proof.
    i. inv COMMIT2. econs; s.
    - apply Snapshot.incr_writes_spec; ss.
      apply MONOTONE.
    - ss. i. unfold LocFun.add, LocFun.find. condtac; tac.
      apply MONOTONE.
    - apply MONOTONE.
  Qed.

  Definition fence_min
             ord commit: Commit.t :=
    (Commit.mk (if Ordering.le Ordering.acquire ord
                then Snapshot.join commit.(Commit.acquirable) commit.(Commit.current)
                else commit.(Commit.current))
               (fun loc =>
                  if Ordering.le Ordering.release ord
                  then Snapshot.join commit.(Commit.current) (commit.(Commit.released) loc)
                  else commit.(Commit.released) loc)
               commit.(Commit.acquirable)).

  Lemma fence_min_spec
        ord commit mem
        (MEMORY: Memory.wf mem)
        (WF1: Commit.wf commit mem):
    <<FENCE: Commit.fence commit ord (fence_min ord commit)>> /\
    <<WF: Commit.wf (fence_min ord commit) mem>>.
  Proof.
    unfold fence_min. splits.
    - econs; tac.
      + econs; tac.
        * reflexivity.
        * unfold LocFun.find. condtac; tac. reflexivity.
        * reflexivity.
      + unfold LocFun.find. condtac; tac.
    - econs; tac; try apply WF1.
      + condtac; try apply WF1.
        apply Memory.wf_snapshot_join; apply WF1.
      + condtac; try apply WF1.
        apply Memory.wf_snapshot_join; apply WF1.
  Qed.  

  Lemma fence_min_min
        ord commit1 commit2
        (COMMIT2: Commit.fence commit1 ord commit2):
    Commit.le (fence_min ord commit1) commit2.
  Proof.
    inv COMMIT2. unfold fence_min. econs; tac.
    - apply MONOTONE.
    - unfold LocFun.find. condtac; tac; eauto.
      + apply MONOTONE.
      + apply MONOTONE.
    - apply MONOTONE.
  Qed.
End CommitFacts.

Ltac committac := CommitFacts.tac.
