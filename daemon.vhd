---------------------------------------------------------------------------------
--
-- PROJECT: UIUC ECE 385 Final Project, Fall 2012
--
--
-- MODULE:  Altera Meatboy HD PS2 Meatboy Pilot Daemon (daemon.vhd)
--
--
-- DUTY:    Processes output from the keyboard reader and pilots Meatboy
--          through the physics engine.
--
--
-- NOTES:   Physics engine should sample its controls at the falling edge of
--          a shared 27 Mhz clock.
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.ALL;

--
-- Processes output from the keyboard reader and pilots Meatboy
-- through the physics engine.
--
entity daemon is
port(-- central controls
     clk      : in std_logic; -- 27 MHz
     reset    : in std_logic;
     fStart   : in std_logic;
     
     -- keyboard input (sync, but async timing)
     codeRdy  : in std_logic;  -- 0=>1 iff new valid scan code
     scanCode : in std_logic_vector(7 downto 0); -- PS2 key code
     make     : in std_logic; -- 1 iff make code, else break code
     
     -- physics engine controls (synced off 27 MHz clk)
     run      : out std_logic;
     jump     : out std_logic;
     R        : out std_logic;
     L        : out std_logic);

end daemon;


architecture behavioral of daemon is

   signal runReg, jReg, rReg, lReg, rdyReg, jumping : std_logic;

   begin

   -- route output
   run   <= runReg;
   jump  <= jReg;
   R     <= rReg;
   L     <= lReg;

   -- update internal registers
   updateRegs : process(reset, clk)
   begin
      if(reset = '1') then -- reset signal
         runReg   <= '0';
         jReg     <= '0';
         rReg     <= '0';
         lReg     <= '0';
         rdyReg   <= '0';
         jumping  <= '0';
      elsif(falling_edge(clk)) then
         rdyReg <= codeRdy; -- used for codeRdy rising edge detection
         if((codeRdy = '1') and (rdyReg = '0')) then -- new code ready
            case scanCode is -- update registers
            when x"1A" => -- z-key (run)
               runReg <= make;
            when x"22" => -- x-key (jump)
               jumping <= make; -- used for break-make edge detection
               if((make = '1') and (jumping = '0')) then -- break=>make edge
                  jReg <= '1';
               end if;
            when x"49" => -- right arrow
               rReg <= make;
            when x"41" => -- left arrow
               lReg <= make;
            when others =>
               null;
            end case;
         elsif(fStart = '1') then -- frame start and no new scan code
            jReg <= '0'; -- erase the jump command for the next frame
         end if;
      end if;
   end process;

end behavioral;

