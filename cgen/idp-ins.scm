; IDA Processor Module support
; By Yifan Lu
; Parts taken from other CGEN files

; Finds operands that are marked as 'in-ops' by analysis to be CF_USE

(define (-use-flags-for-insn insn)
  (let ((vals (map (lambda (ifld) (ifld-get-value ifld)) (insn-iflds insn)))
    (inops (sfmt-in-ops (insn-sfmt insn))))
    (string-list-map (lambda (opc)
        (let ((order (insn-op-order insn (op:sem-name opc))))
          (logit 3 "in-op " (number->string order) ": " (op:sem-name opc) "\n")
          (if (>= order 0)
            (string-append "CF_USE" (number->string (+ order 1)))
            ""
          )
        )
      )
      (filter (lambda (val) 
        (not (null? (find (lambda (op)
          (and (operand? val) (equal? (op:sem-name val) (op:sem-name op))))
          inops
        ))))
        vals
      )
    )
  )
)

; Finds operands that are marked as 'out-ops' by analysis to be CF_CHG

(define (-chg-flags-for-insn insn)
  (let ((vals (map (lambda (ifld) (ifld-get-value ifld)) (insn-iflds insn)))
    (outops (sfmt-out-ops (insn-sfmt insn))))
    (string-list-map (lambda (opc)
        (let ((order (insn-op-order insn (op:sem-name opc))))
          (logit 3 "out-op " (number->string order) ": " (op:sem-name opc) "\n")
          (if (>= order 0)
            (string-append "CF_CHG" (number->string (+ order 1)))
            ""
          )
        )
      )
      (filter (lambda (val) 
        (not (null? (find (lambda (op)
          (and (operand? val) (equal? (op:sem-name val) (op:sem-name op))))
          outops
        ))))
        vals
      )
    )
  )
)

; Generate a single instruc_t entry
; Note we do not consider: CF_JUMP, CF_CALL, CF_STOP, CF_SHFT
; You should add them manually to the generated code

(define (-gen-insn-opcode-entry insn)
  (let* ((flags (append (-use-flags-for-insn insn) (-chg-flags-for-insn insn))))
    (string-append
      "  { \""
      (insn-mnemonic insn)
      "\",    "
      (if (null? flags)
        "0"
        (string-join flags "|")
      )
      " }, //"
      (insn-syntax insn)
      "\n"
    )
  )
)

; Generate instruc_t entries for all instructions

(define (-gen-insn-list)
  (logit 2 "Generating instructions list ...\n")
  (let* ((all-attrs (current-insn-attr-list))
   (all-insn (non-multi-insns (current-insn-list))))
    (map analyze-insn-op-order! all-insn)
    (string-write
     "instruc_t Instructions[] = {
  { \"\", 0 }, // unknown\n"

     (lambda ()
       (string-write-map (lambda (insn)
                           (logit 3 "Generating instruction entry for " (obj:name insn) " ...\n")
                           (-gen-insn-opcode-entry insn))
                         all-insn))

     "};\n"
     )
    )
)

(define (-gen-insn-enum)
  (logit 2 "Generating instructions enum ...\n")
  (let* ((all-attrs (current-insn-attr-list))
   (all-insn (non-multi-insns (current-insn-list))))
    (string-write
     "typedef enum nameNum ENUM_SIZE(uint16)
{
  " (gen-insn-enum "UNKNOWN") " = 0, \n"

     (map (lambda (insn) (string-append "  " (gen-cpu-insn-enum (current-cpu) insn) ", \n")) all-insn)

     "} @PREFIX@_INSN_TYPE;\n"
     )
    )
)

; Return the maximum number of operand instances used by any insn.
; If not generating the operand instance table, use a heuristic.

(define (max-operand-instances)
  (if /opcodes-build-operand-instance-table?
      (apply max
       (map (lambda (insn)
        (+ (length (sfmt-in-ops (insn-sfmt insn)))
           (length (sfmt-out-ops (insn-sfmt insn)))))
      (current-insn-list)))
      6) ; TODO: Error if > 6
)


; Entry point.

(define (ins.cpp)
  (logit 1 "Generating ins.cpp ...\n")

  ;(sim-analyze-insns!)

  ; Turn parallel execution support on if cpu needs it.
  ;(set-with-parallel?! (state-parallel-exec?))

  ; Tell the rtx->c translator we are the simulator.
  ;(rtl-c-config! #:rtl-cover-fns? #t)

  (string-write
   (gen-c-copyright "@ARCH@ IDP instructions"
      CURRENT-COPYRIGHT CURRENT-PACKAGE)
   "\
#include \"@arch@.hpp\"
\n"
   -gen-insn-list
   )
)

(define (ins.hpp)
  (logit 1 "Generating ins.hpp ...\n")

  ;(sim-analyze-insns!)

  ; Turn parallel execution support on if cpu needs it.
  ;(set-with-parallel?! (state-parallel-exec?))

  ; Tell the rtx->c translator we are the simulator.
  ;(rtl-c-config! #:rtl-cover-fns? #t)

  (string-write
   (gen-c-copyright "@ARCH@ IDP instructions"
      CURRENT-COPYRIGHT CURRENT-PACKAGE)
    "\
#ifndef __INSTRS_HPP
#define __INSTRS_HPP

extern instruc_t Instructions[];
\n"
  ; (gen-cpu-insn-enum-decl (current-cpu) (non-multi-insns (current-insn-list))) ; not used because we need UINT16
   -gen-insn-enum
   "\
#endif
"
   )
)

; ins
; CF_USE1 - CF_USE6: sfmt's in-ops, check numbers
; CF_CHG1 - CF_CHG6: sfmt's out-ops, check numbers
; CF_JUMP, CF_CALL, CF_STOP, CF_SHFT: manual

; regs
; names - manual (hard to consolidate names across operands)
; asm_t - manual (not that hard to hand code)

; ana
; itype - decode (easy)
; ops - clear all shown initially, parse each operand
;   registers - hw reg unit(s), index convert to IDA, type = o_reg
;     md-operand:cdata op == POINTER, type = o_phrase
;   immediate - type = o_imm, manual parse of o_near and o_mem
;   pc - not used
;   memory - ignore

; emu
; run instruction if it involves sp

; out
; tbd