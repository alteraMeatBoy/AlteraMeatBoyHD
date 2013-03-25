---------------------------------------------------------------------------------
--
-- PROJECT: UIUC ECE 385 Final Project, Fall 2012
--
--
-- MODULE:  Altera Meatboy HD PS2 Keyboard Reader (keyboard.vhd)
--
--
-- DUTY:    Processes input from the PS2 keyboard in real-time.
--
--
-- NOTES:   Does not check for valid start/stop/parity.
--
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;


--
-- A serial keyboard processor.
--
-- The most recent key code is placed in output scanCode and is
-- valid when codeRdy=1. Output codeRdy pulses to 0 between each
-- new output key code. Does not check for valid start/stop/parity.
--
entity keyboard is
port( -- central controls
      Clk      : in std_logic; -- 27 MHz
      reset    : in std_logic;

      -- ps2 keyboard input
      psClk    : in std_logic; -- async
      psData   : in std_logic; -- async

      -- output (sync, but async timing)
      codeRdy  : out std_logic;  -- 0=>1 iff new valid scan code 
      scanCode : out std_logic_vector(7 downto 0); -- PS2 key code
      make     : out std_logic); -- 1 iff make code, else break code

end keyboard;

architecture Behavioral of keyboard is

  component reg_8 is
    port(   Clk : in std_logic;
            Reset : in std_logic;
            D : in std_logic_vector(7 downto 0);
            Shift_In : in std_logic;
            Load: in std_logic;
            Shift_En : in std_logic;
            Shift_Out : out std_logic;
            Data_Out : out std_logic_vector(7 downto 0));
  end component;

  type keyboard_state is (WAIT_FOR_FIRST_DATA, WAIT_FOR_NEXT_DATA, RECV_DATA, 
                          PARITY_STOP, WAIT_FOR_SCAN_CODE);
  signal state, nextState : keyboard_state;
  
  signal q1, q2, psFalling, shift : std_logic;
  signal dCount : std_logic_vector(3 downto 0);

  -- counter used to divide host clock by 512 for decreased psClk sampling
  signal clkCount : std_logic_vector(7 downto 0);
  
  signal makeReg, break : std_logic;
  signal scanCodeReg : std_logic_vector(7 downto 0);
  
begin

  make <= makeReg;
  scanCode <= scanCodeReg;

  -- write codeRdy output (combinational)
  outputCodeRdy: process(state) is
  begin
    case state is
      when WAIT_FOR_NEXT_DATA =>
        codeRdy <= '1'; -- a key has been pressed after last reset signal
      when others =>
        codeRdy <= '0';
    end case;
  end process;
  
  -- register to hold most recent key code (when codeRdy = 1)
  code : reg_8
    port map( Clk => Clk,
              Reset => reset,
              D => x"00",
              Shift_In => psData,
              Load => '0',
              Shift_En => shift,
              Data_Out => scanCodeReg);

  -- update psFalling from sampled psClk
  psFallingEdge: process(Clk, reset) is
  begin
    if(reset = '1') then -- reset
      psFalling <= '0';
      q1 <= '1';
      q2 <= '1';
      clkCount <= "00000000";
    elsif(rising_edge(Clk)) then -- count clock cycle
      clkCount <= (clkCount + '1');
      if(clkCount = "00000000") then -- sample psClk for falling edge
        q1 <= psClk;
        q2 <= q1;
        psFalling <= (q2 and (not q1));
      else
        psFalling <= '0'; -- only pulse psFalling for one clock cycle
      end if;
    end if;
  end process;
  
  -- updates state/dCount/shift
  updateState: process(Clk, reset) is
  begin
    if(reset = '1') then -- reset state variables
      state <= WAIT_FOR_FIRST_DATA;
      dCount <= x"0";
      shift <= '0';
      makeReg <= '1';
      break <= '0';
    elsif(falling_edge(Clk)) then -- update state/dCount/shift
      case state is
        when RECV_DATA => -- wait for psClk falling edge
          if(psFalling = '1') then -- count and shift in data bit
            dCount <= (dCount + '1');
            shift <= '1';
          else
            shift <= '0';
          end if;
        when PARITY_STOP => -- wait for psClk falling edge
          if(psFalling = '1') then -- count bit
            dCount <= (dCount + '1');
          end if;
          if(nextState /= PARITY_STOP) then -- about to leave PARITY_STOP
              if(break = '1') then -- we had a break code last time around
                makeReg <= '0';
                break <= '0'; -- reset break marker
              else -- make code
                makeReg <= '1';
              end if;
            end if;
          shift <= '0';
        when others => -- reset count
          dCount <= x"0";
          shift <= '0';
      end case;
      if((nextState = WAIT_FOR_SCAN_CODE) and (scanCodeReg = x"F0")) then
         break <= '1'; -- set break code marker for next time around
      end if;
      state <= nextState;
    end if;
  end process;
  
  -- update nextState
  getNextState: process(Clk, state, psFalling, dCount, scanCodeReg) is
  begin
    case state is
      when WAIT_FOR_FIRST_DATA => -- wait for psClk falling edge
        if(psFalling = '1') then -- start bit received
          nextState <= RECV_DATA;
        else -- hold state
          nextState <= WAIT_FOR_FIRST_DATA;
        end if;
      when WAIT_FOR_NEXT_DATA => -- wait for psClk falling edge
        if(psFalling = '1') then -- start bit received
          nextState <= RECV_DATA;
        else -- hold state
          nextState <= WAIT_FOR_NEXT_DATA;
        end if;
      when RECV_DATA => -- wait for 8 data bits to be received
        if(dCount = x"8") then -- final data bit received
          nextState <= PARITY_STOP;
        else -- hold state
          nextState <= RECV_DATA;
        end if;
      when PARITY_STOP => -- wait for stop and parity bits to be received
        if(dCount = x"a") then -- stop bit received
          if((scanCodeReg = x"E0") or (scanCodeReg = x"F0")) then -- not a scan code
            nextState <= WAIT_FOR_SCAN_CODE;
          else -- scan code
            nextState <= WAIT_FOR_NEXT_DATA;
          end if;
        else -- hold state
          nextState <= PARITY_STOP;
        end if;
      when WAIT_FOR_SCAN_CODE => -- wait for the second half of a break code
        if(psFalling = '1') then -- start bit received
          nextState <= RECV_DATA;
        else -- hold state
          nextState <= WAIT_FOR_SCAN_CODE;
        end if;
      when others => -- default safety reset
        nextState <= WAIT_FOR_FIRST_DATA;
    end case;
  end process;

end Behavioral;
