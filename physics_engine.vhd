---------------------------------------------------------------------------------
--
-- PROJECT: UIUC ECE 385 Final Project, Fall 2012
--
--
-- MODULE:  Altera Meatboy HD Physics Engine (physics_engine.vhd)
--
--
-- DUTY:    Produces Meatboy's pixel position based off of the daemon's 
--          controls.
--
--
-- NOTES:   Meatboy's physics x/y-position is at a higher 32-bit resolution.
--          This signal is rounded down by selecting the top bits for Meatboy's
--          pixel location.
--
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;


--
-- Produces Meatboy's pixel position based off of the daemon's controls.
--
entity physics_engine is
   port( -- central control
         reset    : in std_logic;
         clk      : in std_logic; -- 27 MHz
         fStart   : in std_logic;
         deadz    : out std_logic; -- force reset signal
         
         -- daemon controls
         run      : in std_logic;
         jump     : in std_logic;
         R        : in std_logic;
         L        : in std_logic;
     
         -- display controls
         meatX    : out std_logic_vector(12 downto 0);
         meatY    : out std_logic_vector(13 downto 0);
         gameOver : out std_logic;
         meatDir  : out std_logic_vector(1 downto 0);
         
         -- SRAM I/O
         pData    : in std_logic_vector(15 downto 0);
         pAddr    : out std_logic_vector(17 downto 0);
         pReadEn  : out std_logic); -- 1 iff physics engine requests SRAM data

end physics_engine;


architecture behavioral of physics_engine is

   constant X_START : std_logic_vector(31 downto 0) := x"01000000"; -- 32
   constant Y_START : std_logic_vector(31 downto 0) := x"7efc0000"; -- (-32)

   constant ZERO_32              : std_logic_vector(31 downto 0) := x"00000000"; --0
   
   -- acceleration constants
   constant GRAV_ACC             : std_logic_vector(31 downto 0) := x"00003500"; --0
   constant RUN_ACC              : std_logic_vector(31 downto 0) := x"00003400"; --0
   constant WALK_ACC             : std_logic_vector(31 downto 0) := x"00002a00";
   constant POS_FRICTION         : std_logic_vector(31 downto 0) := x"00002100";
   constant NEG_FRICTION         : std_logic_vector(31 downto 0) := x"ffffdf00";
   
   -- velocity constants
   constant FLOOR_JMP_VEL_Y      : std_logic_vector(31 downto 0) := x"ffef8100";
   constant WALL_JMP_VEL_Y       : std_logic_vector(31 downto 0) := x"ffee0000";
   constant WALL_JMP_POS_VEL_X   : std_logic_vector(31 downto 0) := x"00068000";
   constant WALL_JMP_NEG_VEL_X   : std_logic_vector(31 downto 0) := x"FFF98000";
   constant MAX_POS_VEL_X        : std_logic_vector(31 downto 0) := x"00210000";
   constant MAX_NEG_VEL_X        : std_logic_vector(31 downto 0) := x"FFDF0000";
   constant MAX_POS_VEL_Y        : std_logic_vector(31 downto 0) := x"00f00000";
   constant MAX_NEG_VEL_Y        : std_logic_vector(31 downto 0) := x"ff100000";
   constant MAX_WALK_POS_SPEED   : std_logic_vector(31 downto 0) := x"00180000";
   constant MAX_WALK_NEG_SPEED   : std_logic_vector(31 downto 0) := x"FFE80000";
   
   -- overflow constants
   constant LEFT_OVERFLOW_X      : std_logic_vector(31 downto 0) := x"7fffffff";
   constant RIGHT_OVERFLOW_X     : std_logic_vector(31 downto 0) := x"3fffffff";
   constant BOTTOM_OVERFLOW_Y    : std_logic_vector(31 downto 0) := x"bfffffff";
   constant TOP_OVERFLOW_Y       : std_logic_vector(31 downto 0) := x"7fffffff";
   
   constant ZERO_X               : std_logic_vector(12 downto 0) := "0000000000000"; -- 0
   constant ZERO_Y               : std_logic_vector(13 downto 0) := "00000000000000"; -- 0
   constant MEAT_BOY_SIZE_X      : std_logic_vector(12 downto 0) := "0000000001110"; -- 14
   constant MEAT_BOY_SIZE_Y      : std_logic_vector(13 downto 0) := "00000000001110"; -- 14
   constant MEAT_BOY_SIZE_PLUS_X : std_logic_vector(12 downto 0) := "0000000001111"; -- 15
   constant MEAT_BOY_SIZE_PLUS_Y : std_logic_vector(13 downto 0) := "00000000001111"; -- 15

   -- internal daemon control sampling registers
   signal leftR, rightR, runR, jumpR, deadzR : std_logic;
   
   -- internal registers (32-bit signed int)
   signal posX, posY, destX, destY, velX, velY : std_logic_vector(31 downto 0);

   -- internal state signals
   signal onGround, onLeftWall, onRightWall, running, goodJump, walking : std_logic;
   signal walkRight, walkLeft, walkUp, walkDown, emptySpace : std_logic;
   
   -- physics frame sequence counter
   signal frameCnt : std_logic_vector(15 downto 0);
   
   -- internal SRAM registers
   signal readEn : std_logic;
   signal memAddr : std_logic_vector(17 downto 0);
   
   signal walkRight_13, walkLeft_13, meatXR, diffX, walkedPX, walkedPLeft, walkedPRight, pLeft, pLeftPlus, pRight, pRightPlus : std_logic_vector(12 downto 0);
   signal walkDown_14, walkUp_14, meatYR, diffY, nDiffY, negDiffY, walkedPY, walkedPUp, walkedPDown, pUp, pDown, pDownPlus : std_logic_vector(13 downto 0);
   
   signal readBitIdxU, readBitIdxL : std_logic_vector(3 downto 0);
   signal bData : std_logic_vector(1 downto 0);
   
begin

   --
   -- Global reset signal
   --
   deadz <= deadzR;
   
   --
   -- output Meatboy's pixel position (leave out sign-bit)
   --
   meatXR <= posX(29 downto 17); -- (13-bit)
   meatYR <= posY(30 downto 17); -- (14-bit)
   meatX  <= meatXR;
   meatY  <= meatYR;
   
   --
   -- unsigned extension
   --
   walkRight_13 <= (x"000" & walkRight);
   walkLeft_13  <= (x"000" & walkLeft);
   walkDown_14  <= ("0000000000000" & walkDown);
   walkUp_14    <= ("0000000000000" & walkUp);
   
   --
   -- constant arithmetic units for pixel offsets
   --
   walkedPX <= std_logic_vector(unsigned(meatXR) + unsigned(walkRight_13) 
                                  - unsigned(walkLeft_13));
   walkedPY <= std_logic_vector(unsigned(meatYR) + unsigned(walkDown_14) 
                                  - unsigned(walkUp_14));
   walkedPLeft  <= std_logic_vector(unsigned(walkedPX) - unsigned(MEAT_BOY_SIZE_X));
   walkedPRight <= std_logic_vector(unsigned(walkedPX) + unsigned(MEAT_BOY_SIZE_X));
   walkedPUp    <= std_logic_vector(unsigned(walkedPY) - unsigned(MEAT_BOY_SIZE_Y));
   walkedPDown  <= std_logic_vector(unsigned(walkedPY) + unsigned(MEAT_BOY_SIZE_Y));
   pLeft  <= std_logic_vector(unsigned(meatXR) - unsigned(MEAT_BOY_SIZE_X));
   pRight <= std_logic_vector(unsigned(meatXR) + unsigned(MEAT_BOY_SIZE_X));
   pUp    <= std_logic_vector(unsigned(meatYR) - unsigned(MEAT_BOY_SIZE_Y));
   pDown  <= std_logic_vector(unsigned(meatYR) + unsigned(MEAT_BOY_SIZE_Y));
   pLeftPlus  <= std_logic_vector(unsigned(meatXR) - unsigned(MEAT_BOY_SIZE_PLUS_X));
   pRightPlus <= std_logic_vector(unsigned(meatXR) + unsigned(MEAT_BOY_SIZE_PLUS_X));
   pDownPlus  <= std_logic_vector(unsigned(meatYR) + unsigned(MEAT_BOY_SIZE_PLUS_Y));
   
   --
   -- negate diffY
   --
   nDiffY   <= (not diffY);
   negDiffY <= std_logic_vector(unsigned(nDiffY) + 1);
   
   --
   -- drive SRAM address control when appropriate (combinational)
   --
   memAddr(17 downto 14) <= x"0"; -- top SRAM addresses not used
   driveSRAM : process(frameCnt, readEn, memAddr)
   begin
      if(frameCnt /= x"0000") then -- physics owns SRAM
         pReadEn <= readEn;
         pAddr   <= memAddr;
      else -- display owns SRAM
         pReadEn <= '0';
         pAddr   <= "ZZZZZZZZZZZZZZZZZZ";
      end if;
   end process;
   
   --
   -- report if Meatboy is running (combinational)
   --
   isRunning : process(onGround, runR)
   begin
      if((onGround = '1') and (runR = '1')) then
         running <= '1';
      else
         running <= '0';
      end if;
   end process;

   --
   -- Execute the physics frame sequence just before the frame is displayed.
   --
   physicsFrameSequencer : process(reset, clk, fStart)
   begin
      
      if(falling_edge(clk)) then
      
         if(reset = '1') then -- reset everything
            deadzR   <= '0';
            leftR    <= '0';
            rightR   <= '0';
            runR     <= '0';
            jumpR    <= '0';
            
            frameCnt <= x"0000"; -- start in inactive state
            posX     <= X_START;
            posY     <= Y_START;
            velX     <= ZERO_32;
            velY     <= ZERO_32;
            diffX    <= ZERO_X;
            diffY    <= ZERO_Y;
         
            onGround <= '0';
            onLeftWall <= '0';
            onRightWall <= '0';
            goodJump <= '0';
            walking   <= '0';
            walkRight <= '0';
            walkLeft  <= '0';
            walkUp    <= '0';
            walkDown  <= '0';
            emptySpace <= '0';
         else
         
         -- kickstart the physics frame sequence upon fStart signal
         if(fStart = '1') then
            -- sample daemon controls
            leftR    <= L;
            rightR   <= R;
            runR     <= run;
            jumpR    <= jump;
            frameCnt <= x"8000";
         end if;
         
         if(frameCnt = x"8800") then -- done with physics frame (8 sub-frames)
            
            -- reset frame count to inactive state
            frameCnt <= x"0000";
            
         elsif(frameCnt /= x"0000") then -- active frame count
            
            -- increment frame count
            frameCnt <= std_logic_vector(unsigned(frameCnt) + 1);
         
            --
            -- run through physics 8-sub-frame sequence
            --
            case frameCnt(7 downto 0) is
            -- initialize sub-frame cycle
            when "00000000" => -- adjust velocity based on daemon controls
               if(jumpR = '1') then -- attempt to jump
                  readEn <= '1';
                  if(onGround = '1') then -- jump upwards
                     -- load the bottom-plus/left corner map data block
                     memAddr(13 downto 5) <= pDownPlus(13 downto 5);
                     memAddr(4 downto 0)  <= pLeft(12 downto 8);
                     readBitIdxU          <= (pLeft(7 downto 5) & '1');
                  elsif(onLeftWall = '1') then -- wall jump towards right
                     -- load the bottom/left-plus corner map data block
                     memAddr(13 downto 5) <= pDown(13 downto 5);
                     memAddr(4 downto 0)  <= pLeftPlus(12 downto 8);
                     readBitIdxU          <= (pLeftPlus(7 downto 5) & '1');
                  elsif(onRightWall = '1') then -- wall jump towards left
                     -- load the bottom/right-plus corner map data block
                     memAddr(13 downto 5) <= pDown(13 downto 5);
                     memAddr(4 downto 0)  <= pRightPlus(12 downto 8);
                     readBitIdxU          <= (pRightPlus(7 downto 5) & '1');
                  else
                     jumpR <= '0'; -- not jumping for sure
                  end if;
               end if;
            when "00000001" => -- let SRAM read complete
               null;
            when "00000010" => -- load map block data into register
               if(jumpR = '1') then
                  bData(1) <= pData(to_integer(unsigned(readBitIdxU)));
               end if;
            when "00000011" => -- check for wall and get ready to load second block
               if(jumpR = '1') then
                  if(bData(1) = '1') then -- wall present
                     goodJump <= '1'; -- record if jump is good
                  end if;
                  if(onGround = '1') then -- set address for second block
                     memAddr(4 downto 0)  <= pRight(12 downto 8);
                     readBitIdxU          <= (pRight(7 downto 5) & '1');
                  elsif(onLeftWall = '1') then
                     memAddr(13 downto 5) <= pUp(13 downto 5);
                  elsif(onRightWall = '1') then
                     memAddr(13 downto 5) <= pUp(13 downto 5);
                  end if;
               end if;
            when "00000100" => -- let SRAM read complete
               null;
            when "00000101" => -- load map block data into register
               if(jumpR = '1') then
                  bData(1) <= pData(to_integer(unsigned(readBitIdxU)));
               end if;
            when "00000110" => -- check for wall one last time and recover from jump sequence
               if(jumpR = '1') then
                  jumpR <= '0'; -- only jump once per frame
                  readEn <= '0'; -- stop reading
                  if(bData(1) = '1') then
                     goodJump <= '1'; -- record if jump is good
                  end if;
               end if;
            when "00000111" => -- jump if necessary
               if(goodJump = '1') then
                  goodJump       <= '0';
                  if(onGround = '1') then -- jump upwards
                     onGround       <= '0';
                     velY <= FLOOR_JMP_VEL_Y;
                  elsif(onLeftWall = '1') then -- wall jump towards right
                     onLeftWall    <= '0';
                     velY <= WALL_JMP_VEL_Y;
                     velX <= WALL_JMP_POS_VEL_X;
                  elsif(onRightWall = '1') then -- wall jump towards left
                     onRightWall     <= '0';
                     velY <= WALL_JMP_VEL_Y;
                     velX <= WALL_JMP_NEG_VEL_X;
                  end if;
               else                    -- not jumping
                  -- apply y-gravity
                  velY <= std_logic_vector(signed(velY) + signed(GRAV_ACC));
                  -- apply L/R daemon acceleration
                  if(leftR = '1') then
                     if(running = '1') then
                        velX <= std_logic_vector(signed(velX) - signed(RUN_ACC));
                     elsif(signed(velX) > signed(MAX_WALK_NEG_SPEED)) then
                        velX <= std_logic_vector(signed(velX) - signed(WALK_ACC));
                     end if;
                  elsif(rightR = '1') then
                     if(running = '1') then
                        velX <= std_logic_vector(signed(velX) + signed(RUN_ACC));
                     elsif(signed(velX) < signed(MAX_WALK_POS_SPEED)) then
                        velX <= std_logic_vector(signed(velX) + signed(WALK_ACC));
                     end if;
                  end if;
               end if;
            when "00001000" => -- apply velocity bounds and friction
               if(signed(velX) > signed(MAX_POS_VEL_X)) then
                  velX <= MAX_POS_VEL_X;
               elsif(signed(velX) < signed(MAX_NEG_VEL_X)) then
                  velX <= MAX_NEG_VEL_X;
               elsif(signed(velX) > signed(POS_FRICTION)) then
                  velX <= std_logic_vector(signed(velX) - signed(POS_FRICTION));
               elsif(signed(velX) < signed(NEG_FRICTION)) then
                  velX <= std_logic_vector(signed(velX) - signed(NEG_FRICTION));
               else
                  velX <= ZERO_32;
               end if;
               if(signed(velY) > signed(MAX_POS_VEL_Y)) then
                  velY <= MAX_POS_VEL_Y;
               elsif(signed(velY) < signed(MAX_NEG_VEL_Y)) then
                  velY <= MAX_NEG_VEL_Y;
               elsif(signed(velY) > signed(POS_FRICTION)) then
                  velY <= std_logic_vector(signed(velY) - signed(POS_FRICTION));
               elsif(signed(velY) < signed(NEG_FRICTION)) then
                  velY <= std_logic_vector(signed(velY) - signed(NEG_FRICTION));
               else
                  velY <= ZERO_32;
               end if;
            when "00001001" => -- calculate destination
               destX <= std_logic_vector(signed(posX) + signed(velX));
               destY <= std_logic_vector(signed(posY) + signed(velY));
            when "00001010" => -- keep destination within bounds (use unsigned comparisons)
               diffX <= velX(29 downto 17); -- store velocity as pixel displacement
               diffY <= velY(30 downto 17);
               if(unsigned(destX) > unsigned(LEFT_OVERFLOW_X)) then
                  destX <= ZERO_32;
               elsif(unsigned(destX) > unsigned(RIGHT_OVERFLOW_X)) then
                  destX <= RIGHT_OVERFLOW_X;
               end if;
               if(unsigned(destY) > unsigned(BOTTOM_OVERFLOW_Y)) then
                  destY <= ZERO_32;
               elsif(unsigned(destY) > unsigned(TOP_OVERFLOW_Y)) then
                  destY <= TOP_OVERFLOW_Y;
               end if;
            when "00001011"|"00001100"|"00001101"|"00001110"|"00001111" =>
               null; -- wait for proper walk routine alignment
            when "11111111" => -- acount for rounding errors at the end
               if((posX(29 downto 17) = destX(29 downto 17))
                   and (posY(30 downto 17) = destY(30 downto 17))) then
                  posX <= destX;
                  posY <= destY;
               end if;
            when others =>
               --
               -- walk routine
               --
               case frameCnt(3 downto 0) is
               when "0000" => -- figure out which way to walk (if any)
                  walking   <= '0'; -- default stationary walk-cycle
                  walkRight <= '0';
                  walkLeft  <= '0';
                  walkUp    <= '0';
                  walkDown  <= '0';
                  if(signed(diffX) > 0) then 
                     if((signed(diffX) >= signed(negDiffY)) 
                          and (signed(diffX) >= signed(diffY))) then  -- possitive x-domininant displacement
                        walkRight <= '1';
                     elsif(signed(diffY) > 0) then -- possitive y-domininant displacement
                        walkDown <= '1';
                     else -- negative y-domininant displacement
                        walkUp <= '1';
                     end if;
                  elsif(signed(diffX) < 0) then
                     if((signed(diffX) <= signed(negDiffY)) 
                          and (signed(diffX) <= signed(diffY))) then  -- negative x-domininant displacement
                        walkLeft <= '1';
                     elsif(signed(diffY) > 0) then -- possitive y-domininant displacement
                        walkDown <= '1';
                     else -- negative y-domininant displacement
                        walkUp <= '1';
                     end if;
                  elsif(signed(diffY) < 0) then -- (x-disp=0) negative y-dominant displacement
                     walkUp <= '1';
                  elsif(diffY /= ZERO_Y) then -- positive y-dominant displacement
                     walkDown <= '1';
                  else -- x and y displacement is zero (keep stationary default setting)
                     null;
                  end if;
               when "0001" => -- determine SRAM memory address to access for appropriate map-data
                  if((walkUp = '1') or (walkDown = '1') 
                       or (walkLeft = '1') or (walkRight = '1')) then
                     walking <= '1'; -- record that we are currently moving in our walk
                     readEn <= '1';
                  end if;
                  if(walkLeft = '1') then -- top/left
                     memAddr(13 downto 5) <= walkedPUp(13 downto 5);
                     memAddr(4 downto 0)  <= walkedPLeft(12 downto 8);
                     readBitIdxU          <= (walkedPLeft(7 downto 5) & '1');
                     readBitIdxL          <= (walkedPLeft(7 downto 5) & '0');
                  elsif(walkRight = '1') then -- top/right
                     memAddr(13 downto 5) <= walkedPUp(13 downto 5);
                     memAddr(4 downto 0)  <= walkedPRight(12 downto 8);
                     readBitIdxU          <= (walkedPRight(7 downto 5) & '1');
                     readBitIdxL          <= (walkedPRight(7 downto 5) & '0');
                  elsif(walkUp = '1') then -- top/left
                     memAddr(13 downto 5) <= walkedPUp(13 downto 5);
                     memAddr(4 downto 0)  <= walkedPLeft(12 downto 8);
                     readBitIdxU          <= (walkedPLeft(7 downto 5) & '1');
                     readBitIdxL          <= (walkedPLeft(7 downto 5) & '0');
                  elsif(walkDown = '1') then -- bottom/left
                     memAddr(13 downto 5) <= walkedPDown(13 downto 5);
                     memAddr(4 downto 0)  <= walkedPLeft(12 downto 8);
                     readBitIdxU          <= (walkedPLeft(7 downto 5) & '1');
                     readBitIdxL          <= (walkedPLeft(7 downto 5) & '0');
                  end if;
               when "0010" => -- wait for SRAM data read to complete
                  null;
               when "0011" => -- load block map data
                  if(walking = '1') then
                     bData(1) <= pData(to_integer(unsigned(readBitIdxU)));
                     bData(0) <= pData(to_integer(unsigned(readBitIdxL)));
                  end if;
               when "0100" => -- process first block and get ready to load second block map data
                  if(walking = '1') then
                     case bData is
                     when "00" => -- Meatboy hit air
                        emptySpace <= '1'; -- empty for now..
                     when "01" => -- Meatboy hit salt
                        deadzR <= '1'; -- trigger an async global reset now
                     when others => -- Meatboy hit a wall
                        emptySpace <= '0';
                     end case;
                     if(walkLeft = '1') then -- bottom/left
                        memAddr(13 downto 5) <= walkedPDown(13 downto 5);
                     elsif(walkRight = '1') then -- bottom/right
                        memAddr(13 downto 5) <= walkedPDown(13 downto 5);
                     elsif(walkUp = '1') then -- top/right
                        memAddr(4 downto 0)  <= walkedPRight(12 downto 8);
                        readBitIdxU          <= (walkedPRight(7 downto 5) & '1');
                        readBitIdxL          <= (walkedPRight(7 downto 5) & '0');
                     elsif(walkDown = '1') then -- bottom/right
                        memAddr(4 downto 0)  <= walkedPRight(12 downto 8);
                        readBitIdxU          <= (walkedPRight(7 downto 5) & '1');
                        readBitIdxL          <= (walkedPRight(7 downto 5) & '0');
                     end if;
                  end if;
               when "0101" => -- wait for SRAM data read to complete
                  null;
               when "0110" => -- load block map data
                  if(walking = '1') then
                     bData(1) <= pData(to_integer(unsigned(readBitIdxU)));
                     bData(0) <= pData(to_integer(unsigned(readBitIdxL)));
                  end if;
               when "0111" => -- process second block
                  if(walking = '1') then
                     case bData is
                     when "00" => -- Meatboy hit air
                        null; -- hold emptySpace state
                     when "01" => -- Meatboy hit salt
                        deadzR <= '1'; -- trigger an async global reset now
                     when others => -- Meatboy hit a wall
                        emptySpace <= '0';
                     end case;
                  end if;
               when "1000" => -- process collision
                  if(walking = '1') then
                     if(emptySpace = '1') then           -- Meatboy can move into empty space
                        if((walkLeft = '1') or (walkRight = '1')) then -- x-movement happening
                           if(onLeftWall = '1') then
                              onLeftWall <= '0';  -- blitz onLeftWall
                           end if;
                           if(onRightWall = '1') then
                              onRightWall <= '0'; -- blitz onRightWall
                           end if;
                        end if;
                        if((walkUp = '1') or (walkDown = '1')) then -- y-movement happening
                           if(onGround = '1') then
                              onGround <= '0';  -- blitz onGround
                           end if;
                        end if;
                        -- move Meatboy into empty space
                        posX(29 downto 17) <= walkedPX;
                        posY(30 downto 17) <= walkedPY;
                        if(walkLeft = '1') then -- hit a wall on left
                           diffX <= std_logic_vector(unsigned(diffX) + 1);
                        elsif(walkRight = '1') then -- hit a wall on right
                           diffX <= std_logic_vector(unsigned(diffX) - 1);
                        elsif(walkUp = '1') then -- hit a ceiling
                           diffY <= std_logic_vector(unsigned(diffY) + 1);
                        elsif(walkDown = '1') then -- hit a floor
                           diffY <= std_logic_vector(unsigned(diffY) - 1);
                        end if;
                     else                                -- Meatboy collided with a wall
                        if(walkLeft = '1') then -- hit a wall on left
                           velX <= ZERO_32;
                           diffX <= ZERO_X;
                           onLeftWall <= '1';
                        elsif(walkRight = '1') then -- hit a wall on right
                           velX <= ZERO_32;
                           diffX <= ZERO_X;
                           onRightWall <= '1';
                        elsif(walkUp = '1') then -- hit a ceiling
                           velY <= ZERO_32;
                           diffY <= ZERO_Y;
                        elsif(walkDown = '1') then -- hit a floor
                           velY <= ZERO_32;
                           diffY <= ZERO_Y;
                           onGround <= '1';
                        end if;
                     end if;
                  end if;
               when others => -- wait for walk routine cycle to complete
                  null;
               end case;
            end case;
         end if;
         end if;
      end if;
   end process;

end behavioral;

