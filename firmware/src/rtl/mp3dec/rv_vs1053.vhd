-- VS1053 emulation on neorv32: the CPU pulls MP3 data from the FIFO of the host interface, decodes it
-- with Helix (sw/src/mp3dec) and plays the PCM through a ring buffer.
--
-- Everything the CPU needs is on the XBUS and answers in one cycle:
--   0x00000000  ROM, ROM_WORDS words, loaded from SPI flash by loader.vhd
--   0x10000000  PCM ring, 2048 words (bits 15:0 left, 31:16 right), mirrored every 8 KB so that Helix can
--               write a whole frame past the end of the ring
--   0x20000000  r: bit 8 = byte valid, bits 7:0 = next byte of the FIFO; reading a valid byte consumes it
--   0x20000004  r: bits 7:0 = volume register (#FB)
--   0x20000008  r: play pointer; w: end of the committed PCM (both 12 bits, one more than the ring index)
--   0x2000000C  w: NCO increment per CPU clock, 2^32 is one sample per clock
--
-- Domains: the CPU, the ring and the player run on clk_cpu (70 MHz), the FIFO and the mixer on clk_bus
-- (28 MHz). A byte from the FIFO and a sample to the mixer cross with a toggle: the data is stable long before.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rv_byte_ram is
  port (
    clk     : in  std_ulogic;
    we      : in  std_ulogic;
    addr_a  : in  std_ulogic_vector(10 downto 0);
    din     : in  std_ulogic_vector(7 downto 0);
    dout_a  : out std_ulogic_vector(7 downto 0);
    addr_b  : in  std_ulogic_vector(10 downto 0);
    dout_b  : out std_ulogic_vector(7 downto 0)
  );
end entity;

architecture rtl of rv_byte_ram is
  type mem_t is array (0 to 2047) of std_ulogic_vector(7 downto 0);
  signal mem : mem_t;
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if (we = '1') then
        mem(to_integer(unsigned(addr_a))) <= din;
      end if;
      dout_a <= mem(to_integer(unsigned(addr_a)));
      dout_b <= mem(to_integer(unsigned(addr_b)));
    end if;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity rv_vs1053 is
  generic (
    ROM_WORDS : natural := 9216 -- 36 KB
  );
  port (
    clk_bus        : in  std_logic;
    clk_cpu        : in  std_logic;
    reset          : in  std_logic;
    rom_busy       : in  std_logic; -- the CPU has to wait for its ROM
    -- ROM image from the loader, clk_bus
    rom_a          : in  std_logic_vector(20 downto 0);
    rom_do         : in  std_logic_vector(7 downto 0);
    rom_wr         : in  std_logic;
    -- VS1053 host interface, clk_bus
    fifo_rd_en     : out std_logic;
    fifo_data      : in  std_logic_vector(7 downto 0);
    fifo_empty     : in  std_logic;
    soft_reset_cmd : in  std_logic;
    hard_reset_cmd : in  std_logic;
    reg_volume     : in  std_logic_vector(7 downto 0);
    -- audio, clk_bus
    audio_l        : out std_logic_vector(15 downto 0);
    audio_r        : out std_logic_vector(15 downto 0);
    -- debug
    uart_tx        : out std_logic
  );
end entity;

architecture rtl of rv_vs1053 is

  -- reset --
  signal rst_cnt  : unsigned(3 downto 0) := (others => '1');
  signal rst_bus  : std_ulogic := '1';
  signal cpu_rstn : std_ulogic;
  signal rst_sync : std_ulogic_vector(1 downto 0) := "11";
  signal rst_cpu  : std_ulogic;

  -- ROM --
  type rom_t is array (0 to ROM_WORDS - 1) of std_ulogic_vector(31 downto 0);
  signal rom      : rom_t;
  signal rom_q    : std_ulogic_vector(31 downto 0);
  signal rom_hold : std_ulogic_vector(23 downto 0);

  -- XBUS --
  signal adr, dat_o, dat_i : std_ulogic_vector(31 downto 0);
  signal sel    : std_ulogic_vector(3 downto 0);
  signal stb, we, ack : std_ulogic;
  signal region_q : std_ulogic_vector(1 downto 0); -- region of the access being answered
  signal is_ring, is_reg : std_ulogic;

  -- PCM ring and player --
  signal ring_q, play_q : std_ulogic_vector(31 downto 0);
  signal ring_we  : std_ulogic_vector(3 downto 0);
  signal rp, wp   : unsigned(11 downto 0);
  signal nco_inc  : unsigned(31 downto 0);
  signal nco_acc  : unsigned(32 downto 0);
  signal pcm_lr   : std_ulogic_vector(31 downto 0);
  signal play_tgl : std_ulogic;
  signal play_sync : std_ulogic_vector(2 downto 0) := "000";

  -- FIFO byte bridge --
  signal fifo_st   : unsigned(1 downto 0);
  signal fifo_rd   : std_ulogic;
  signal hold_full : std_ulogic;
  signal hold_byte : std_ulogic_vector(7 downto 0);
  signal byte_tgl  : std_ulogic;
  signal ack_sync  : std_ulogic_vector(1 downto 0);
  signal ack_prev  : std_ulogic;
  signal byte_sync : std_ulogic_vector(1 downto 0);
  signal byte_prev : std_ulogic;
  signal have      : std_ulogic;
  signal ack_tgl   : std_ulogic;
  signal cpu_byte  : std_ulogic_vector(7 downto 0);

  signal vol_sync1, vol_sync2 : std_ulogic_vector(7 downto 0);
  signal reg_q : std_ulogic_vector(31 downto 0);

  signal audio_lr : std_ulogic_vector(31 downto 0) := (others => '0');

begin

  -- CPU --------------------------------------------------------------------------------------
  cpu_inst: entity neorv32.neorv32_top
  generic map (
    CLOCK_FREQUENCY   => 70000000,
    BOOT_MODE_SELECT  => 1,
    BOOT_ADDR_CUSTOM  => x"00000000",
    RISCV_ISA_C       => true,
    RISCV_ISA_M       => true,
    RISCV_ISA_Zicntr  => true,
    RISCV_ISA_Xcfu    => true,
    CPU_FAST_MUL_EN   => true,
    CPU_FAST_MUL_REGS => 3,
    CPU_FAST_SHIFT_EN => true,
    DMEM_EN           => true,
    DMEM_SIZE         => 32*1024,
    XBUS_EN           => true,
    XBUS_REGSTAGE_EN  => false,
    IO_UART0_EN       => true
  )
  port map (
    clk_i       => clk_cpu,
    rstn_i      => cpu_rstn,
    xbus_adr_o  => adr,
    xbus_dat_o  => dat_o,
    xbus_we_o   => we,
    xbus_sel_o  => sel,
    xbus_stb_o  => stb,
    xbus_dat_i  => dat_i,
    xbus_ack_i  => ack,
    xbus_err_i  => '0',
    uart0_txd_o => uart_tx,
    uart0_rxd_i => '1'
  );

  -- Reset: host reset, VS1053 soft/hard reset and the ROM load all restart the CPU --------------
  process(clk_bus)
  begin
    if rising_edge(clk_bus) then
      if (reset = '1') or (soft_reset_cmd = '1') or (hard_reset_cmd = '1') or (rom_busy = '1') then
        rst_cnt <= (others => '1');
        rst_bus <= '1';
      elsif (rst_cnt /= 0) then
        rst_cnt <= rst_cnt - 1;
      else
        rst_bus <= '0';
      end if;
    end if;
  end process;

  cpu_rstn <= not rst_bus;

  process(clk_cpu)
  begin
    if rising_edge(clk_cpu) then
      rst_sync <= rst_sync(0) & rst_bus;
    end if;
  end process;
  rst_cpu <= rst_sync(1);

  -- ROM: written a word at a time on clk_bus, read on clk_cpu ------------------------------------
  process(clk_bus)
  begin
    if rising_edge(clk_bus) then
      if (rom_wr = '1') then
        case rom_a(1 downto 0) is
          when "00"   => rom_hold(7 downto 0)   <= std_ulogic_vector(rom_do);
          when "01"   => rom_hold(15 downto 8)  <= std_ulogic_vector(rom_do);
          when "10"   => rom_hold(23 downto 16) <= std_ulogic_vector(rom_do);
          when others =>
            if (unsigned(rom_a(20 downto 2)) < ROM_WORDS) then
              rom(to_integer(unsigned(rom_a(20 downto 2)))) <= std_ulogic_vector(rom_do) & rom_hold;
            end if;
        end case;
      end if;
    end if;
  end process;

  process(clk_cpu)
    variable idx : natural;
  begin
    if rising_edge(clk_cpu) then
      idx := to_integer(unsigned(adr(15 downto 2)));
      -- synthesis translate_off
      if (idx >= ROM_WORDS) then
        idx := 0;
      end if;
      -- synthesis translate_on
      rom_q <= rom(idx);
    end if;
  end process;

  -- XBUS -------------------------------------------------------------------------------------
  is_ring <= '1' when (adr(29 downto 28) = "01") else '0';
  is_reg  <= '1' when (adr(29 downto 28) = "10") else '0';

  ring_we(0) <= stb and we and is_ring and sel(0);
  ring_we(1) <= stb and we and is_ring and sel(1);
  ring_we(2) <= stb and we and is_ring and sel(2);
  ring_we(3) <= stb and we and is_ring and sel(3);

  ring_gen: for i in 0 to 3 generate
    ring_lane: entity work.rv_byte_ram
    port map (
      clk    => clk_cpu,
      we     => ring_we(i),
      addr_a => adr(12 downto 2),
      din    => dat_o(i*8+7 downto i*8),
      dout_a => ring_q(i*8+7 downto i*8),
      addr_b => std_ulogic_vector(rp(10 downto 0)),
      dout_b => play_q(i*8+7 downto i*8)
    );
  end generate;

  dat_i <= rom_q  when (region_q = "00") else
           ring_q when (region_q = "01") else
           reg_q;

  process(clk_cpu)
    variable sum : unsigned(32 downto 0);
  begin
    if rising_edge(clk_cpu) then
      ack <= stb;
      if (stb = '1') then
        region_q <= adr(29 downto 28);
      end if;

      vol_sync1 <= std_ulogic_vector(reg_volume);
      vol_sync2 <= vol_sync1;

      byte_sync <= byte_sync(0) & byte_tgl;

      if (rst_cpu = '1') then
        wp <= (others => '0');
        rp <= (others => '0');
        nco_inc <= (others => '0');
        nco_acc <= (others => '0');
        have <= '0';
        ack_tgl <= '0';
        byte_prev <= '0';
        play_tgl <= '0';
        pcm_lr <= (others => '0');
      else
        -- a new byte from the bus side --
        if (byte_sync(1) /= byte_prev) then
          byte_prev <= byte_sync(1);
          cpu_byte <= hold_byte;
          have <= '1';
        end if;

        -- register access --
        if (stb = '1') and (is_reg = '1') then
          if (we = '1') then
            if (adr(3 downto 2) = "10") then
              wp <= unsigned(dat_o(11 downto 0));
            elsif (adr(3 downto 2) = "11") then
              nco_inc <= unsigned(dat_o);
            end if;
          else
            case adr(3 downto 2) is
              when "00" =>
                reg_q <= (31 downto 9 => '0') & have & cpu_byte;
                if (have = '1') then
                  have <= '0';
                  ack_tgl <= not ack_tgl;
                end if;
              when "01" =>
                reg_q <= (31 downto 8 => '0') & vol_sync2;
              when others =>
                reg_q <= (31 downto 12 => '0') & std_ulogic_vector(rp);
            end case;
          end if;
        end if;

        -- player: one sample per NCO overflow --
        sum := ('0' & nco_acc(31 downto 0)) + ('0' & nco_inc);
        nco_acc <= sum;
        if (nco_acc(32) = '1') and (rp /= wp) then
          pcm_lr <= play_q;
          rp <= rp + 1;
          play_tgl <= not play_tgl;
        end if;
      end if;
    end if;
  end process;

  -- FIFO byte bridge and the sample to the mixer, clk_bus ---------------------------------------
  fifo_rd_en <= fifo_rd;

  process(clk_bus)
  begin
    if rising_edge(clk_bus) then
      ack_sync <= ack_sync(0) & ack_tgl;
      play_sync <= play_sync(1 downto 0) & play_tgl;
      fifo_rd <= '0';

      if (rst_bus = '1') then
        fifo_st   <= "00";
        hold_full <= '0';
        byte_tgl  <= '0';
        ack_prev  <= '0';
        audio_lr  <= (others => '0');
      else
        case fifo_st is
          when "00" =>
            if (hold_full = '0') and (fifo_empty = '0') then
              fifo_rd <= '1';
              fifo_st <= "01";
            end if;
          when "01" => -- the FIFO takes the read at the end of this clock
            fifo_st <= "10";
          when others =>
            hold_byte <= std_ulogic_vector(fifo_data);
            hold_full <= '1';
            byte_tgl  <= not byte_tgl;
            fifo_st   <= "00";
        end case;

        if (ack_sync(1) /= ack_prev) then
          ack_prev  <= ack_sync(1);
          hold_full <= '0';
        end if;

        if (play_sync(2) /= play_sync(1)) then
          audio_lr <= pcm_lr;
        end if;
      end if;
    end if;
  end process;

  audio_l <= std_logic_vector(audio_lr(15 downto 0));
  audio_r <= std_logic_vector(audio_lr(31 downto 16));

end architecture;
