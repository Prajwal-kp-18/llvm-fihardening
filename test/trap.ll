; fi-harden-checks turns each fi.check(i1 %cond, i1 %expected) into an inline
; check: a branch that continues if %cond is %expected and goes to the
; function's one trap block otherwise.
; RUN: opt -load-pass-plugin=%fi_plugin -passes=fi-harden-checks,verify -S %s \
; RUN:   | FileCheck %s --implicit-check-not='call void @fi.check'
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden-checks<trap=call>,verify' -S %s \
; RUN:   | FileCheck %s --check-prefix=CALL

; Each check keeps its own compare and branch after llc -O2, and its branch
; reaches the trap. The copies are in the check's block: without them, Thumb-2
; if-converts the two checks into cmp; it eq; cmpeq; bne, one branch for both.
; RUN: opt -load-pass-plugin=%fi_plugin -passes=fi-harden-checks %s \
; RUN:   | llc -O2 -mtriple=aarch64-linux-gnu -o - | FileCheck %s --check-prefix=A64
; RUN: opt -load-pass-plugin=%fi_plugin -passes=fi-harden-checks %s \
; RUN:   | llc -O2 -mtriple=thumbv7m-none-eabi -o - | FileCheck %s --check-prefix=T2
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden-checks<trap=call>' %s \
; RUN:   | llc -O2 -mtriple=aarch64-linux-gnu -o - | FileCheck %s --check-prefix=A64-CALL
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden-checks<trap=call>' %s \
; RUN:   | llc -O2 -mtriple=thumbv7m-none-eabi -o - | FileCheck %s --check-prefix=T2-CALL

; The reference handler's two spin loops survive -O2.
; RUN: clang -O2 --target=aarch64-linux-gnu -S -o - %S/../runtime/fi_trap.c \
; RUN:   | FileCheck %s --check-prefix=SPIN
; RUN: clang -O2 --target=thumbv7m-none-eabi -S -o - %S/../runtime/fi_trap.c \
; RUN:   | FileCheck %s --check-prefix=SPIN
; SPIN-LABEL:  fi_trap:
; SPIN-COUNT-2:  Inner Loop Header

; CHECK-LABEL: @two(
; CHECK:         %eq = icmp eq i32 %a.copy, %b.copy
; CHECK-NEXT:    br i1 %eq, label %fi.ok, label %fi.trap
; CHECK:       fi.ok:
; CHECK:         %lt = icmp ult i32 %c.copy, %d.copy
; CHECK-NEXT:    br i1 %lt, label %fi.trap, label %fi.ok1
; CHECK:       fi.ok1:
; CHECK-NEXT:    ret i32 0
; CHECK:       fi.trap:
; CHECK-NEXT:    call void @llvm.trap()
; CHECK-NEXT:    unreachable
; CHECK-NEXT:  }

; CALL:        fi.trap:
; CALL-NEXT:     call void @fi_trap() #[[NOUNWIND:[0-9]+]]
; CALL-NEXT:     call void @llvm.trap()
; CALL-NEXT:     unreachable
; CALL:        attributes #[[NOUNWIND]] = { nounwind }

; A64-LABEL:   two:
; A64:           cmp w0, w1
; A64-NEXT:      b.ne [[TRAP:.LBB[0-9_]+]]
; A64:           cmp w2, w3
; A64-NEXT:      b.lo [[TRAP]]
; A64:         [[TRAP]]:
; A64-NEXT:      brk

; T2-LABEL:    two:
; T2:            cmp r0, r1
; T2-NEXT:       bne [[TRAP:.LBB[0-9_]+]]
; T2:            cmp r2, r3
; T2-NEXT:       itt hs
; T2:          [[TRAP]]:
; T2-NEXT:       .inst.n 0xdefe

; A64-CALL:    bl fi_trap
; A64-CALL-NEXT: brk
; T2-CALL:     bl fi_trap
; T2-CALL-NEXT:  .inst.n 0xdefe

define i32 @two(i32 %a, i32 %b, i32 %c, i32 %d) {
  %a.copy = call i32 asm sideeffect "", "=r,0"(i32 %a) #0
  %b.copy = call i32 asm sideeffect "", "=r,0"(i32 %b) #0
  %eq = icmp eq i32 %a.copy, %b.copy
  call void @fi.check(i1 %eq, i1 true)
  %c.copy = call i32 asm sideeffect "", "=r,0"(i32 %c) #0
  %d.copy = call i32 asm sideeffect "", "=r,0"(i32 %d) #0
  %lt = icmp ult i32 %c.copy, %d.copy
  call void @fi.check(i1 %lt, i1 false)
  ret i32 0
}

declare void @fi.check(i1, i1)

attributes #0 = { nounwind }
