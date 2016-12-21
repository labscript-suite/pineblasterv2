/*
#######################################################################
#                                                                     #
# PineBlasterV2.pde                                                   #
#                                                                     #
# Copyright 2016, Philip Starkey                                      #
#                                                                     #
# Based on "BitBlaster"                                               #
#     Copyright 2015, Martijn Jasperse                                #
#     https://bitbucket.org/martijnj/bitblaster                       #
#                                                                     #
# Based on "pineblaster"                                              #
#     Copyright 2013, Christopher Billington                          #
#     https://bitbucket.org/labscript_suite/pineblaster               #
#                                                                     #
# This file is used to flash a Digilent ChipKIT Max32 or WiFire       #
# microcontroller prototyping board to create a PineBlasterV2         #
# (see https://bitbucket.org/labscript_suite/pineblasterv2).          #
# This file is licensed under the Simplified BSD License.             #
# See the license.txt file for the full license.                      #
#                                                                     #
#######################################################################
*/

#if defined(__PIC32MZXX__)
// number of instructions the chipkit wifire can hold
const unsigned int max_instructions = 64350; //8*7450;
#else
// number of instructions the chipkit MAX32 can hold
const unsigned int max_instructions = 15050;
#endif
int autostart;
unsigned int instructions[2*max_instructions + 6]; // 3 extra instructions (2 32-bit ints per instruction). two initial blank instructions (for the caching hack) and 1 for stop instruction at end
volatile unsigned int * resume_address = instructions;

#define MAX_STR 255
char cmdstr[MAX_STR+1] = "";

uint16_t enabled_channels = 0xFF;
int mode = 0;
volatile int hold_final = 1;
#define MIN_PULSE 6 //TODO: Fix this for bitblaster, define for pineblaster

#define DEBUG 1

void __attribute__((naked, nomips16)) Reset(void){
  // does a software reset of the CPU:
  // We have to do some kind of 'unlocking' sequence before we're allowed to reset:
  asm volatile ("reset: di\n\t");
  volatile int * p = (volatile int *)&RSWRST;
  SYSKEY = 0;
  SYSKEY = 0xAA996655;
  SYSKEY = 0x556699AA;

  // Perform the software reset
  RSWRSTSET=_RSWRST_SWRST_MASK;
  *p;

  // Wait for the rest to take place
  while(1);
}

void serialInterruptDuringRun(int ch){
  #if DEBUG==1
    Serial.println("DEBUG: resetting");
  #endif
  asm volatile ("j reset\n\t"); 
}


void start_clock(){
  Serial.println("ok");
  #if DEBUG==1
    Serial.println("DEBUG: attaching serial interrupt");
  #endif
  // Any serial communication will now reset the CPU:
  Serial.attachInterrupt(serialInterruptDuringRun);
  
  int incomplete = 1;
  int runcache = 1;
  while (incomplete==1){
    #if DEBUG==1
      Serial.println("DEBUG: calling run()");
    #endif
    run_clock(runcache);
    autostart = 0;
    runcache = 0;
    incomplete = (uint)resume_address != (uint)instructions;
  }
  // no longer reset on serial communication:
  Serial.detachInterrupt();
  // say that we're done!
  Serial.println("done");
}

void run_clock(int runcache){
  // Enable our hardware trigger, if we're doing a hardware triggered start:
  if (autostart==0){
    attachInterrupt(0,0,RISING);
  }

  #if defined(__PIC32MZXX__)  
    if (runcache==1)
    {
      asm volatile ("li $t7, 0x1\n\t");
    }
    else
    {
      asm volatile ("li $t7, 0x0\n\t");
    }
  #else
    // 32 bit mode, no prescaler:
    T2CON = 0x0008;
    OC2CON = 0x0000; 
    OC2CON = 0x0023; 
    OC2R = 0;
    PR2 = 0;
    TMR2 = 0;
    TMR3 = 0;
    asm volatile ("nop\n\t");
    T2CONSET = 0x8000; 
    OC2CONSET = 0x8000; 
  #endif

  
  // don't fill our branch delay slots with nops, thank you very much:
  asm volatile (".set noreorder\n\t":::"t0","t1","t2","t3","t4", "t5", "t6", "t7", "t8", "k0", "k1", "v0", "v1");
  #if defined(__PIC32MZXX__)
    // load the ram address of the output port into register $t0:
    asm volatile ("la $t0, LATE\n\t");
    // store enabled channels
    asm volatile ("la $t1, enabled_channels\n\t");
    asm volatile ("lhu $t1, 0($t1)\n\t");
  #else
    // load the ram address of PR2 into register $t0:
    asm volatile ("la $t0, PR2\n\t");
    // load the ram address of OC2R into register $t1:
    asm volatile ("la $t1, OC2R\n\t");
      // load the address of OC2CON into register $t7:
    asm volatile ("la $t7, OC2CON\n\t");
    // a small constant used for getting to the right part of the waveform:
    asm volatile ("addi $t8, $zero, 2\n\t");
  #endif
  // load the address of the instruction array into register $t2:
  asm volatile ("la $t2, resume_address\n\t");
  asm volatile ("lw $t2, 0($t2)\n\t");
  // load the half-period time into register $t3:
  asm volatile ("lw $t3, 0($t2)\n\t"); 
  // load the reps into register $t4:
  asm volatile ("lw $t4, 4($t2)\n\t"); 
  // load the the autostart flag into register $t5:
  asm volatile ("la $t5, autostart\n\t");
  asm volatile ("lw $t5, 0($t5)\n\t");
  // load the address of IPC0 into register $t6:
  asm volatile ("la $t6, IPC0\n\t");

  // TODO: can this be deleted?
  // Prepare registers for hardware triggering (makes the interrupt code faster):
  asm volatile ("li $k0, 0x101001\n\t"); // the status we need to write to acknowledge that we're servicing the interrupt
  asm volatile ("li $k1, 0x100003\n\t"); // The status we need to write to say we've finished the interrupt
  asm volatile ("la $v0, IFS0\n\t"); // load the address of IFS0
  asm volatile ("li $v1, 0x10088880\n\t"); // the value of IFSO we need to indicate we've serviced the interrupt

  // if we're set to autostart, jump right in:
  asm volatile ("bne $t5, $zero, start\n\t");
  asm volatile ("nop\n\t");
  
  // otherwise, wait for it...
  asm volatile ("wait\n\t");

  // TODO:
  //    * Does not detaching actually change anything?
  //    * Does the commented out code achieve the sam ething in less instructions?
  // once the wait is complete, detach the interrupt so future triggers do not 
  // slow down the execution
  detachInterrupt(0); 
//  IEC0bits.INT0IE  = 0;  
//  setIntPriority(0, 0, 0); // this will disable the interrupt
//  /* Compute the address of the interrupt priority control register used
//  ** by this interrupt vector
//  */
//  p32_regset * ipc = ((p32_regset *)&IPC0);
//  /* Set the interrupt privilege level and sub-privilege level
//  */
//  ipc->clr = 0x1F;
//  ipc->set = 0;
  
  // required nop because the asm for the detachInterrupt has a jump, which 
  // seems to execute the following asm instruction before jumping (much like
  // the branch instructions do. This nop ensures nothing critical starts 
  // before the detachment is finished
  asm volatile ("nop\n\t");

  #if defined(__PIC32MZXX__)
    // We:
    //   * have the first 2 instructions by full of 0's
    //   * jump to the low half of the wait loop (wait_loop2)
    //   *   before we get here, we store "1" in "$t7" (this will be used later)
    //   * because the reps is 0, this runs through into the low_and_load block of code
    //   * the low_and_load block loads the second instruction (as above, is 0)
    //   * this simulates an end of current run (or a wait)
    //   * we catch the fact that $t7 is 1 (see above) and jump back to wait_loop (the upper wait_loop in the "high" section)
    //   *   while branching we set $t7 to 0 so it doesn't get caught again
    //   * this executes the upper block (hopefully caching it) and then jumps to the low_and_load block (because reps is 0 still)
    //   * we then load in the first instruction and jump to "go_high" (which may be delayed slightly because we haven't cached it yet, but that's ok, it just delays the start very slightly!)
    // I think this will fill the cache with the asm instructions so execution is faster
    // Without this, we see the first clock tick of the first sequence be slower than it should be  
    asm volatile ("start: bne $t7, $zero, wait_loop2\n\t");
      asm volatile ("nop\n\t");
    
    //
    // Start of main execution loop
    //
    asm volatile ("high: sw $t1, 0($t0)\n\t");
    //iterate over the high half-period
    asm volatile ("wait_loop: bne $t3, $zero, wait_loop\n\t");
      asm volatile ("addi $t3, -1\n\t");
    // load the half-period again
    asm volatile ("lw $t3, 0($t2)\n\t");
    // nop's to balance out the loop (and make the length of the loop a nice number)
    asm volatile ("nop\n\t");
    asm volatile ("nop\n\t");
    asm volatile ("nop\n\t");
  
    // if this is the last "rep", then branch to the section that loads the next instruction
    asm volatile ("beq $t4, $zero, low_and_load\n\t");
      asm volatile("sw $zero, 0($t0)\n\t"); 
  
    // iterate over the low half-period
    asm volatile ("wait_loop2: bne $t3, $zero, wait_loop2\n\t");
      asm volatile ("addi $t3, -1\n\t");
    // load the half-period again
    asm volatile ("lw $t3, 0($t2)\n\t");
    // nop's to balance out the loop (and make the length of the loop a nice number)
    asm volatile ("nop\n\t");
    asm volatile ("nop\n\t");
  
    // branch to the top and decrease the "rep" counter
    // Note: This will always execute because if $t4==0 then we branch earlier
    //       Except, if we are precaching the asm instructions, in which case we roll right through this line
    asm volatile ("bne $t4, $zero, high\n\t");
      asm volatile ("addi $t4, -1\n\t");
  
    //
    //This section only runs if we are on the last "rep" of an instruction and need to load the next instruction
    //
    // increment the instruction pointer
    asm volatile ("low_and_load: addi $t2, 8\n\t"); 
    // iterate over the low half-period (from the previous instruction)
    asm volatile ("wait_loop3: bne $t3, $zero, wait_loop3\n\t");
      asm volatile ("addi $t3, -1\n\t");
    // load the half-period again (for the next instruction)
    asm volatile ("lw $t3, 0($t2)\n\t");
    // nop's to balance out the loop (and make the length of the loop a nice number)
    asm volatile ("nop\n\t");
    // branch if the half-period is not zero (and load the number of "reps")
    asm volatile ("bne $t3, $zero, high\n\t");
      asm volatile ("lw $t4, 4($t2)\n\t");
  
    // branch back to first wait loop if we are precaching instructions still
    asm volatile ("bne $t7, $zero, wait_loop\n\t");
      asm volatile ("li $t7, 0x0\n\t");
    //
    // END OF PRECACHED ASM INSTRUCTIONS
    //
  #else
    // We need to get up to the right part of the waveform, we don't want the initial digital low.
    // We want to start with a digital high. So let's set the period to some small constant, and wait
    // until it is about to go high, switching the period to our first instruction at just the right moment:
    asm volatile ("start: sw $t8, 0($t0)\n\t"); 
    asm volatile ("sw $t8, 0($t1)\n\t");
  
    // update the period of the output:
    asm volatile ("top: sw $t3, 0($t0)\n\t"); 
    asm volatile ("sw $t3, 0($t1)\n\t");
    // wiat for the delay time:
    asm volatile ("wait_loop: bne $t4, $zero, wait_loop\n\t");
    asm volatile ("addi $t4, -1\n\t");
    // load the next half-period in:
    asm volatile ("lw $t3, 8($t2)\n\t");
    // increment our instruction pointer:
    asm volatile ("addi $t2, 8\n\t");
    // go to the top of the loop if it's not a stop instruction:
    asm volatile ("bne $t3, $zero, top\n\t");
    //load the the next delay time in:
    asm volatile ("lw $t4, 4($t2)\n\t"); 
    
    // We got a stop instruction (indicated by half_period==0). Disable output:
    asm volatile ("sw $zero, 0($t7)\n\t");
  #endif

  // We might be stopping for good, or we might be resuming after a hardware trigger.
  // In case of the latter (indicated by reps != 0), 
  // save the next instruction pointer so we can resume from it:
  asm volatile ("la $t8, resume_address");
  asm volatile ("la $t7, instructions");
  asm volatile ("beq $t4, $zero, end\n\t");
  asm volatile ("sw $t7, 0($t8)\n\t");
  // increment our instruction pointer:
  asm volatile ("addi $t2, 8\n\t");
  asm volatile ("sw $t2, 0($t8)\n\t");
  asm volatile ("end:\n\t");
}

void start_bitblaster(int mode)
{
  int nloops;
  // operation depends on value of "mode":
  //   0 = hardware triggered, single run
  //   1 = software triggered, single run
  //   2 = hardware triggered, repeated infinitely
  //   3 = software triggered, repeated infinitely
  if (instruction_empty(0) == 0) {
    Serial.println("empty sequence");
    return;
  }
  Serial.println("ok");
  // Any serial communication will now reset the CPU:
  // do the magic
  for (nloops = 0; ; ++nloops) {
    Serial.attachInterrupt(serialInterruptDuringRun);
    digitalWrite(PIN_LED2,HIGH);
    LATASET = 0x1;      // indicate the run has begun
    run_bitblaster(mode & 0x1);    // do the work
    LATACLR = 0x1;      // indicate the run has ended
    WDTCONSET = 0x1;    // set watchdog WDTCLR bit
    digitalWrite(PIN_LED2,LOW);
    // no longer reset on serial communication:
    Serial.detachInterrupt();
    if ((mode & 0x2) == 0) break;
    Serial.println(nloops);
  }
  
  
  Serial.println("done");
}

void run_bitblaster(int autostart)
{
  // set cache bit
  asm volatile ("li $t5, 0x1\n\t");
  
  // tell the assembler to do exactly what we say (make sure to undo later)
  asm volatile (".set noreorder\n\t");
  // load the address of the output buffer into register $t0
  #if defined(__PIC32MZXX__)  
    asm volatile ("la $t0, LATE\n\t");
  #else
    asm volatile ("la $t0, LATB\n\t");
  #endif
  asm volatile ("la $t1, LATAINV\n\t");
  asm volatile ("li $t8, 0x4\n\t");
  // load the instructions array into register $t2
  asm volatile ("la $t2, instructions\n\t");
  // load the time into register $t3
  asm volatile ("lhu $t3, 2($t2)\n\t"); 
  // load the port value into register $t4
  asm volatile ("lhu $t4, 0($t2)\n\t");   
  // store the number to count down to in the loop (0 for the cache instruction and then set to 1 later)
  //asm volatile ("li $s6, 0\n\t");
  
  // if not autostart, wait for trigger
  if (!autostart) {
    // high-level activation of interrupt
    LATASET = 0x2;                           // indicate we're waiting for a trigger
    attachInterrupt(0, 0, RISING);           // attach the interrupt handler
    // low-level overrides for fast triggering
    asm volatile ("li $k0, 0x101001\n\t");   // the status we need to write to acknowledge that we're servicing the interrupt
    asm volatile ("li $k1, 0x100003\n\t");   // the status we need to write to say we've finished the interrupt
    asm volatile ("la $v0, IFS0\n\t");       // load the address of IFS0
    asm volatile ("li $v1, 0x10088880\n\t"); // the value of IFSO we need to indicate we've serviced the interrupt
    // wait until the trigger happens
    asm volatile ("li $t7, 0x2\n\t");
    asm volatile ("trig_wait: wait\n\t");    // put the cpu into wait mode
    // TODO:
    //    * Does not detaching actually change anything?
    //    * Does the commented out code achieve the sam ething in less instructions?
    // once the wait is complete, detach the interrupt so future triggers do not 
    // slow down the execution
    detachInterrupt(0); 
    //  IEC0bits.INT0IE  = 0;  
    //  setIntPriority(0, 0, 0); // this will disable the interrupt
    //  /* Compute the address of the interrupt priority control register used
    //  ** by this interrupt vector
    //  */
    //  p32_regset * ipc = ((p32_regset *)&IPC0);
    //  /* Set the interrupt privilege level and sub-privilege level
    //  */
    //  ipc->clr = 0x1F;
    //  ipc->set = 0;
    
    // required nop because the asm for the detachInterrupt has a jump, which 
    // seems to execute the following asm instruction before jumping (much like
    // the branch instructions do. This nop ensures nothing critical starts 
    // before the detachment is finished
    asm volatile ("nop\n\t");
    
    asm volatile ("sw $t7, 0($t1)\n\t");     // equivalent to LATAINV = 0x2

    // jump into the caching point
    asm volatile ("bne $t5, $zero, wait_loop_bits\n\t");
       asm volatile ("nop\n\t");
  } else
    autostart = 0;  // we autostart this one, but not next time (i.e. for "hold and wait" instruction)
  
  // ***** MAKE THE MAGIC HAPPEN *****
  // NB: modifying code here requires updating MIN_PULSE (= #commands / 2)
  // ---
  // registers already be loaded, so write straight to PORTB
  asm volatile ("output: sw $t4, 0($t0)\n\t");
  // blink the indicator (equivalent to LATAINV = 0x4)
  asm volatile ("sw $t8, 0($t1)\n\t");
  // wait for the delay time
  asm volatile ("wait_loop_bits: bne $t3, $zero, wait_loop_bits\n\t");
    asm volatile ("addiu $t3, -1\n\t");  // decrement within branch slot
  // increment our instruction pointer
  asm volatile ("addi $t2, 4\n\t");
  // load the time in
  asm volatile ("lhu $t3, 2($t2)\n\t");
  // repeat the loop unless a stop instruction
  asm volatile ("bne $t3, $zero, output\n\t");
    // load the the next delay time in:
    asm volatile ("lhu $t4, 0($t2)\n\t"); // load value within branch slot

  // branch back to top of instruction loop if we have just finished precaching the asm instructions
  //asm volatile ("li $s6, 1\n\t");
  asm volatile ("bne $t5, $zero, output\n\t");
    asm volatile ("li $t5, 0x0\n\t");
  
  // *** stop instruction ***
  // if the value is also zero, it's all over!
  asm volatile ("beq $t4, $zero, end_bits\n\t");
  // load the next values (note: don't care about branch slot this time)
  asm volatile ("lhu $t3, 2($t2)\n\t");
  asm volatile ("lhu $t4, 0($t2)\n\t");
  // TODO: if we don't need to detach above, then we don't need to reattach either! Let's check it out sometime
  attachInterrupt(0, 0, RISING);           // attach the interrupt handler
  // wait for hardware trig 
  asm volatile ("j trig_wait\n\t");
  
  // *** all done ***
  asm volatile ("end_bits: nop\n\t");
  #if defined(__PIC32MZXX__)
    if (!hold_final) LATE = 0x0;
  #else
    if (!hold_final) LATB = 0x0;
  #endif
  
  // CRITICAL: undo the "noreorder" command (see issue #3)
  asm volatile (".set reorder\n\t");
}

void readline( ) {
  // get data off the serial line
  int i = 0;
  while (i < MAX_STR)  // failsafe to prevent overrun
  {
    // wait til data arrives
    if (!Serial.available()) continue;
    // read a character
    char c = Serial.read();
    if ((c == '\r')||(c == '\n'))
      // ignore at string start
      if (i==0) continue; else break;
    cmdstr[i] = c;
    ++i;
  }
  // null-terminate
  cmdstr[i] = '\0';
}


void setup(){

  // initial setup of instructions for mode=0
  instructions[0] = 0;
  instructions[1] = 0;
  instructions[2] = 0;
  instructions[3] = 0;
  
  // configure the digital ports
  #if defined(__PIC32MZXX__)  
    TRISE = 0;      // set PORTE to become entirely outputs
    LATE = 0;       // set PORTE to LO
  #else
    TRISB = 0;      // set PORTB to become entirely outputs
    LATB = 0;       // set PORTB to LO
  #endif
  TRISACLR = 0x7; // set bits 0--2 of PORTA to be outputs
  LATACLR = 0x7;  // set those bits to LO
  
  // setup serial connection
  Serial.begin(115200);
  
  // Disable our hardware trigger until it is needed:
  IPC0 = 0;
  
  // configure status LEDs
  pinMode(PIN_LED1,OUTPUT);
  digitalWrite(PIN_LED1,HIGH);
  pinMode(PIN_LED2,OUTPUT);
  digitalWrite(PIN_LED2,LOW);

  // Announce we are ready!
  Serial.println("ready");
}

int set_bits(int i, uint32_t val, uint32_t ts)
{
  #if defined(__PIC32MZXX__)    
    i++; // increment i as the first instruction should always be 0 (used to precache the asm instructions)
  #endif
  if (i >= (2*max_instructions))
    Serial.println("invalid address");
  else if (ts == 0) {
    // either a stop or a wait instruction
    instructions[i] = 0;
    if ((val == 0)||(val == 0xFFFF)) {
      // stop or wait instruction
      instructions[i] = val;
      return 0;
    }
    Serial.println("invalid stop instruction");
  }
  else if (ts < MIN_PULSE)
    Serial.println("timestep too short");
  else if (ts > 0xFFFF)
    Serial.println("timestep too long");
  else if (val > 0xFFFF)
    Serial.println("invalid value");
  else {
    // it's a regular instruction! HI word is the timesteps, LO word is the port value
    ts -= MIN_PULSE-1;    // account for overhead
    instructions[i] = (ts<<16)|val;
    return 0;
  }
  return 1;
}

int get_bits(int i, uint32_t *val, uint32_t *len)
{
  #if defined(__PIC32MZXX__)  
    i++; // increment i as the first instruction should always be 0 (used to precache the asm instructions)
  #endif

  if (!val || !len)
    return -1;
  if (i >= (2*max_instructions)) {
    Serial.println("invalid address");
    return 1;
  }
  *len = instructions[i] >> 16;     // high-word is timesteps
  if (*len) *len += MIN_PULSE-1;    // correct for overhead
  *val = instructions[i] & 0xFFFF;  // low-word is data
  return 0;
}

int instruction_empty(int i)
{
  #if defined(__PIC32MZXX__)  
    return (instructions[i+1]!=0)?1:0;
  #else
    return (instructions[i]!=0)?1:0;
  #endif
}

void loop(){
  readline();
  if (strcmp(cmdstr, "hello") == 0){
    Serial.println("hello");
  }
  else if ((strcmp(cmdstr, "go high") == 0)||(strncmp(cmdstr, "hi", 2) == 0)) {
    #if defined(__PIC32MZXX__)  
      // write entire port HI
      LATE = 0xFFFF;
    #else
      if (mode == 0)
      {
        digitalWrite(5,HIGH);
      }
      else
      {
        // write entire port HI
        LATB = 0xFFFF;
      }
    #endif
    Serial.println("ok");
  }
  else if ((strcmp(cmdstr, "go low") == 0)||(strncmp(cmdstr, "lo", 2) == 0)) {
    #if defined(__PIC32MZXX__)  
      // write entire port LO
      LATE = 0;
    #else
      if (mode == 0)
      {
        digitalWrite(5,LOW);
      }
      else
      {
        // write entire port LO
        LATB = 0;
      }
    #endif
    Serial.println("ok");
  }
  else if (strcmp(cmdstr, "reset") == 0){
    Serial.println("ok");
    delayMicroseconds(1000);  
    asm volatile ("nop\n\t");
    asm volatile ("j reset\n\t");
  }
  else if (strcmp(cmdstr, "len") == 0) {
    int max_instr = (mode==0)?max_instructions:2*max_instructions;
    for (int i = 0; i < max_instr; ++i)
      if (!instruction_empty(i))  // stop instruction
      {
        Serial.println(i+1);
        break;
      }
  }
  else if (strncmp(cmdstr, "setmode ", 8) == 0){
    unsigned int newmode;
    int parsed = sscanf(cmdstr,"%*s %u",&newmode);
    if ((parsed < 1) || (newmode != 0 and newmode != 1)){
        Serial.println("invalid request");
    }
    else
    {
      // reset instruction array
      for (int i = 0; i < ((2*max_instructions)+6); ++i)
      {
        instructions[i] = 0;
      }
      
      mode = newmode;
      Serial.println("ok");
    }
  }
  else if (mode == 0) //pineblaster (clk mode)
  {
    if (strcmp(cmdstr, "hwstart") == 0){
      autostart = 0;
      start_clock();
    }
    else if ((strcmp(cmdstr, "start") == 0) || (strcmp(cmdstr, "") == 0)){
      autostart = 1;
      start_clock();
    }
    else if (strncmp(cmdstr, "set ", 4) == 0){
      unsigned int addr;
      unsigned int half_period;
      unsigned int reps;
      int parsed = sscanf(cmdstr,"%*s %u %u %u",&addr, &half_period, &reps);
      if (parsed < 3){
          Serial.println("invalid request");
      }
      else if (addr >= max_instructions){
        Serial.println("invalid address");
      }
      else if (half_period == 0){
        #if defined(__PIC32MZXX__)
          addr = addr+2; // account for the two cache instructions (or 4 entries in the array) that must stay 0
        #endif
        // This indicates either a stop or a wait instruction
        instructions[2*addr] = 0;
        if (reps == 0){
          // It's a stop instruction
          instructions[2*addr+1] = 0;
          Serial.println("ok");
        }
        else if (reps == 1){
          // It's a wait instruction:
          instructions[2*addr+1] = 1;
          Serial.println("ok");
        }
        else{
          Serial.println("invalid request");
        }
      }
      else if (half_period < 5){
        Serial.println("half-period too short");
      }
      else if (reps < 1){
        Serial.println("reps must be at least one");
      }
      else{
        instructions[2*addr] = half_period - 4;
        instructions[2*addr+1] = reps - 1;
        Serial.println("ok");
      }
    }
    else{
      Serial.println("invalid request");
    }
  }
  else if (mode == 1) //bitblaster mode
  {
    
    uint32_t i, val, ts; //TODO: clean this up
    if (strcmp(cmdstr, "hwstart") == 0)
      start_bitblaster(0);
    else if (strcmp(cmdstr, "hwrepeat") == 0)
      start_bitblaster(2);
    else if (strcmp(cmdstr, "start") == 0)
      start_bitblaster(1);
    else if (strcmp(cmdstr, "repeat") == 0)
      start_bitblaster(3);
    else if (strncmp(cmdstr, "load ", 5) == 0)
    {
      // expect a HEX string of length 4N containing all the instructions (limited by buffer size)
      char *p = cmdstr+5;
      int success = 1;
      for (i=0; *p; p+=8, ++i)
      {
        // is it a continuation?
        if ((p[0] == '+') && (p[1] == '\0')) {
          readline();
          p = cmdstr;
        }
        // parse the instruction
        if (sscanf(p, "%04x%04x", &val, &ts) != 2) {
          Serial.println("invalid instruction");
          success = 0;
          break;
        }
        // load it into the array
        if (set_bits(i,val,ts)) {
          success = 0;
          break;
        }
      }
      // terminate the sequence
      if (success)
        set_bits(i,0,0); // append STOP just in case
      else
        set_bits(0,0,0);  // wipe the list
      // respond to host
      if (success)
        Serial.println("ok");
    }
    else if (strcmp(cmdstr, "dump") == 0)
    {
      // dump instructions array as a HEX string
      char buffer[10];
      for (i=0; instruction_empty(i); ++i)
      {
        if (get_bits(i,&val,&ts)) break;
        sprintf(buffer, "%04X%04X", val, ts);
        Serial.print(buffer);
      }
      if (i==0)
        Serial.println("no instructions");
      else
        Serial.println("");
    }
    else if (strncmp(cmdstr, "set ", 4) == 0)
    {
      byte nparsed = sscanf(cmdstr, "%*s %u %x %u", &i, &val, &ts);
      if (nparsed < 3)
        Serial.println("invalid request");
      else
        if (!set_bits(i, val, ts))
          Serial.println("ok");
    }
    else if (strncmp(cmdstr, "get ", 4) == 0) {
      uint32_t i;
      if (sscanf(cmdstr, "%*s %u", &i) != 1)
        Serial.println("invalid request");
      else {
        get_bits(i,&val,&ts);
        Serial.print(val,HEX);
        Serial.print(" ");
        Serial.println(ts);
      }
    }
    else{
      Serial.println("invalid request");
    }
  }
  
}


