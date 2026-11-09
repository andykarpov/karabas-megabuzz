-- End-to-end test of rtl/mp3dec/rv_vs1053.vhd: the real firmware, loaded through the ROM port, decodes
-- an MP3 taken from a FIFO model. Prints the checksum of the played PCM per frame, the same as main.c of
-- the benchmark, so the sums can be compared with a run without the bridge.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_rv is
  generic (FW_HEX : string := "fw.hex"; MP3_HEX : string := "mp3.hex"; FRAMES : natural := 2; FRAME_SAMPLES : natural := 2304);
end entity;

architecture sim of tb_rv is
  signal clk_bus, clk_cpu : std_logic := '0';
  signal reset : std_logic := '1';
  signal rom_busy : std_logic := '1';
  signal rom_a : std_logic_vector(20 downto 0) := (others => '0');
  signal rom_do : std_logic_vector(7 downto 0) := (others => '0');
  signal rom_wr : std_logic := '0';
  signal fifo_rd, uart_tx : std_logic;
  signal fifo_data : std_logic_vector(7 downto 0) := (others => '0');
  signal fifo_empty : std_logic := '1';
  signal audio_l, audio_r : std_logic_vector(15 downto 0);
  type bytes_t is array (natural range <>) of std_logic_vector(7 downto 0);
begin
  clk_cpu <= not clk_cpu after 7143 ps;
  clk_bus <= not clk_bus after 17857 ps;

  dut: entity work.rv_vs1053
  port map (
    clk_bus => clk_bus, clk_cpu => clk_cpu, reset => reset, rom_busy => rom_busy,
    rom_a => rom_a, rom_do => rom_do, rom_wr => rom_wr,
    fifo_rd_en => fifo_rd, fifo_data => fifo_data, fifo_empty => fifo_empty,
    soft_reset_cmd => '0', hard_reset_cmd => '0', reg_volume => x"00",
    audio_l => audio_l, audio_r => audio_r, uart_tx => uart_tx
  );

  -- ROM load, then the MP3 data as a FIFO that always has bytes while the file lasts
  stim: process
    file f : text;
    variable l : line;
    variable b : std_logic_vector(7 downto 0);
    variable n : natural := 0;
    variable mp3 : bytes_t(0 to 65535);
    variable mp3_len : natural := 0;
    variable pos : natural := 0;
  begin
    wait for 200 ns;
    reset <= '0';
    file_open(f, FW_HEX, read_mode);
    while not endfile(f) loop
      readline(f, l);
      hread(l, b);
      wait until rising_edge(clk_bus);
      rom_a <= std_logic_vector(to_unsigned(n, 21));
      rom_do <= b;
      rom_wr <= '1';
      n := n + 1;
    end loop;
    file_close(f);
    wait until rising_edge(clk_bus);
    rom_wr <= '0';
    report "TB: ROM loaded, " & integer'image(n) & " bytes" severity note;
    rom_busy <= '0';

    file_open(f, MP3_HEX, read_mode);
    while not endfile(f) loop
      readline(f, l);
      hread(l, b);
      mp3(mp3_len) := b;
      mp3_len := mp3_len + 1;
    end loop;
    file_close(f);
    fifo_empty <= '0';
    loop
      wait until rising_edge(clk_bus);
      if (fifo_rd = '1') and (fifo_empty = '0') then
        fifo_data <= mp3(pos);
        pos := pos + 1;
        if (pos = mp3_len) then
          fifo_empty <= '1';
        end if;
      end if;
    end loop;
  end process;

  mon: process(clk_cpu)
    alias play_tgl is << signal .tb_rv.dut.play_tgl : std_ulogic >>;
    alias pcm_lr is << signal .tb_rv.dut.pcm_lr : std_ulogic_vector(31 downto 0) >>;
    variable prev : std_ulogic := '0';
    variable pending : boolean := false;
    variable sum : unsigned(31 downto 0) := (others => '0');
    variable samples, frame : natural := 0;
    variable l : line;
  begin
    if rising_edge(clk_cpu) then
      if pending then
        pending := false;
        sum := resize(sum * 31, 32) + unsigned(pcm_lr(15 downto 0));
        sum := resize(sum * 31, 32) + unsigned(pcm_lr(31 downto 16));
        samples := samples + 2;
        if samples = FRAME_SAMPLES then
          write(l, string'("TB: frame ") & integer'image(frame) & string'(" pcm="));
          hwrite(l, std_logic_vector(sum));
          writeline(output, l);
          sum := (others => '0');
          samples := 0;
          frame := frame + 1;
          if frame = FRAMES then
            std.env.finish;
          end if;
        end if;
      end if;
      -- pcm_lr changes together with the toggle, one clock later both are stable
      -- the toggle is 'U' until the reset reaches it, that is not a sample
      if (play_tgl = '0' or play_tgl = '1') and play_tgl /= prev then
        prev := play_tgl;
        pending := true;
      end if;
    end if;
  end process;
end architecture;
