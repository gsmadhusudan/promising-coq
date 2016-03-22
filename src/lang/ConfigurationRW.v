Require Import List.
Require Import Equalities.
Require Import PeanoNat.
Require Import Relations.
Require Import MSetList.
Require Import Omega.

Require Import sflib.
Require Import paco.

Require Import DataStructure.
Require Import Basic.
Require Import Event.
Require Import Thread.
Require Import UsualFMapPositive.

Set Implicit Arguments.
Import ListNotations.


(* TODO: how about using functor in defining structures with bot/le?
 *)
Module Timestamps.
  Definition t := LocFun.t positive.

  Definition bot: t := LocFun.init 1%positive.

  Definition le (lhs rhs:t): Prop :=
    forall loc, (LocFun.find loc lhs <= LocFun.find loc rhs)%positive.

  Definition get (loc:Loc.t) (c:t) :=
    LocFun.find loc c.
End Timestamps.


Module Capability.
  Structure t := mk {
    reads: Timestamps.t;
    writes: Timestamps.t;
  }.

  Definition bot: t := mk Timestamps.bot Timestamps.bot.

  Inductive le (lhs rhs:t): Prop :=
  | le_intro
      (READS: Timestamps.le lhs.(reads) rhs.(reads))
      (WRITES: Timestamps.le lhs.(writes) rhs.(writes))
  .
End Capability.


Module Message.
  Structure t := mk {
    val: Const.t;
    released: Capability.t;
    confirmed: bool;
  }.
End Message.


Module MessageSet.
  Definition t := LocFun.t (UsualPositiveMap.t Message.t).

  Definition init: t :=
    LocFun.init
      (UsualPositiveMap.add
         1%positive
         (Message.mk 0 Capability.bot true)
         (UsualPositiveMap.empty _)).

  Definition get (loc:Loc.t) (ts:positive) (m:t): option Message.t :=
    UsualPositiveMap.find ts (LocFun.find loc m).

  Inductive declare (loc:Loc.t) (ts:positive) (val:Const.t) (released:Capability.t) (m1:t): forall (m2:t), Prop :=
  | declare_intro
      (GET: get loc ts m1 = None):
      declare loc ts val released m1
              (LocFun.add loc (UsualPositiveMap.add ts (Message.mk val released false) (LocFun.find loc m1)) m1)
  .

  Inductive declared (m:t) (loc:Loc.t) (ts:positive): Prop :=
  | declared_intro
      val released
      (GET: MessageSet.get loc ts m = Some (Message.mk val released false))
  .

  Inductive confirmed (m:t): Prop :=
  | confirmed_intro
      (CONFIRM: forall loc ts, ~ declared m loc ts)
  .
End MessageSet.


Module Commit.
  Structure t := mk {
    current: Capability.t;
    released: LocFun.t Capability.t;
    acquirable: Capability.t;
  }.

  Definition bot: t :=
    mk Capability.bot (LocFun.init Capability.bot) Capability.bot.

  Inductive le (lhs rhs:t): Prop :=
  | le_intro
      (CURRENT: Capability.le lhs.(current) rhs.(current))
      (RELEASED: forall (loc:Loc.t), Capability.le (LocFun.find loc lhs.(released)) (LocFun.find loc rhs.(released)))
      (ACQUIRABLE: Capability.le lhs.(acquirable) rhs.(acquirable))
  .

  Inductive read
            (commit1:t) (m:MessageSet.t) (loc:Loc.t) (ts:positive) (ord:Ordering.t)
            (commit2:t) (val:Const.t) (released:Capability.t) (confirmed:bool): Prop :=
  | read_intro
      (COMMIT0: le commit1 commit2)
      (COMMIT1: (Timestamps.get loc commit1.(current).(Capability.reads) <= ts)%positive)
      (GET: MessageSet.get loc ts m = Some (Message.mk val released confirmed))
      (ACQUIRE: forall (ORDERING: Ordering.le Ordering.acquire ord),
          Capability.le released commit2.(current))
      (ACQUIRABLE: Capability.le released commit2.(acquirable)):
      read commit1 m loc ts ord
           commit2 val released confirmed
  .

  Inductive write
            (commit1:t) (m1:MessageSet.t) (loc:Loc.t) (ts:positive) (val:Const.t) (released:Capability.t) (ord:Ordering.t)
            (commit2:t): forall (m2:MessageSet.t), Prop :=
  | write_intro
      (DECLARE: MessageSet.get loc ts m1 = Some (Message.mk val released false))
      (COMMIT0: le commit1 commit2)
      (COMMIT1: (Timestamps.get loc commit1.(current).(Capability.writes) < ts)%positive)
      (COMMIT2: (ts <= Timestamps.get loc commit2.(current).(Capability.reads))%positive)
      (COMMIT3: (ts <= Timestamps.get loc commit2.(current).(Capability.writes))%positive)
      (RELEASE: forall (ORDERING: Ordering.le Ordering.release ord),
          Capability.le commit1.(current) (LocFun.find loc commit1.(Commit.released)))
      (RELEASED: Capability.le (LocFun.find loc commit1.(Commit.released)) released):
      write commit1 m1 loc ts val released ord
            commit2 (LocFun.add loc (UsualPositiveMap.add ts (Message.mk val released true) (LocFun.find loc m1)) m1)
  .

  Inductive fence
            (commit1:t) (ord:Ordering.t)
            (commit2:t): Prop :=
  | fence_intro
      (COMMIT: le commit1 commit2)
      (ACQUIRE: forall (ORDERING: Ordering.le Ordering.acquire ord),
          Capability.le commit2.(acquirable) commit2.(current))
      (RELEASE: forall (ORDERING: Ordering.le Ordering.release ord) loc,
          Capability.le commit2.(current) (LocFun.find loc commit2.(released)))
  .

  Inductive step (commit1:t) (m1:MessageSet.t): forall (reading:option (Loc.t * positive)) (e:MemEvent.t) (commit2:t) (m2:MessageSet.t), Prop :=
  | step_read
      loc ts ord val released confirmed commit2
      (READ: read commit1 m1 loc ts ord commit2 val released confirmed):
      step commit1 m1
           (Some (loc, ts)) (MemEvent.read loc val ord)
           commit2 m1
  | step_write
      loc ts val released ord commit2 m2
      (WRITE: write commit1 m1 loc ts val released ord commit2 m2):
      step commit1 m1
           None (MemEvent.write loc val ord)
           commit2 m2
  | step_update
      loc ts ord valr releasedr confirmedr valw releasedw commiti commit2 m2
      (READ: read commit1 m1 loc ts ord commiti valr releasedr confirmedr)
      (WRITE: write commiti m1 loc (ts + 1) valw releasedw ord commit2 m2)
      (RELEASE: Capability.le releasedr releasedw):
      step commit1 m1
           (Some (loc, ts)) (MemEvent.update loc valr valw ord)
           commit2 m2
  | step_fence
      ord commit2
      (FENCE: Commit.fence commit1 ord commit2):
      step commit1 m1
           None (MemEvent.fence ord)
           commit2 m1
  .
End Commit.


Module Configuration.
  Definition syntax := IdentMap.t Thread.syntax.

  Structure t := mk {
    messages: MessageSet.t;
    threads: IdentMap.t (Commit.t * Thread.t);
  }.

  Definition init (s:syntax): t :=
    mk MessageSet.init (IdentMap.map (fun th => (Commit.bot, Thread.init th)) s).

  Inductive is_terminal (c:t): Prop :=
  | is_terminal_intro
      (TERMINAL:
         forall tid commit th (FIND: IdentMap.find tid c.(threads) = Some (commit, th)),
           Thread.is_terminal th)
  .

  (* TODO: to check the liveness, the step should be annotated with the thread id.
   *)
  Inductive base_step (c1:t): forall (tid:option Ident.t) (validation:option (Loc.t * positive)) (c2:t), Prop :=
  | step_tau
      tid commit1 commit2 th1 th2
      (COMMIT: Commit.le commit1 commit2)
      (TID: IdentMap.find tid c1.(threads) = Some (commit1, th1))
      (THREAD: Thread.step th1 None th2):
      base_step
        c1 (Some tid) None
        (mk c1.(messages) (IdentMap.add tid (commit2, th2) c1.(threads)))
  | step_mem
      tid commit1 commit2 th1 th2 messages2 reading e
      (TID: IdentMap.find tid c1.(threads) = Some (commit1, th1))
      (MEM: Commit.step commit1 c1.(messages) reading e commit2 messages2)
      (THREAD: Thread.step th1 (Some (ThreadEvent.mem e)) th2):
      base_step
        c1 (Some tid) reading
        (mk messages2 (IdentMap.add tid (commit2, th2) c1.(threads)))
  | step_declare
      loc ts val released messages2
      (DECLARE: MessageSet.declare loc ts val released c1.(messages) messages2):
      base_step
        c1 None None
        (mk messages2 c1.(threads))
  .

  Inductive internal_step: forall (c1 c2:t), Prop :=
  | step_confirmed
      c1 c2 tid
      (STEP: base_step c1 tid None c2):
      internal_step c1 c2
  | step_unconfirmed
      c1 c2 tid loc ts
      commit1 commit1' th1
      (STEP: base_step c1 (Some tid) (Some (loc, ts)) c2)
      (THREAD1: IdentMap.find tid c1.(threads) = Some (commit1, th1))
      (COMMIT0: Commit.le commit1 commit1')
      (COMMIT1: (ts <= commit1'.(Commit.current).(Capability.writes).(Timestamps.get loc))%positive)
      (VALID: valid loc ts (mk c1.(messages) (IdentMap.add tid (commit1', th1) c1.(threads)))):
      internal_step c1 c2
  with valid: forall (loc:Loc.t) (ts:positive) (c1:t), Prop :=
  | valid_intro
      c1 c2 loc ts
      (STEPS: rtc internal_step c1 c2)
      (DECLARE: MessageSet.declared c2.(messages) <2= MessageSet.declared c1.(messages))
      (NODECLARE: ~ MessageSet.declared c2.(messages) loc ts):
      valid loc ts c1
  .

  Inductive consistent: forall (c1:t), Prop :=
  | consistent_intro
      c1 c2
      (STEPS: rtc internal_step c1 c2)
      (CONFIRM: MessageSet.confirmed c2.(messages)):
      consistent c1
  .

  Lemma internal_steps_consistent c1 c2
        (STEPS: rtc internal_step c1 c2)
        (CONSISTENT: consistent c2):
    consistent c1.
  Proof.
    inv CONSISTENT. econs; [|eauto].
    eapply rtc_trans; eauto.
  Qed.

  Lemma init_consistent s: consistent (init s).
  Proof.
    econs.
    - econs 1.
    - unfold init. simpl. econs. i. intro X. inv X.
      unfold MessageSet.get, MessageSet.init in *.
      rewrite LocFun.init_spec in *.
      rewrite IdentMap.Facts.add_o in *.
      match goal with
      | [H: context[if ?cond then _ else _] |- _] =>
        destruct cond; inv H
      end.
      rewrite IdentMap.Facts.empty_o in *. inv H0.
  Qed.

  Inductive external_step (c1:t): forall (e:Event.t) (c2:t), Prop :=
  | step_syscall
      tid commit th1 th2
      e
      (TID: IdentMap.find tid c1.(threads) = Some (commit, th1))
      (THREAD: Thread.step th1 (Some (ThreadEvent.syscall e)) th2):
      external_step
        c1 e
        (mk c1.(messages) (IdentMap.add tid (commit, th2) c1.(threads)))
  .

  Inductive step: forall (c1:t) (e:option Event.t) (c2:t), Prop :=
  | step_internal
      c1 c2
      (STEP: internal_step c1 c2)
      (CONSISTENT: consistent c2):
      step c1 None c2
  | step_external
      c1 c2
      e
      (STEP: external_step c1 e c2)
      (CONSISTENT: consistent c2):
      step c1 (Some e) c2
  .
End Configuration.