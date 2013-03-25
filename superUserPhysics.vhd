--
-- Altera Meatboy HD SXGA Map Building Test Entity (superUserPhysics.vhd)
--
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;


entity superUserPhysics is
   port( -- central control
         reset    : in std_logic;
         clk      : in std_logic; -- 27 MHz
         fStart   : in std_logic;
         
         -- daemon controls
         run      : in std_logic;
         jump     : in std_logic;
         R        : in std_logic;
         L        : in std_logic;
     
         -- display controls
         meatX    : out std_logic_vector(12 downto 0);
         meatY    : out std_logic_vector(13 downto 0);
         gameOver : out std_logic;
         mode     : out std_logic_vector(1 downto 0));
         
end superUserPhysics;


architecture behavioral of superUserPhysics is

   constant ZERO_12 : std_logic_vector(12 downto 0) := "0000000000000";  -- 0
   constant ZERO_13 : std_logic_vector(13 downto 0) := "00000000000000";  -- 0
   constant X_START : std_logic_vector(12 downto 0) := "0000001010000";  -- 32...
   constant Y_START : std_logic_vector(13 downto 0) := "11111101101111"; -- 32
   
   signal regX : std_logic_vector(12 downto 0);
   signal regY : std_logic_vector(13 downto 0);
   signal velX : std_logic_vector(12 downto 0);
   signal velY : std_logic_vector(13 downto 0);
   
   signal posXExt, velXExt : std_logic_vector(13 downto 0);
   signal posYExt, velYExt : std_logic_vector(14 downto 0);
   
   signal jumpCnt, moveLeft, moveRight, moveUp, moveDown : std_logic;
   

begin

   -- route output
   gameOver <= '0';
   mode(1)  <= run;
   mode(0)  <= jumpCnt;
   meatX    <= regX;
   meatY    <= regY;
   
   -- signed/unsigned extension
   posXExt <= ('0' & regX);
   posYExt <= ('0' & regY);
   velXExt <= (velX(12) & velX);
   velYExt <= (velY(13) & velY);

   
   -- test display with a Meatboy who walks around the outside of the map in a clockwise cycle
   update : process(reset, clk, fStart)
   begin
      if(reset = '1') then -- reset
         regX <= X_START;
         regY <= Y_START;
         velX <= ZERO_12;
         velY <= ZERO_13;
         jumpCnt <= '1';
      elsif(falling_edge(clk)) then
         if(fStart = '1') then -- start of frame
            
            -- adjust controls
            jumpCnt <= (jump xor jumpCnt);
            if(jumpCnt = '1') then
               moveLeft <= L;
               moveRight <= R;
               moveUp <= '0';
               moveDown <= '0';
            else
               moveUp <= L;
               moveDown <= R;
               moveLeft <= '0';
               moveRight <= '0';
            end if;
            
            -- adjust velocity
            if(moveLeft = '1') then
               velX <= std_logic_vector(signed(velX) - 2);
            elsif(moveRight = '1') then
               velX <= std_logic_vector(signed(velX) + 2);
            elsif(moveUp = '1') then
               velY <= std_logic_vector(signed(velY) - 2);
            elsif(moveDown = '1') then
               velY <= std_logic_vector(signed(velY) + 2);
            else -- friction
               if(signed(velX) > 0) then
                  velX <= std_logic_vector(signed(velX) - 1);
               elsif(signed(velX) < 0) then
                  velX <= std_logic_vector(signed(velX) + 1);
               end if;
               if(signed(velY) > 0) then
                  velY <= std_logic_vector(signed(velY) - 1);
               elsif(signed(velY) < 0) then
                  velY <= std_logic_vector(signed(velY) + 1);
               end if;
            end if;
            
            -- move position
            regX <= std_logic_vector(signed(posXExt) + signed(velXExt))(12 downto 0);
            regY <= std_logic_vector(signed(posYExt) + signed(velYExt))(13 downto 0);
         end if;
      end if;
   end process;

end behavioral;
