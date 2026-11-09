/* MAC instructions of the neorv32 CFU (rtl/core/neorv32_cpu_alu_cfu.vhd).
 *
 * k is a literal: 0..3 selects the accumulator, adding 4 makes CFU_MAC subtract.
 * CFU_RD returns ClipToShort((int)(acc >> 20), 6) and resets acc to the rounding constant 1 << 25.
 */
#ifndef _CFU_MAC_H
#define _CFU_MAC_H

#define CFU_STR_(x) #x
#define CFU_STR(x) CFU_STR_(x)

#define CFU_MAC(k, a, b) \
	__asm__ volatile (".insn r 0x0b, 0, " CFU_STR(k) ", x0, %0, %1" : : "r"(a), "r"(b))

#define CFU_RD(k) ({ int r_; \
	__asm__ volatile (".insn r 0x0b, 1, " CFU_STR(k) ", %0, x0, x0" : "=r"(r_)); r_; })

#define CFU_SET(k, v) \
	__asm__ volatile (".insn r 0x0b, 2, " CFU_STR(k) ", x0, %0, x0" : : "r"(v))

#endif
