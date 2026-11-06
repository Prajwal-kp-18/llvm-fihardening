; Only functions marked annotate("fi_harden") or named in the allowlist file
; are hardened. Declarations and the trap handler fi_trap never are, even when
; marked.
; RUN: opt -load-pass-plugin=%fi_plugin -passes=fi-harden -pass-remarks=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=MARKED --implicit-check-not=hardening
; MARKED: hardening marked:

; The allowlist adds to the annotations. Comment lines, blank lines and names
; missing from this module are ignored.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<allowlist=%S/Inputs/allowlist.txt>' \
; RUN:   -pass-remarks=fi-harden -disable-output %s 2>&1 \
; RUN:   | FileCheck %s --check-prefixes=MARKED,LISTED --implicit-check-not=hardening
; LISTED: hardening listed:

; all: every defined function except the trap handler.
; RUN: opt -load-pass-plugin=%fi_plugin -passes='fi-harden<all>' -pass-remarks=fi-harden \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=ALL --implicit-check-not=hardening
; ALL: hardening marked:
; ALL: hardening other_annotation:
; ALL: hardening listed:
; ALL: hardening plain:

; RUN: not opt -load-pass-plugin=%fi_plugin -passes='fi-harden<allowlist=%t.missing>' \
; RUN:   -disable-output %s 2>&1 | FileCheck %s --check-prefix=MISSING
; MISSING: fi-harden: cannot read allowlist '{{.*}}.missing'

; Unselected functions are left exactly as they were.
; RUN: opt -load-pass-plugin=%fi_plugin -passes=fi-harden -S %s | FileCheck %s
; CHECK-LABEL: define i32 @plain(
; CHECK-NEXT:    %c = icmp eq i32 %a, %b
; CHECK-NEXT:    br i1 %c, label %t, label %f
; CHECK:       t:
; CHECK-NEXT:    ret i32 1
; CHECK:       f:
; CHECK-NEXT:    ret i32 0
; CHECK-NEXT:  }

@.fi = private unnamed_addr constant [10 x i8] c"fi_harden\00", section "llvm.metadata"
@.other = private unnamed_addr constant [6 x i8] c"other\00", section "llvm.metadata"
@.file = private unnamed_addr constant [7 x i8] c"test.c\00", section "llvm.metadata"
@llvm.global.annotations = appending global [4 x { ptr, ptr, ptr, i32, ptr }] [
  { ptr, ptr, ptr, i32, ptr } { ptr @marked, ptr @.fi, ptr @.file, i32 1, ptr null },
  { ptr, ptr, ptr, i32, ptr } { ptr @other_annotation, ptr @.other, ptr @.file, i32 2, ptr null },
  { ptr, ptr, ptr, i32, ptr } { ptr @fi_trap, ptr @.fi, ptr @.file, i32 3, ptr null },
  { ptr, ptr, ptr, i32, ptr } { ptr @declared, ptr @.fi, ptr @.file, i32 4, ptr null }
], section "llvm.metadata"

define i32 @marked(i32 %a, i32 %b) {
  %c = icmp eq i32 %a, %b
  br i1 %c, label %t, label %f
t:
  ret i32 1
f:
  ret i32 0
}

define i32 @other_annotation(i32 %a, i32 %b) {
  %c = icmp eq i32 %a, %b
  br i1 %c, label %t, label %f
t:
  ret i32 1
f:
  ret i32 0
}

define i32 @listed(i32 %a, i32 %b) {
  %c = icmp eq i32 %a, %b
  br i1 %c, label %t, label %f
t:
  ret i32 1
f:
  ret i32 0
}

define i32 @plain(i32 %a, i32 %b) {
  %c = icmp eq i32 %a, %b
  br i1 %c, label %t, label %f
t:
  ret i32 1
f:
  ret i32 0
}

define void @fi_trap() {
  ret void
}

declare void @declared()
