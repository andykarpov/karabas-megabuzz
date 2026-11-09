library ieee;
use ieee.std_logic_1164.all;
library neorv32;
use neorv32.neorv32_package.all;

entity tb is
  generic (FAST_MUL : boolean := true; MUL_REGS : natural := 3; FAST_SHIFT : boolean := true; ZBB : boolean := false;
           CFU : boolean := false; PROF_FILE : string := ""; PROF_DIV : natural := 64);
end entity;

architecture sim of tb is
  signal clk  : std_ulogic := '0';
  signal rstn : std_ulogic := '0';
  signal gpio : std_ulogic_vector(31 downto 0);
begin
  clk  <= not clk after 5 ns;
  rstn <= '1' after 100 ns;

  cpu: neorv32_top
  generic map (
    CLOCK_FREQUENCY   => 100000000,
    BOOT_MODE_SELECT  => 2,
    RISCV_ISA_C       => true,
    RISCV_ISA_M       => true,
    RISCV_ISA_Zbb     => ZBB,
    RISCV_ISA_Zicntr  => true,
    RISCV_ISA_Xcfu    => CFU,
    CPU_FAST_MUL_EN   => FAST_MUL,
    CPU_FAST_MUL_REGS => MUL_REGS,
    CPU_FAST_SHIFT_EN => FAST_SHIFT,
    IMEM_EN           => true,
    IMEM_SIZE         => 64*1024,
    DMEM_EN           => true,
    DMEM_SIZE         => 64*1024,
    IO_GPIO_NUM       => 32,
    IO_UART0_EN       => true
  )
  port map (
    clk_i  => clk,
    rstn_i => rstn,
    gpio_o => gpio
  );

  stopper: process(clk)
  begin
    if rising_edge(clk) then
      if gpio(11 downto 0) = x"D0E" then
        report "TB: done" severity note;
        std.env.finish;
      end if;
    end if;
  end process;
  -- optional profiler: dump the instruction fetch address every PROF_DIV cycles
  prof_gen: if PROF_FILE /= "" generate
    prof: process(clk)
      use std.textio.all;
      file f : text open write_mode is PROF_FILE;
      alias ireq is << signal .tb.cpu.core_complex_gen(0).neorv32_cpu_inst.ibus_req_o : bus_req_t >>;
      variable cnt : natural := 0;
      variable l : line;
    begin
      if rising_edge(clk) then
        cnt := cnt + 1;
        if cnt = PROF_DIV then
          cnt := 0;
          hwrite(l, ireq.addr);
          writeline(f, l);
        end if;
      end if;
    end process;
  end generate;
end architecture;
