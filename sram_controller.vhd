
---------------------------------------------------------------------------------
--
-- PROJECT: UIUC ECE 385 Final Project, Fall 2012
--
--
-- MODULE:  Altera Meatboy HD SRAM Controller (sram_controller.vhd)
--
--
-- DUTY:    Provides a dumb SRAM read-only memory interface for the physics and 
--          display engines.
--
--
-- NOTES:   Purely combinational. Allow the SRAM two 27 MHz cycles for a read.
--
---------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;


--
-- Provides a dumb SRAM read-only memory interface for the physics/display engines.
--
entity sram_controller is

   port( -- display/physics engine interface
         eReadEn  : in std_logic;
         eAddr    : in std_logic_vector(17 downto 0);
         eData    : out std_logic_vector(15 downto 0);
         
         -- SRAM control signals
         mAddr    : out std_logic_vector(17 downto 0);
         mData    : in std_logic_vector(15 downto 0);
         ce       : out std_logic;
         ub       : out std_logic;
         lb       : out std_logic;
         oe       : out std_logic;
         we       : out std_logic);
         
end sram_controller;


architecture behavioral of sram_controller is
begin

   -- always enable 16-bit-word memory access (active low)
   ce <= '0'; 
   ub <= '0';
   lb <= '0';

   -- never write memory (active low)
   we <= '1';
   
   -- read memory when requested
   oe <= (not eReadEn); -- (active low)

   -- route data/addr
   mAddr <= eAddr;
   eData <= mData;
   
end behavioral;

