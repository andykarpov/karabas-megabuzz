-------------------------------------------------------------------[21.09.2026]
-- Loader
--
-- Load data from SPI flash (W25Q16) into RAM on boot
-- 1. Loader process initiates by RESET=1 (asynchronous)
-- 2. Loader progress indicates via LOADER_ACTIVE=1
-- 3. At the end, a LOADER_RESET=1 pulse will be triggered to re-boot the host
-- 4. FSM is also waiting for the NEW_CFG_WR=1 to update the CFG byte from the host
--
-- Copyright (c) 2019-2026 Andy Karpov <andy.karpov@gmail.com>
--
-- Datasheets:
-- 	https://www.winbond.com/resource-files/w25q16dv_revi_nov1714_web.pdf
--		https://www.digikey.com/eewiki/pages/viewpage.action?pageId=4096096
-------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_arith.all;
USE ieee.std_logic_unsigned.all;

entity loader is
generic (
	FLASH_ADDR_START	: std_logic_vector(23 downto 0) := "000100000000000000000000"; -- 0x100000; -- 24bit address / ROM image start at
	RAM_ADDR_START		: std_logic_vector(20 downto 0) := "000000000000000000000"; -- 21 bit address / RAM address to copy ROM image to
	--																		101000000000000000000 (X140000)- DIVMMC address in Sram
	SIZE_TO_READ		: integer := 32768; -- count of bytes to read (32KB rom)
    CFG_SIZE_TO_READ    : integer := 2; -- count of bytes to read for cfg (2 bytes)
	CFG_ADDR 			: std_logic_vector(23 downto 0) := "000111110000000000000000" -- 0x1F0000; -- 24bit address / config byte address	
);
port (
	-- bus clock 28 MHz
	CLK   			: in std_logic;
	
	-- global reset
	RESET 			: in std_logic;
	
	-- RAM interface
	RAM_A 			: out std_logic_vector(20 downto 0);
	RAM_DO 			: out std_logic_vector(7 downto 0);
	RAM_WR			: out std_logic;
	
	-- Config bytes
	CFG 				: out std_logic_vector(15 downto 0) := x"FFFF";

	-- Parallel flash interface
	FLASH_A 			: out std_logic_vector(23 downto 0);
    FLASH_DI        : out std_logic_vector(7 downto 0) := x"FF";
	FLASH_DO 		: in std_logic_vector(7 downto 0);
	FLASH_RD_N 		: out std_logic := '1';
    FLASH_WR_N      : out std_logic := '1';
    FLASH_ER_N      : out std_logic := '1';
	FLASH_BUSY 		: in std_logic;
	FLASH_READY 	: in std_logic;

    -- Config writer
    NEW_CFG         : in std_logic_vector(15 downto 0) := x"FFFF";
    NEW_CFG_WR      : in std_logic := '0';
	
	-- loader state pulses
	LOADER_ACTIVE 	: out std_logic;
	LOADER_RESET 	: out std_logic
);
end loader;

architecture rtl of loader is

-- SPI
signal spi_page_bus 	: std_logic_vector(15 downto 0);
signal spi_a_bus 		: std_logic_vector(7 downto 0);

-- RAM
signal ram_a_bus 		: std_logic_vector(20 downto 0);

-- System
signal loader_act 	: std_logic := '1';
signal reset_cnt  	: std_logic_vector(3 downto 0) := "0000";
signal read_cnt 		: std_logic_vector(20 downto 0) := (others => '0');
signal clear_cnt 		: std_logic_vector(20 downto 0) := (others => '0');
signal cfg_read		: std_logic := '0';
signal cfg_cnt      : std_logic_vector(1 downto 0) := (others => '0');

signal prev_new_cfg_wr : std_logic := '0';

type machine IS( 
					 ready, 
					 cmd_read_cfg, do_read_cfg, finish_cfg,
					 cmd_read, do_read, do_next, finish, finish2,
                     cmd_erase_cfg, do_erase_cfg, cmd_write_cfg, do_write_cfg, finish_write_cfg
);     --state machine datatype
signal state : machine; --current state

begin
	
-------------------------------------------------------------------------------

-- loading state machine
process (RESET, CLK, loader_act)
VARIABLE spi_busy_cnt : INTEGER := 0;
begin
	if RESET = '1' then
		loader_act <= '1';
		cfg_read <= '0';
		spi_page_bus <= FLASH_ADDR_START(23 downto 8);
		spi_a_bus <= FLASH_ADDR_START(7 downto 0);
		ram_a_bus <= RAM_ADDR_START;
		state <= ready;
		read_cnt <= (others => '0');
        cfg_cnt <= (others => '0');
        FLASH_RD_N <= '1';
        FLASH_WR_N <= '1';
        FLASH_ER_N <= '1';
        FLASH_DI   <= x"FF";
        prev_new_cfg_wr <= '0';
	elsif CLK'event and CLK = '1' then
		
        prev_new_cfg_wr <= NEW_CFG_WR;

		case state is 
			
			when ready => -- ready to begin / finish
				if (flash_busy = '1') then 
					state <= ready;
				elsif (cfg_read = '0') then 
					state <= cmd_read_cfg;
				elsif (read_cnt < SIZE_TO_READ) then 
					state <= cmd_read;
				else 
					state <= finish;
				end if;
				
			-- read cfg byte from spi flash
			when cmd_read_cfg => 
				FLASH_RD_N <= '0';
				spi_page_bus <= CFG_ADDR(23 downto 8);
				if (cfg_cnt = 0) then
					spi_a_bus <= CFG_ADDR(7 downto 0);
				else 
					spi_a_bus <= CFG_ADDR(7 downto 0) + 1;
				end if;
				if (flash_busy = '1') then
					state <= do_read_cfg;
				end if;

			when do_read_cfg => -- wait for spi transfer
				FLASH_RD_N <= '1';
				if (flash_ready = '1') then 
					if (cfg_cnt = 0) then
						CFG(7 downto 0) <= FLASH_DO;
						cfg_cnt <= cfg_cnt + 1;
						state <= cmd_read_cfg;
					else 
						CFG(15 downto 8) <= FLASH_DO;
						cfg_read <= '1';
						state <= finish_cfg;
					end if;
				else 
					state <= do_read_cfg;
				end if;

			when finish_cfg => --set up initial addresses to read a ROM image from flash to RAM
				spi_page_bus <= FLASH_ADDR_START(23 downto 8);
				spi_a_bus <= FLASH_ADDR_START(7 downto 0);
				ram_a_bus <= RAM_ADDR_START;
				cfg_cnt <= (others => '0');
				state <= ready;
			
			when cmd_read => -- read command
				FLASH_RD_N <= '0';
				if (flash_busy = '1') then 
					state <= do_read;
				end if;
			
			when do_read => -- wait for spi transfer
				FLASH_RD_N <= '1';
				if (flash_ready = '1') then
					RAM_WR <= '1'; -- begin ram write
					RAM_DO <= FLASH_DO;
					state <= do_next;
				else 
					state <= do_read;
				end if;
			
			when do_next => -- increment address / page
				RAM_WR <= '0'; -- end ram write
				read_cnt <= read_cnt + 1; -- increment read counter
				if (spi_a_bus = X"FF") then -- increment flash page
					spi_page_bus <= spi_page_bus + 1;
				end if;
				spi_a_bus <= spi_a_bus + 1; -- increment flash address 
				ram_a_bus <= ram_a_bus + 1; -- increment ram address
				state <= ready;

			when finish => -- finish of reading rom images fro flash to ram
				state <= finish2;
			
			when finish2 => -- read all the required data from SPI flash
				loader_act <= '0'; -- loader finished

				-- listening for cfg write command
				if (NEW_CFG_WR = '1') then
					cfg_cnt <= (others => '0');
					state <= cmd_erase_cfg;
					loader_act <= '1';
				end if;
                 
			-- erase block to write a new cfg byte
			when cmd_erase_cfg => 
				FLASH_ER_N <= '0';
				spi_page_bus <= CFG_ADDR(23 downto 8);
				spi_a_bus <= CFG_ADDR(7 downto 0);
				if (flash_busy = '1') then
					state <= do_erase_cfg;
				end if;

			when do_erase_cfg => -- wait for spi transfer
				FLASH_ER_N <= '1';
				if (flash_busy = '0') then 
					state <= cmd_write_cfg;
				end if;

			-- write a new cfg byte
			when cmd_write_cfg => 
				FLASH_WR_N <= '0';
				spi_page_bus <= CFG_ADDR(23 downto 8);
				if (cfg_cnt = 0) then
					spi_a_bus <= CFG_ADDR(7 downto 0);                
					FLASH_DI <= NEW_CFG(7 downto 0);
				else 
					spi_a_bus <= CFG_ADDR(7 downto 0) + 1;                
					FLASH_DI <= NEW_CFG(15 downto 8);
				end if;
				if (flash_busy = '1') then
					state <= do_write_cfg;
				end if;

			when do_write_cfg => -- wait for spi transfer
				FLASH_WR_N <= '1';
				if (flash_busy = '0') then 
					if (cfg_cnt = 0) then
						cfg_cnt <= cfg_cnt + 1;
						state <= cmd_write_cfg;
					else 
						state <= finish_write_cfg;
					end if;
				end if;

			-- going to re-read cfg bytes
			when finish_write_cfg => 
				cfg_read <= '0';
				cfg_cnt <= (others => '0');
				state <= cmd_read_cfg;
		end case;
	
	end if;
end process;

-- reset signal at the end
process (RESET, CLK, reset_cnt, loader_act)
begin
	if RESET = '1' then
		reset_cnt <= "0000";
	elsif CLK'event and CLK = '1' then
		if (loader_act = '0' and reset_cnt /= "1000") then 
			reset_cnt <= reset_cnt + 1;
		end if;
	end if;
end process;

-------------------------------------------------------------------------------

LOADER_ACTIVE <= loader_act;
LOADER_RESET <= reset_cnt(2);
FLASH_A <= spi_page_bus & spi_a_bus;
RAM_A <= ram_a_bus;

end rtl;
