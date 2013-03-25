---------------------------------------------------------------------------------
--
-- PROJECT: UIUC ECE 385 Final Project, Fall 2012
--
--
-- MODULE:  Altera Meatboy HD Display Engine (display_engine.vhd)
--
--
-- DUTY:    Paints the Altera Meatboy game window in 60 Hz SXGA (1280 x 1024).
--
--
-- NOTES:   Paints a (1280 x 1024) pixel window whose colors are derived from
--          SRAM-map-data, Meatboy's position, and the window position. A new
--          pixel is drawn on every pixel-clock-cycle (108 MHz), with a break
--          in between in each line, and a larger break at the end of the last
--          line in the frame. These breaks motivate the SRAM access timings of 
--          Altera Meatboy's physics and display engines.
--
--          During the line break, the display engine stores map data for the
--          next line to paint in 6 local 16-bit registers, when necessary. Just
--          before a next frame's top line is loaded, the display engine samples 
--          Meatboy's position from the phSyncyics engine, and decides wether or  
--          not to scroll the display window position. During the large SXGA 
--          break at the end of the frame, the phSyncyics engine access SRAM map
--          data to help determine Meatboy's next frame position. This mutually
--          exclusive shared SRAM read pattern prevents access collisions.
--
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.all;


--
-- Displays Altera Meatboy HD game action in real time.
--
entity vga_display_engine is

   port( pxlClk   : in std_logic; -- 108 MHz SXGA pixel clock (for 60 Hz frame-rate)
         reset    : in std_logic;

          -- Diplay engine controls
         meatPosX : in std_logic_vector(12 downto 0); -- roughly (0,0) to (8097, 16191)
         meatPosY : in std_logic_vector(13 downto 0);
         gameOver : in std_logic;
         meatDir  : in std_logic_vector(1 downto 0);

         -- physics engine control
         fStart   : out std_logic; -- 1 iff complete frame was just drawn (TODO: shift row down)
         
         -- VGA controls
         red      : out std_logic_vector(9 downto 0);
         green    : out std_logic_vector(9 downto 0);
         blue     : out std_logic_vector(9 downto 0);
         hs       : out std_logic;  -- Horizontal sync pulse.
         vs       : out std_logic;  -- Vertical sync pulse.
         blank    : out std_logic;  -- Blanking interval indicator.  Active low.
         sync     : out std_logic;  -- Composite Sync signal.  Active low.
         
         -- SRAM I/O
         dData    : in std_logic_vector(15 downto 0);
         dAddr    : out std_logic_vector(17 downto 0);
         dReadEn  : out std_logic); -- 1 iff display engine requests SRAM data

end vga_display_engine;


architecture Behavioral of vga_display_engine is

  --
   -- SXGA 16-color pallate
   --
   type sxga_color is array(0 to 2) of std_logic_vector(9 downto 0); -- order RGB (rIdx=0)
   type color_palate is array(0 to 15) of sxga_color;
   constant palate : color_palate :=
    ( -- 0 Orange
     ("1111111111",  -- red		1023
      "1010010100",  -- green	660
      "0000000000"), -- blue	0	
      -- 1 Dark Goldenrod
     ("1110111000",  -- red		952
      "1010110100",  -- green	692
      "0000111000"), -- blue	56
      -- 2 Orange Red
     ("1111111111",  -- red		1023
      "0010010001",  -- green	145
      "0000000000"), -- blue	0
      -- 3 Meat Red 
     ("1000110000",  -- red		560
      "0000000000",  -- green	0
      "0000000000"), -- blue	0
      -- 4 salt 0
     ("1111100101",  -- red
      "1111100100",  -- green
      "1111100010"), -- blue
      -- 5 salt 1
     ("1111010001",  -- red
      "1111010010",  -- green
      "1111010110"), -- blue
      -- 6 salt 2..
     ("1111111111",  -- red
      "1111111111",  -- green
      "1111111111"), -- blue
      -- 7 salt 3..
     ("1110010100",  -- red
      "1110010010",  -- green
      "1110010011"), -- blue
      -- 8 Dark Grey
     ("0110100111",  -- red		423
      "0110100111",  -- green	423
      "0110100111"), -- blue	423
      -- 9 Grey
     ("1011111011",  -- red		763
      "1011111011",  -- green	763
      "1011111101"), -- blue	763
      -- A
     ("0111100010",  -- red
      "0001001000",  -- green
      "1111111011"), -- blue
      -- B 
     ("0001100100",  -- red
      "0000000101",  -- green
      "1111111011"), -- blue
      -- C Yellow
     ("1110111011",  -- red		955
      "1110111011",  -- green	955
      "0000000000"), -- blue	0
      -- D Black
     ("0000000000",  -- red		0
      "0000000000",  -- green	0
      "0000000000"), -- blue	0
      -- E 
     ("1111111111",  -- red
      "1111111111",  -- green
      "1111111111"), -- blue
      -- F
     ("0000000010",  -- red
      "0111111100",  -- green
      "1000011011")); -- blue

   --
   -- tile textures (32 x 32)
   --
   type texture is array(0 to 31) of std_logic_vector(127 downto 0);
   constant airText : texture :=
     (x"00000000011000000000000001210000",
      x"00000012110022000000001001000000",
      x"00000001120020020000000000000200",
      x"00000000022000011000100002200000",
      x"00000000110100011100000022100000",
      x"00000000000000001110000220000000",
      x"00000000000000000000000100000000",
      x"00000110001101110000000000110000",
      x"00000011010011001100000000010000",
      x"00000000101110121110000000000000",
      x"00000000010110001100000000200000",
      x"00000000000000000000000000000000",
      x"00000000020010000000010001000000",
      x"00020000000110020000000000000000",
      x"00000000000000000000000000000000",
      x"00002000020110000011100001000000",
      x"11100000000010000110110010001001",
      x"11101010200000000110010000011011",
      x"10110001100000001100000000110111",
      x"11010011011002000110100001111211",
      x"11221100010000000110101012110011",
      x"11111001111000000001100211100111",
      x"01111000100000000001102210011111",
      x"00000100022200000000011211011000",
      x"00000000022200000000000000000000",
      x"00001101002220001000011000000100",
      x"00000000000010000000002200000000",
      x"00000000000110000220000000000000",
      x"00000010002200022212000000000000",
      x"00000000000200002002000002200000",
      x"00000100100000001110000002200000",
      x"00000000000000010000000000000000");
   constant saltText : texture :=
     (x"46475464756464745464776465647545",
      x"66666666574467454676744467446666",
      x"66667666657446745467674464744666",
      x"67666666574467454767744746644666",
      x"66647766665744674547776444446466",
      x"66644766776574467454776744474446",
      x"66554666576657446757467774446744",
      x"65557755666657665744674547766444",
      x"66556667557766666574467454776744",
      x"64745474474456766674444444555774",
      x"64745474474456766674444444555774",
      x"55455666446677747665476577765756",
      x"44444666446667776666664444776644",
      x"55666555747766665554445554466755",
      x"56665574776666545544455557755755",
      x"46475464756464745464777465647545",
      x"55755755747766665554445554545555",
      x"55557575777766665554445557577545",
      x"55455666444677775557767776667746",
      x"55455666555666677776667777755577",
      x"55455664466677776677776667777657",
      x"64745474474456766674446444555774",
      x"64745474474456766674446644555774",
      x"55555555767766665554445555777555",
      x"55474554455774764665554445555555",
      x"46475464756464745464777465647545",
      x"55555666577676666555444555566655",
      x"55566644455777766665554445556655",
      x"55555444566677666655544455566555",
      x"55455666666666677776667777766777",
      x"64745474474456766674444444555774",
      x"65544744566667776667444466666555");
   constant wallAText : texture :=
     (x"99999999999999999999999999999999",
      x"98888888888888888888888888888889",
      x"98888888888888888888888888888889",
      x"98899999999999999999999999999889",
      x"98899999999999999999999999999889",
      x"98899999999999999999999999999889",
      x"98899998899999999999999889999889",
      x"98899988889999999999998888999889",
      x"98899988889999999999998888999889",
      x"98899998899999999999999889999889",
      x"98899999999999999999999999999889",
      x"98899999999999999999999999999889",
      x"98899999999999999999999999999889",
      x"98899999999999999999999999999889",
      x"98899999999999999999999999999889",
      x"98899999999999999999999999999889",
      x"98899999999999999999999999999889",
      x"98899999999999999999999999999889",
      x"98899999999999999999999999999889",
      x"98899999999999999999999999999889",
      x"98899999999999999999999999999889",
      x"98899999999999999999999999999889",
      x"98899999889999999999999889999889",
      x"98899998888999999999998888999889",
      x"98899998888999999999998888999889",
      x"98899999889999999999999889999889",
      x"98899999999999999999999999999889",
      x"98899999999999999999999999999889",
      x"98899999999999999999999999999889",
      x"98888888888888888888888888888889",
      x"98888888888888888888888888888889",
      x"99999999999999999999999999999999");
   constant wallBText : texture :=
     (x"ccccddddddddccccccccddddddddcccc",
      x"cccccddddddddccccccccddddddddccc",
      x"ccccccddddddddccccccccddddddddcc",
      x"cccccccddddddddccccccccddddddddc",
      x"ccccccccddddddddccccccccdddddddd",
      x"dccccccccddddddddccccccccddddddd",
      x"ddccccccccddddddddccccccccdddddd",
      x"dddccccccccddddddddccccccccddddd",
      x"ddddccccccccddddddddccccccccdddd",
      x"dddddccccccccddddddddccccccccddd",
      x"ddddddccccccccddddddddccccccccdd",
      x"dddddddccccccccddddddddccccccccd",
      x"ddddddddccccccccddddddddcccccccc",
      x"cddddddddccccccccddddddddccccccc",
      x"ccddddddddccccccccddddddddcccccc",
      x"cccddddddddccccccccddddddddccccc",
      x"ccccddddddddccccccccddddddddcccc",
      x"cccccddddddddccccccccddddddddccc",
      x"ccccccddddddddccccccccddddddddcc",
      x"cccccccddddddddccccccccddddddddc",
      x"ccccccccddddddddccccccccdddddddd",
      x"dccccccccddddddddccccccccddddddd",
      x"ddccccccccddddddddccccccccdddddd",
      x"dddccccccccddddddddccccccccddddd",
      x"ddddccccccccddddddddccccccccdddd",
      x"dddddccccccccddddddddccccccccddd",
      x"ddddddccccccccddddddddccccccccdd",
      x"dddddddccccccccddddddddccccccccd",
      x"ddddddddccccccccddddddddcccccccc",
      x"cddddddddccccccccddddddddccccccc",
      x"ccddddddddccccccccddddddddcccccc",
      x"cccddddddddccccccccddddddddccccc");

   -- SXGA frame constants (signed or unsigned)
   constant SXGA_FRAME_COL_DIM : std_logic_vector(12 downto 0) := "0010100000000";  -- 1280
   constant SXGA_FRAME_ROW_DIM : std_logic_vector(13 downto 0) := "00010000000000"; -- 1024
   constant SXGA_FRAME_MID_COL : std_logic_vector(12 downto 0) := "0001010000000";  -- 1280/2=640
   constant SXGA_FRAME_MID_ROW : std_logic_vector(13 downto 0) := "00001000000000"; -- 1024/2=512

   -- scroll offsets (signed)
   constant POS_OFF_TOL_X : std_logic_vector(12 downto 0) := "0000010000000";  -- 128
   constant NEG_OFF_TOL_X : std_logic_vector(12 downto 0) := "1111110000000";  -- (-128)
   constant POS_OFF_TOL_Y : std_logic_vector(13 downto 0) := "00000010010110"; -- 150
   constant NEG_OFF_TOL_Y : std_logic_vector(13 downto 0) := "11111101101010"; -- (-150)
   
   -- window position constants (unsigned)
   constant MAP_WIDTH_UPPER_INV  : std_logic_vector(12 downto 0) := "1110101111111";  -- 7551
   constant MAP_WINDOW_MAX_X     : std_logic_vector(12 downto 0) := "1101100000000";  -- 6912
   constant MAP_HEIGHT_UPPER_INV : std_logic_vector(13 downto 0) := "11110111111111"; -- 15871
   constant MAP_WINDOW_MAX_Y     : std_logic_vector(13 downto 0) := "11110000000000"; -- 15360

   
   -- state machine walking through (1688, 1066) grid (unsigned)
   constant LOAD_ZERO         : std_logic_vector(2 downto 0) := "000";        -- 0
   constant SXGA_ZERO         : std_logic_vector(10 downto 0) := "00000000000"; -- 0
   constant SXGA_ONE          : std_logic_vector(10 downto 0) := "00000000001"; -- 1
   constant SXGA_TWO          : std_logic_vector(10 downto 0) := "00000000010"; -- 2
   constant SXGA_THREE        : std_logic_vector(10 downto 0) := "00000000011"; -- 3
   constant SXGA_FOUR         : std_logic_vector(10 downto 0) := "00000000100"; -- 4
   constant SXGA_FIVE         : std_logic_vector(10 downto 0) := "00000000101"; -- 5
   constant SXGA_COLS         : std_logic_vector(10 downto 0) := "11010010111"; -- <= 1687
   constant SXGA_ROWS         : std_logic_vector(10 downto 0) := "10000101001"; -- <= 1065
   constant LINE_BRK_END_COL  : std_logic_vector(10 downto 0) := "00110010111"; -- == 407
   constant FRAME_START_COL   : std_logic_vector(10 downto 0) := "00110011000"; -- == 408
   constant FRAME_BRK_END_ROW : std_logic_vector(10 downto 0) := "00000101001"; -- == 41
   constant FRAME_START_ROW   : std_logic_vector(10 downto 0) := "00000101010"; -- == 42
   constant HSYNC_START_COL   : std_logic_vector(10 downto 0) := "00000101111"; -- >= 47 (112-period)
   constant HSYNC_END_COL     : std_logic_vector(10 downto 0) := "00010011110"; -- <= 158
   constant VSYNC_START_ROW   : std_logic_vector(10 downto 0) := "00000000000"; -- >= 0 (3-period)
   constant VSYNC_END_ROW     : std_logic_vector(10 downto 0) := "00000000010"; -- <= 2
   constant LOAD_ROW_END      : std_logic_vector(10 downto 0) := "00000110000"; -- <= (6 * 8) = 48
   constant X_ZERO : std_logic_vector(12 downto 0) := ("00" & SXGA_ZERO); -- 0
   constant Y_ZERO : std_logic_vector(13 downto 0) := ('0' & X_ZERO);     -- 0
   
   constant LOAD_5 : std_logic_vector(2 downto 0) := "101";
   constant LOAD_6 : std_logic_vector(2 downto 0) := "110";
   
   constant TEXTURE_MAX_IDX : std_logic_vector(6 downto 0) := "1111111";
   
   -- counter registers
   signal xIdx, yIdx, pixelX   : std_logic_vector(10 downto 0);
   signal xPlus, yPlus, pixelY : std_logic_vector(10 downto 0);
  
   -- internal position registers
   signal meatX, winPosX, mapX, meatOffX, pixelX_13 : std_logic_vector(12 downto 0); -- (0, 0) to (8095, 16191)
   signal meatY, winPosY, mapY, meatOffY, pixelY_14 : std_logic_vector(13 downto 0);

   -- 1 iff ok to display color for a pixel
   signal display : std_logic;
   
   -- sxga sync signal registers
   signal hSync, vSync : std_logic;
   
   -- row data SRAM cache
   type row_data is array(5 downto 0) of std_logic_vector(15 downto 0);
   signal rowData : row_data; -- array of 21 registers (16-bit)
   signal loadIdx : std_logic_vector(2 downto 0);
   signal memAddr : std_logic_vector(17 downto 0);
   
   -- signal for sample_meatboy_pos_and_scroll process
   signal winPosX_14, meatOffX_14 : std_logic_vector(13 downto 0);
   signal winPosY_15, meatOffY_15 : std_logic_vector(14 downto 0);
   
   -- signals for paint_pixels process
   signal redReg, greenReg, blueReg : std_logic_vector(9 downto 0);
   signal meatUpperOffX, meatLowerOffX : std_logic_vector(12 downto 0);
   signal meatUpperOffY, meatLowerOffY : std_logic_vector(13 downto 0);
   signal bWord : std_logic_vector(15 downto 0);
   signal bData : std_logic_vector(1 downto 0);
   signal drawingFrame : std_logic;
   signal readWordIdx : std_logic_vector(2 downto 0);
   signal readBitIdxU, readBitIdxL : std_logic_vector(3 downto 0);
   signal pColIdx0, pColIdx1, pColIdx2, pColIdx3 : std_logic_vector(6 downto 0);
   signal airRow, saltRow, wallARow, wallBRow : std_logic_vector(127 downto 0);
   signal airColor, saltColor, wallAColor, wallBColor : std_logic_vector(3 downto 0);
   signal airPixelColor, saltPixelColor, wallAPixelColor, wallBPixelColor : sxga_color;
   signal mapX0, mapX1, mapX2, mapX3 : std_logic_vector(6 downto 0);
   
begin

   --
   -- route external outputs
   --
   dAddr <= memAddr;
   blank <= display;  -- pixel on/off control (active low creates implicit "not")
   hs <= hSync;
   vs <= vSync;
   sync <= '0'; --(hSync xor vSync); -- composite sync
   red <= redReg;
   green <= greenReg;
   blue <= blueReg;
   
   -- increment counters
   xPlus <= std_logic_vector(unsigned(xIdx) + 1);
   yPlus <= std_logic_vector(unsigned(yIdx) + 1);
   
   -- x/y-pixel-coordinate to draw
   pixelX <= std_logic_vector(unsigned(xPlus) - unsigned(FRAME_START_COL));
   pixelY <= std_logic_vector(unsigned(yIdx)  - unsigned(FRAME_START_ROW));
   pixelX_13 <= ("00" & pixelX);
   pixelY_14 <= ("000" & pixelY);
   
   -- x/y-map-coordinate to draw
   mapX <= std_logic_vector(unsigned(pixelX_13) + unsigned(winPosX));
   mapY <= std_logic_vector(unsigned(pixelY_14) + unsigned(winPosY));
   
   --
   -- display (1280 x 1024) pixels (combinational)
   --
   blank_proc : process(xIdx, yIdx)
   begin
      if((unsigned(xIdx) > unsigned(LINE_BRK_END_COL)) 
           and (unsigned(yIdx) > unsigned(FRAME_BRK_END_ROW))) then
         display <= '1';
      else
         display <= '0';
      end if;
   end process;
   
   --
   -- frame break start pulse for four 108 MHz cycles (combinational)
   --
   output_fstart : process(xIdx, yIdx)
   begin
      if((xIdx(10 downto 2) = SXGA_ZERO(10 downto 2)) and (yIdx = SXGA_ZERO)) then -- start of frame pulse
         fStart <= '1';
      else
         fStart <= '0';
      end if;
   end process;
   
   --
   -- increment row/col counters
   --
   counter_proc : process(pxlClk, reset, xIdx, yIdx)
   begin
      if(reset = '1') then
         xIdx <= SXGA_ZERO;
         yIdx <= SXGA_ZERO;
      elsif(rising_edge(pxlClk)) then
         if(xIdx = SXGA_COLS) then -- xIdx has reached the end of row count
            xIdx <= SXGA_ZERO; -- zero xIdx
            if (yIdx = SXGA_ROWS) then -- yIdx has reached end of line count
               yIdx <= SXGA_ZERO; -- zero yIdx
            else
               yIdx <= yPlus; -- inc yIdx
            end if;
         else
            xIdx <= xPlus; -- inc xIdx
            yIdx <= yIdx;  -- maintain yIdx (don't forget about the consequences of this)
         end if;
      end if;
   end process;

   --
   -- SXGA horizontal sync pulse
   --
   hs_proc : process (reset, pxlClk, xIdx)
   begin
   if (reset = '1') then
      hSync <= '0'; -- start outside of pulse
   elsif(rising_edge(pxlClk)) then -- use next col index
      if((unsigned(xPlus) >= unsigned(HSYNC_START_COL)) 
           and (unsigned(xPlus) <= unsigned(HSYNC_END_COL))) then
         hSync <= '1'; -- active high pulse
      else
         hSync <= '0';
      end if;
   end if;
   end process;

   --
   -- SXGA vertical sync pulse (fixed from source)
   --
   vs_proc : process(reset, pxlClk, yIdx)
   begin
      if(reset = '1') then
         vSync <= '1'; -- start at beginning of pulse
      elsif(rising_edge(pxlClk)) then -- use current row/col
         if(((yIdx = SXGA_ROWS) and (xIdx = SXGA_COLS))
              or (unsigned(yIdx) < unsigned(VSYNC_END_ROW))
               or ((yIdx = VSYNC_END_ROW)
                           and (not (xIdx = SXGA_COLS)))) then -- sorry
            vSync <= '1'; -- active high pulse
         else
            vSync <= '0';
         end if;
      end if;
   end process;
  
   --
   -- Sample Meatboy's position from the physics engine at last row in frame break
   -- and scroll window position if necessary.
   --
   --  By (yIdx = 42), the window is scrolled and (meatOffX, meatOffXY) holds
   --  Meatboy'spixel offset.
   --
   sample_meatboy_pos_and_scroll : process(reset, pxlClk, yIdx, winPosX, winPosY,
                                           meatOffX, meatOffY)
   begin
   
      -- extend integer values for proper signed/unsigned arithmetic
      winPosX_14  <= ('0' & winPosX(12 downto 0)); -- unsigned extension
      meatOffX_14 <= (meatOffX(12) & meatOffX(12 downto 0)); -- signed extension
      winPosY_15  <= ('0' & winPosY(13 downto 0)); -- unsigned extension
      meatOffY_15 <= (meatOffY(13) & meatOffY(13 downto 0)); -- signed extension
      
      -- scroll sequence
      if(reset = '1') then
         winPosX <= X_ZERO;
         winPosY <= MAP_WINDOW_MAX_Y;
      elsif(rising_edge(pxlClk) and (yIdx = FRAME_BRK_END_ROW)) then
         if(xIdx = SXGA_ZERO) then
            -- sample Meatboy's position
            meatX <= meatPosX;
            meatY <= meatPosY;
         end if; -- else
         if(xIdx = SXGA_ONE) then
            -- calc Meatboy's offset from the frame center
            meatOffX <= std_logic_vector(unsigned(meatX) - unsigned(winPosX)
                           - unsigned(SXGA_FRAME_MID_COL));
            meatOffY <= std_logic_vector(unsigned(meatY) - unsigned(winPosY)
                           - unsigned(SXGA_FRAME_MID_ROW));
         end if; -- else
         if(xIdx = SXGA_TWO) then
            -- check if offset is too large, and calculate final scroll offset
            if(signed(meatOffX) > signed(POS_OFF_TOL_X)) then
               meatOffX <= std_logic_vector(signed(meatOffX) - signed(POS_OFF_TOL_X));
            elsif(signed(meatOffX) < signed(NEG_OFF_TOL_X)) then
               meatOffX <= std_logic_vector(signed(meatOffX) - signed(NEG_OFF_TOL_X));
            else
               meatOffX <= X_ZERO;
            end if;
            if(signed(meatOffY) > signed(POS_OFF_TOL_Y)) then
               meatOffY <= std_logic_vector(signed(meatOffY) - signed(POS_OFF_TOL_Y));
            elsif(signed(meatOffY) < signed(NEG_OFF_TOL_Y)) then
               meatOffY <= std_logic_vector(signed(meatOffY) - signed(NEG_OFF_TOL_Y));
            else
               meatOffY <= Y_ZERO;
            end if;
         end if; -- else
         if(xIdx = SXGA_THREE) then
            -- scroll window position
            winPosX <= std_logic_vector(signed(winPosX_14) + signed(meatOffX_14))(12 downto 0);
            winPosY <= std_logic_vector(signed(winPosY_15) + signed(meatOffY_15))(13 downto 0);
         end if; --else
         if(xIdx = SXGA_FOUR) then
            -- keep window position within bounds
            if(unsigned(winPosX) > unsigned(MAP_WIDTH_UPPER_INV)) then
               winPosX <= X_ZERO;
            elsif(unsigned(winPosX) > unsigned(MAP_WINDOW_MAX_X)) then
               winPosX <= MAP_WINDOW_MAX_X;
            end if;
            if(unsigned(winPosY) > unsigned(MAP_HEIGHT_UPPER_INV)) then
               winPosY <= Y_ZERO;
            elsif(unsigned(winPosY) > unsigned(MAP_WINDOW_MAX_Y)) then
               winPosY <= MAP_WINDOW_MAX_Y;
            end if;
         end if; --else
         if(xIdx = SXGA_FIVE) then
            -- calculate final meatboy pixel offset
            meatOffX <= std_logic_vector(unsigned(meatX) - unsigned(winPosX));
            meatOffY <= std_logic_vector(unsigned(meatY) - unsigned(winPosY));
         end if;
      end if;
   end process;

   --
   -- Load the upcoming row's map data (21 words) from SRAM when necessary.
   --
   load_map_row : process(reset, pxlClk, xIdx, yIdx, mapY)
   begin
      if(reset = '1') then
         loadIdx <= LOAD_ZERO;
         dReadEn <= '0';
         memAddr <= "ZZZZZZZZZZZZZZZZZZ";
      elsif(rising_edge(pxlClk)) then
         if(unsigned(yIdx) > unsigned(FRAME_BRK_END_ROW)) then -- display owns SRAM
            if((unsigned(xIdx) <= unsigned(LOAD_ROW_END))
                and ((mapY(4 downto 0) = "00000")
                        or (yIdx = FRAME_START_ROW))) then -- load a row
               dReadEn <= '1'; -- read SRAM
               if(xIdx = SXGA_ZERO) then  -- first cycle in row load
                  -- initialize the memory load address
                  memAddr(17 downto 14) <= "0000";
                  memAddr(13 downto 5)  <= mapY(13 downto 5);    -- use counter map row coordinate
                  memAddr(4 downto 0)   <= winPosX(12 downto 8); -- use window column coordinate
               elsif(xIdx = LOAD_ROW_END) then -- last cycle in row load
                  loadIdx <= LOAD_ZERO;            -- reset for next time
                  dReadEn <= '0';                  -- stop reading SRAM
                  memAddr <= "ZZZZZZZZZZZZZZZZZZ";
               elsif(xIdx(2 downto 0) = "110") then  -- sample SRAM map data
                  if(unsigned(loadIdx) < unsigned(LOAD_6)) then -- safety-check
                     rowData(to_integer(unsigned(loadIdx))) <= dData;
                  end if;
               elsif((xIdx(2 downto 0) = "111") 
                       and (loadIdx /= LOAD_5)) then -- move on to next word
                  loadIdx <= std_logic_vector(unsigned(loadIdx) + 1);
                  memAddr <= std_logic_vector(unsigned(memAddr) + 1);
               end if;
            end if;
         else -- physics engine currently owns SRAM
            dReadEn <= '0';
            memAddr <= "ZZZZZZZZZZZZZZZZZZ";
         end if;
      end if;
   end process;
   
   --
   -- Paint the SXGA pixels (1280 x 1024) from the SRAM block data w/ (8 x 8) pixles-per-block.
   --
   paint_pixels : process(reset, pxlClk, xIdx, yIdx, pixelX, pixelY, meatOffX, meatOffY,
                          rowData, bWord, readWordIdx, readBitIdxU, readBitIdxL, mapX, mapY,
                          pColIdx0, pColIdx1, pColIdx2, pColIdx3, airRow, saltRow, wallARow, wallBRow,
                          airColor, saltColor, wallAColor, wallBColor, mapX0, mapX1, mapX2, mapX3) -- hacked for sure..
   begin
   
      --
      -- combinational logic
      --
      meatUpperOffX <= std_logic_vector(unsigned(meatOffX) + 14); -- Meatboy's four corners
      meatLowerOffX <= std_logic_vector(unsigned(meatOffX) - 14);
      meatUpperOffY <= std_logic_vector(unsigned(meatOffY) + 14);
      meatLowerOffY <= std_logic_vector(unsigned(meatOffY) - 14);
      
      -- mapX/mapY to color palate indices
      mapX0 <= (mapX(4 downto 0) & "00");
      mapX1 <= (mapX(4 downto 0) & "01");
      mapX2 <= (mapX(4 downto 0) & "10");
      mapX3 <= (mapX(4 downto 0) & "11");
      pColIdx3(6 downto 0) <= std_logic_vector(unsigned(TEXTURE_MAX_IDX) - unsigned(mapX0));
      pColIdx2(6 downto 0) <= std_logic_vector(unsigned(TEXTURE_MAX_IDX) - unsigned(mapX1));
      pColIdx1(6 downto 0) <= std_logic_vector(unsigned(TEXTURE_MAX_IDX) - unsigned(mapX2));
      pColIdx0(6 downto 0) <= std_logic_vector(unsigned(TEXTURE_MAX_IDX) - unsigned(mapX3));
      airRow   <= airText(to_integer(unsigned(mapY(4 downto 0))));
      saltRow  <= saltText(to_integer(unsigned(mapY(4 downto 0))));
      wallARow <= wallAText(to_integer(unsigned(mapY(4 downto 0))));
      wallBRow <= wallBText(to_integer(unsigned(mapY(4 downto 0))));
      airColor(0)   <= airRow(to_integer(unsigned(pColIdx0)));
      airColor(1)   <= airRow(to_integer(unsigned(pColIdx1)));
      airColor(2)   <= airRow(to_integer(unsigned(pColIdx2)));
      airColor(3)   <= airRow(to_integer(unsigned(pColIdx3)));
      saltColor(0)  <= saltRow(to_integer(unsigned(pColIdx0)));
      saltColor(1)  <= saltRow(to_integer(unsigned(pColIdx1)));
      saltColor(2)  <= saltRow(to_integer(unsigned(pColIdx2)));
      saltColor(3)  <= saltRow(to_integer(unsigned(pColIdx3)));
      wallAColor(0) <= wallARow(to_integer(unsigned(pColIdx0)));
      wallAColor(1) <= wallARow(to_integer(unsigned(pColIdx1)));
      wallAColor(2) <= wallARow(to_integer(unsigned(pColIdx2)));
      wallAColor(3) <= wallARow(to_integer(unsigned(pColIdx3)));
      wallBColor(0) <= wallBRow(to_integer(unsigned(pColIdx0)));
      wallBColor(1) <= wallBRow(to_integer(unsigned(pColIdx1)));
      wallBColor(2) <= wallBRow(to_integer(unsigned(pColIdx2)));
      wallBColor(3) <= wallBRow(to_integer(unsigned(pColIdx3)));
      
      -- color palate index to color
      airPixelColor   <= palate(to_integer(unsigned(airColor)));
      saltPixelColor  <= palate(to_integer(unsigned(saltColor)));
      wallAPixelColor <= palate(to_integer(unsigned(wallAColor)));
      wallBPixelColor <= palate(to_integer(unsigned(wallBColor)));

      -- pixelX/pixelY to bData
      readBitIdxL(0) <= '0'; -- even
      readBitIdxU <= (readBitIdxL(3 downto 1) & '1'); -- odd (readBitIdxL + 1)
      if((unsigned(pixelX) < unsigned(SXGA_FRAME_COL_DIM))
               and (unsigned(pixelY) < unsigned(SXGA_FRAME_ROW_DIM))) then
         drawingFrame <= '1';
         if(unsigned(readWordIdx) < unsigned(LOAD_6)) then -- safety-check
            bWord <= rowData(to_integer(unsigned(readWordIdx)));
         else
            bWord <= "XXXXXXXXXXXXXXXX";
         end if;
         bData(1) <= bWord(to_integer(unsigned(readBitIdxU)));
         bData(0) <= bWord(to_integer(unsigned(readBitIdxL)));
      else
         drawingFrame <= '0';
         bWord <= "XXXXXXXXXXXXXXXX";
         bData <= "XX";
      end if;
      
      --
      -- sequential logic
      --
      if(reset = '1') then -- reset signal
         redReg   <= "0000000000";
         greenReg <= "0000000000";
         blueReg  <= "0000000000";
      elsif(rising_edge(pxlClk)) then
         if(drawingFrame = '1') then -- paint a pixel
            if(mapX(4 downto 0) = "11111") then -- about to load next block's data (2-bit)
               readBitIdxL(3 downto 1) <= std_logic_vector(unsigned(readBitIdxL(3 downto 1)) + 1);
               if((readBitIdxL(3 downto 1) = "111")
                     and (readWordIdx /= LOAD_5)) then -- about to move to next word (16-bit)
                  readWordIdx <= std_logic_vector(unsigned(readWordIdx) + 1);
               end if;
            end if;
            if((unsigned(pixelX) < unsigned(meatUpperOffX(10 downto 0))) 
               and (unsigned(pixelX) > unsigned(meatLowerOffX(10 downto 0)))
                and (unsigned(pixelY) < unsigned(meatUpperOffY(10 downto 0)))
                 and (unsigned(pixelY) > unsigned(meatLowerOffY(10 downto 0)))) then -- Meatboy color
               case meatDir is
                  when "00" =>
                     redReg   <= "1111111111"; -- Meatboy red
                     greenReg <= "0000111000";
                     blueReg  <= "0000000100";
                  when "01" =>
                     redReg   <= "1111111111"; -- Meatboy red
                     greenReg <= "0000111000";
                     blueReg  <= "0000000100";
                  when "10" =>
                     redReg   <= "0000000100"; -- Meatboy red
                     greenReg <= "1111111111";
                     blueReg  <= "0000000100";
                  when "11" =>
                     redReg   <= "1111111111"; -- Meatboy red
                     greenReg <= "0000000100";
                     blueReg  <= "1111111111";
               end case;
            elsif(bData = "00") then -- air
               redReg   <= airPixelColor(0);
               greenReg <= airPixelColor(1);
               blueReg  <= airPixelColor(2);
            elsif(bData = "01") then -- salt
               redReg   <= saltPixelColor(0);
               greenReg <= saltPixelColor(1);
               blueReg  <= saltPixelColor(2);
            elsif(bData = "10") then -- wall pattern 0
               redReg   <= wallAPixelColor(0);
               greenReg <= wallAPixelColor(1);
               blueReg  <= wallAPixelColor(2);
            elsif(bData = "11") then -- wall pattern 1
               redReg   <= wallBPixelColor(0);
               greenReg <= wallBPixelColor(1);
               blueReg  <= wallBPixelColor(2);
            end if;
         else -- not drawing frame
            readWordIdx <= "000"; -- reset the indices
            readBitIdxL(3 downto 1) <= winPosX(7 downto 5); -- get ready for offset start
         end if;
      end if;
   end process;
   
end Behavioral;      
