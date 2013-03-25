import os
import sys
import re 

#
# global 2D byte array
#
WIDTH = 256
HEIGHT = 512
ram = []

byte = [0,0]

#
# print help message
#
def printHelp():
   print "\nAltera Meatboy HD Map Data Generator:\n"
   print " Input an ASCII list of base-10 quintuples (one per line) whose internal"
   print " members are separated by any non-digit(s), in the following order:"
   print "   (rectBlockType, topLeftX, topLeftY, bottomRightX, bottomRightY)."
   print "\n   Input Format:"
   print "    >> 2,(0,0),(10,56)         # example line-format"
   print "    >> ## Lead with a '#' to comment a line out."
   print "    >> 0,(5,5),(18,156)        // Or append comments however you like.."
   print "    >>   3-191-201-199-259...  # Use any format within the constraints."
   print "    >> # An overlapping rectangle clobbers previous block-data"
   print "    >> # in line order.."
   print "    >> 1,2,3,4,5 :)"
   print "\n   --(32 x 32) Block Types:  air = 0, salt = 1, wallA = 2, wallB = 3."
   print "       Every block is air by default, except outside 2-blocks are wallA."
   print "   --X/Y-Bounds:  [x,y] = [0,0] (top-left) to [255, 511] (bottom-right).\n"
   
#
# Process input file, updating internal array. Returns true iff success.
#
def processInput(file):

   retVal = False
   lineNum = 0
   
   while(True):
      
      # read next line
      lineNum += 1 # move to next line (1-indexed)
      string = file.readline()
      
      # check for EOF
      if(len(string) == 0):
         print "Reached EOF at line %d." %(lineNum)
         retVal = True
         break   # success
      
      # check for leading comment
      if(re.match(r"\s*\#", string)):
         continue    # skip a lead-commented line
      
      # attempt to collect 5-element decimal vector
      qMatch = re.match(r"\D*(\d+)\D+(\d+)\D+(\d+)\D+(\d+)\D+(\d+)", string)
      if(qMatch):
         numMatches = qMatch.lastindex
      else:
         numMatches = 0
      
      if(numMatches == 5): # line has data--collect and validate it
      
         bType = int(qMatch.group(1))
         if(bType > 3):
            # invalid block type
            print "ERROR: Invalid block type of %d at line %d." %(bType, lineNum)
            break # failure
            
         bTopLeftX = int(qMatch.group(2))
         if((bTopLeftX < 0) or (bTopLeftX >= WIDTH)):
            # invalid x-coordinate
            print "ERROR: Invalid top-left x-coordinate at line %d." %(lineNum)
            break #failure
            
         bTopLeftY = int(qMatch.group(3))
         if((bTopLeftY < 0) or (bTopLeftY >= HEIGHT)):
            # invalid y-coordinate
            print "ERROR: Invalid top-left y-coordinate (%d) at line %d." %(bTopLeftY, lineNum)
            break #failure
            
         bBottomRightX = int(qMatch.group(4))
         if((bBottomRightX < 0) or (bBottomRightX >= WIDTH)):
            # invalid x-coordinate
            print "ERROR: Invalid bottom-right x-coordinate at line %d." %(lineNum)
            break #failure
            
         bBottomRightY = int(qMatch.group(5))
         if((bBottomRightY < 0) or (bBottomRightY >= HEIGHT)):
            # invalid y-coordinate
            print "ERROR: Invalid bottom-right y-coordinate at line %d." %(lineNum)
            break #failure
            
         if((bTopLeftX > bBottomRightX) or (bTopLeftY > bBottomRightY)):
            # invalid (top-left, bottom-right) pair
            print "ERROR: Invalid top-left/bottom-right pair at line %d." %(lineNum)
            break #failure
            
         # write the rectangle data into the internal array
         for yIdx in range(bTopLeftY, bBottomRightY + 1):
            for xIdx in range(bTopLeftX, bBottomRightX + 1):
               ram[(yIdx * WIDTH) + xIdx] = bType
         
      elif(numMatches == 0):  # valid line lacking any digits
         continue # skip line
      
      else:                   # invalid line
         print "ERROR: Found %d decimal entries at line %d." %(numMatches, lineNum)
         print "       Exactly 5 decimal (base-10) entries are required."
         break # failure
         
   return retVal
   
#
# Sanity check on the internal array generated from the input text file.
#
def validateArray():

   for yIdx in range(HEIGHT):
   
      for xIdx in range(WIDTH):
      
         bData = ram[(yIdx * WIDTH) + xIdx]
         
         if(bData > 0x3):
            #invalid array data => internal bug
            print "ERROR: Invalid array data at (%d, %d)!\n" %(xIdx, yIdx)
            return False # failure
            
         if(((yIdx <= 1) or (yIdx >= 510) or (xIdx <= 1) or (xIdx >= 254)) 
                  and (bData == 0)):
            # invalid boarder
            print "ERROR: Outside boarder broken by air at block (%d, %d)." %(xIdx, yIdx)
            return False # failure

   return True # success

#
# Write the output ram byte file from the internal array.
#
def writeOutput(file):

   for yIdx in range(HEIGHT):
      for xIdx in range(WIDTH / 8):
         for byteIdx in range(2):
         
            byte[byteIdx] = 0
            
            for blockIdx in range(4):
            
               bData = ram[(yIdx * WIDTH) + (xIdx * 8) + (byteIdx * 4) + blockIdx]
               byte[byteIdx] |= (bData << (blockIdx * 2))
         
         # write 16-bit word in proper byte-order
         bString = "%c%c" %(byte[0], byte[1])
         #print bString
         file.write(bString)

#
# Initialize the internal map array with the wallA boarder (2-blocks thick) and air center.
#
def initMapArray():

   for yIdx in range(HEIGHT):
      for xIdx in range(WIDTH):
         if((yIdx <= 1) or (yIdx >= 510) or (xIdx <= 1) or (xIdx >= 254)):
            ram.append(2) # wallA boarder
         else:
            ram.append(0) # default air



######################################## MAIN ######################################## 
if(__name__ == "__main__"):
   
   # print default help-message
   printHelp()
   
   # validate argument count
   argc = len(sys.argv)
   if(argc != 3):
      print "ERROR: Invalid args. Usage:  map_builder.py <in_fname> <out_fname.ram>"
      sys.exit(0); # early return
   
   # open the input and output files
   fIn = open(sys.argv[1], 'r')
   fOut = open(sys.argv[2], 'wb') # binary mode
   
   # initialize output array
   initMapArray()
   
   # read every line in the input file
   success = processInput(fIn)
   
   # validate that output array boarder is maintained, and internal sanity check
   if(success):
      success = validateArray()
   
   # write array to output RAM byte file
   if(success):
      writeOutput(fOut)
   
   # clean up
   fIn.close()
   fOut.close()
   if(success):
      print "\nAltera Meatboy HD Map Data Generator Success."
   else:
      os.remove(sys.argv[2])
      print "\nAltera Meatboy HD Map Data Generator Failure." 
   