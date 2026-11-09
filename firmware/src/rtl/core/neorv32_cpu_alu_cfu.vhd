-- ================================================================================ --
-- NEORV32 CPU - ALU Custom (RISC-V Instructions) Functions Unit (CFU)              --
-- -------------------------------------------------------------------------------- --
-- Karabas-MegaBuzz: the upstream XTEA example is replaced by a 32x32 multiply-     --
-- accumulate unit for the Helix MP3 polyphase filter (see PLAN.md, section 5).     --
-- -------------------------------------------------------------------------------- --
-- The NEORV32 RISC-V Processor - https://github.com/stnolting/neorv32              --
-- Copyright (c) NEORV32 contributors.                                              --
-- Copyright (c) 2020 - 2026 Stephan Nolting. All rights reserved.                  --
-- Licensed under the BSD-3-Clause license, see LICENSE for details.                --
-- SPDX-License-Identifier: BSD-3-Clause                                            --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_cpu_alu_cfu is
  port (
    -- global control --
    clk_i    : in  std_ulogic; -- global clock, rising edge
    rstn_i   : in  std_ulogic; -- global reset, low-active, async
    -- request --
    start_i  : in  std_ulogic;                     -- start trigger, single-shot
    inst_i   : in  std_ulogic_vector(31 downto 0); -- full instruction word
    rs1_i    : in  std_ulogic_vector(31 downto 0); -- register source operand 1
    rs2_i    : in  std_ulogic_vector(31 downto 0); -- register source operand 2
    -- response --
    result_o : out std_ulogic_vector(31 downto 0); -- operation result
    valid_o  : out std_ulogic                      -- operation done; result valid
  );
end entity;

architecture neorv32_cpu_alu_cfu_rtl of neorv32_cpu_alu_cfu is

  -- All instructions are R-type in the CUSTOM-0 opcode space:
  --
  --   funct3 = 000  MAC    acc[k] +/-= rs1 * rs2 (signed); rd is not written with anything useful
  --   funct3 = 001  MACRD  rd = clip16(acc[k]), then acc[k] = round_c
  --   funct3 = 010  MACSET acc[k] = sign-extended rs1
  --
  --   funct7(1:0) = k (accumulator select), funct7(2) = 1: subtract (MAC only)
  --
  -- MAC returns at once and runs in a 4-stage pipeline, so the CPU can issue one per instruction.
  -- MACRD and MACSET wait until the pipeline is empty, which keeps them ordered against MACs.
  --
  -- MACRD is bit-exact with Helix: ClipToShort((int)SAR64(acc, 20), 6).

  constant opcode_custom0_c : std_ulogic_vector(6 downto 0) := "0001011";

  constant mac_op_c    : std_ulogic_vector(2 downto 0) := "000";
  constant macrd_op_c  : std_ulogic_vector(2 downto 0) := "001";
  constant macset_op_c : std_ulogic_vector(2 downto 0) := "010";

  constant round_c : signed(63 downto 0) := to_signed(2**25, 64); -- 1 << (DEF_NFRACBITS - 1 + 32 - CSHIFT)

  -- instruction decoder --
  signal is_cust0, mac_start, sync_op : std_ulogic;
  signal funct3 : std_ulogic_vector(2 downto 0);
  signal funct7 : std_ulogic_vector(6 downto 0);
  signal k_sel  : natural range 0 to 3;

  -- multiplier pipeline; operands are split into 17-bit signed high and 15-bit unsigned low parts so that
  -- every partial product fits one DSP48A1. These registers have no reset, otherwise they do not pack into DSPs.
  signal op_a, op_b : signed(31 downto 0);
  signal a_lo, b_lo : signed(15 downto 0);
  signal p_hh       : signed(33 downto 0);
  signal p_hl, p_lh : signed(32 downto 0);
  signal p_ll       : signed(31 downto 0);
  signal mid        : signed(33 downto 0);
  signal hh_d       : signed(33 downto 0);
  signal ll_d       : signed(29 downto 0);
  signal prod       : signed(63 downto 0);

  type ctl_t is array (0 to 3) of std_ulogic_vector(2 downto 0);
  signal ctl : ctl_t; -- pipelined funct7(2:0)

  -- accumulators and control --
  type acc_t is array (0 to 3) of signed(63 downto 0);
  signal acc   : acc_t;
  signal valid : std_ulogic_vector(3 downto 0); -- pipeline stage occupied
  signal empty, pend, fire : std_ulogic;

  -- result clipping --
  signal rd_acc : signed(63 downto 0);
  signal rd_hi  : std_ulogic_vector(10 downto 0);
  signal rd_sat : std_ulogic;
  signal rd_val : std_ulogic_vector(15 downto 0);

begin

  -- Instruction Decode ---------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  is_cust0  <= '1' when (inst_i(6 downto 0) = opcode_custom0_c) else '0';
  funct3    <= inst_i(14 downto 12);
  funct7    <= inst_i(31 downto 25);
  k_sel     <= to_integer(unsigned(funct7(1 downto 0)));
  mac_start <= start_i and is_cust0 when (funct3 = mac_op_c) else '0';
  sync_op   <= is_cust0 when (funct3 = macrd_op_c) or (funct3 = macset_op_c) else '0';


  -- Multiplier Pipeline (no reset) ---------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  a_lo <= '0' & op_a(14 downto 0);
  b_lo <= '0' & op_b(14 downto 0);

  mul_pipe: process(clk_i)
  begin
    if rising_edge(clk_i) then
      -- stage 0: operands (also holds the MACSET value while waiting) --
      if (start_i = '1') then
        op_a <= signed(rs1_i);
        op_b <= signed(rs2_i);
      end if;
      -- stage 1: partial products --
      p_hh <= op_a(31 downto 15) * op_b(31 downto 15);
      p_hl <= op_a(31 downto 15) * b_lo;
      p_lh <= a_lo * op_b(31 downto 15);
      p_ll <= a_lo * b_lo;
      -- stage 2: middle sum --
      mid  <= resize(p_hl, 34) + resize(p_lh, 34);
      hh_d <= p_hh;
      ll_d <= p_ll(29 downto 0); -- the product of two 15-bit values fits 30 bits
      -- stage 3: full product --
      prod <= (hh_d & ll_d) + shift_left(resize(mid, 64), 15);
      -- control follows the data --
      ctl(0) <= funct7(2 downto 0);
      ctl(1) <= ctl(0);
      ctl(2) <= ctl(1);
      ctl(3) <= ctl(2);
    end if;
  end process;


  -- Accumulators ---------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  empty <= '1' when (valid = "0000") else '0';
  fire  <= pend and empty;

  acc_core: process(rstn_i, clk_i)
    variable idx : natural range 0 to 3;
  begin
    if (rstn_i = '0') then
      valid <= (others => '0');
      pend  <= '0';
      acc   <= (others => round_c);
    elsif rising_edge(clk_i) then
      valid <= valid(2 downto 0) & mac_start;
      -- MACRD/MACSET always take at least one wait cycle, so op_a is already latched when they fire --
      if (fire = '1') then
        pend <= '0';
      elsif (start_i = '1') and (sync_op = '1') then
        pend <= '1';
      end if;
      -- stage 4: accumulate; "fire" needs an empty pipeline, so both branches never compete --
      if (fire = '1') then
        if (funct3 = macrd_op_c) then
          acc(k_sel) <= round_c;
        else
          acc(k_sel) <= resize(op_a, 64);
        end if;
      elsif (valid(3) = '1') then
        idx := to_integer(unsigned(ctl(3)(1 downto 0)));
        if (ctl(3)(2) = '1') then
          acc(idx) <= acc(idx) - prod;
        else
          acc(idx) <= acc(idx) + prod;
        end if;
      end if;
    end if;
  end process;


  -- Result ---------------------------------------------------------------------------------
  -- -------------------------------------------------------------------------------------------
  -- (int)(acc >> 20) >> 6 keeps acc(51:26); it fits 16 bits if acc(51:41) are all equal
  rd_acc <= acc(k_sel);
  rd_hi  <= std_ulogic_vector(rd_acc(51 downto 41));
  rd_sat <= or_reduce_f(rd_hi) and (not and_reduce_f(rd_hi));
  rd_val <= std_ulogic_vector(rd_acc(41 downto 26)) when (rd_sat = '0') else
            x"8000" when (rd_acc(51) = '1') else x"7fff";

  result_o <= (31 downto 16 => rd_val(15)) & rd_val when (funct3 = macrd_op_c) else (others => '0');

  valid_o <= is_cust0 when (funct3 = mac_op_c) else -- started in the background
             fire     when (sync_op = '1')   else
             '0'; -- anything else raises an illegal instruction exception

end architecture;
