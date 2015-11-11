/*
----------------------------------------------------------------------
BITBLASTER :: simple 16-channel digital output with chipKIT
Copyright 2015, Martijn Jasperse
https://bitbucket.org/martijnj/bitblaster
----------------------------------------------------------------------
Based on "PineBlaster" by Christopher Billington,
https://bitbucket.org/labscript_suite/pineblaster
----------------------------------------------------------------------
*/
#include <plib.h>

// do we want to hold the final instruction or not?
#define HOLD_FINAL_INSTRUCTION  1

// what's the RAM-limited number of instructions we can store?
#define MAX_INSTR 30000
// a big array
uint32_t instructions[MAX_INSTR + 1];

uint32_t nloops = 0;

// what's the shortest pulse we can execute?
#define MIN_PULSE 6

volatile int reset_on_serial = 0;

#define MAX_STR 64
char cmdstr[MAX_STR+1] = "";

void __attribute__((naked, at_vector(3), nomips16)) ExtInt0Handler(void)
{
  // acknowledge that we're starting the interrupt handler
  asm volatile ("mtc0 $k0, $12\n\t");
  // set IPC0 to disable this interrupt
  asm volatile ("sw $zero, 0($t6)\n\t");
  // set IFSO to indicate that the interrupt has been handled
  asm volatile ("sw $v1, 0($v0)\n\t");
  // set status to indicate the end
  asm volatile ("mtc0 $k1, $12\n\t");
  // return
  asm volatile ("eret\n\t");
}

void __attribute__((naked, at_vector(24), nomips16)) IntSer0Handler(void)
{
  // read in the address, then value of "reset_on_serial"
  asm volatile ("la $k0, reset_on_serial\n\t");
  asm volatile ("lw $k0, 0($k0)\n\t");
  // if it's zero, exec the "usual" serial handler
  asm volatile ("beq $k0, $zero, IntSer0Handler\n\t");
  asm volatile ("nop\n\t");  // branch slot nop
  // serial comms means interrupt execution, so do a reset!
  asm volatile ("j reset\n\t");
}

void __attribute__((naked, nomips16)) IntReset(void)
{
  // we have to do some kind of 'unlocking' sequence before we're allowed to reset:
  asm volatile ("reset: di\n\t");
  asm volatile ("la $k0, SYSKEY\n\t");
  asm volatile ("li $v0, 0xAA996655\n\t");
  asm volatile ("li $v1, 0x556699AA\n\t");
  // Have to write these two keys to SYSKEY in two back to back instructions to 'unlock' the system:
  asm volatile ("sw $v0, 0($k0)\n\t");
  asm volatile ("sw $v1, 0($k0)\n\t");
  // ok, now we can reset
  asm volatile ("la $k0, RSWRST\n\t");
  asm volatile ("li $v0, 1\n\t");
  asm volatile ("sw $v0, 0($k0)\n\t");
  // execute the reset by reading the register back in
  asm volatile ("lw $v0, 0($k0)");
  // wait for the end to come:
  asm volatile ("seeya: j seeya");
}

void start(int mode)
{
  // operation depends on value of "mode":
  //   0 = hardware triggered, single run
  //   1 = software triggered, single run
  //   2 = hardware triggered, repeated infinitely
  //   3 = software triggered, repeated infinitely
  Serial.println("ok");
  // set serial comms to reset the CPU
  reset_on_serial = 1;
  // do the magic
  nloops = 0;
  digitalWrite(PIN_LED2,HIGH);
  do {
    LATASET = 0x1;      // indicate the run has begun
    run(mode & 1);
    LATACLR = 0x1;      // indicate the run has ended
    WDTCONSET = 0x1;    // set watchdog WDTCLR bit
    ++nloops;
  } while (mode & 2);   // repeat run?
  digitalWrite(PIN_LED2,LOW);
  // do not reset on serial
  reset_on_serial = 0;
  Serial.println("done");
}

int run(int autostart)
{
  // load the address of the output buffer into register $t0
  asm volatile ("la $t0, LATB\n\t");
  asm volatile ("la $t1, LATAINV\n\t");
  asm volatile ("li $t8, 4\n\t");
  // load the instructions array into register $t2
  asm volatile ("la $t2, instructions\n\t");
  // load the time into register $t3
  asm volatile ("lh $t3, 2($t2)\n\t"); 
  // load the port value into register $t4
  asm volatile ("lh $t4, 0($t2)\n\t"); 
  // load the address of IPC0 into register $t6
  asm volatile ("la $t6, IPC0\n\t");
  
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
    asm volatile ("lw $t7, 0($t1)");         // equivalent to LATAINV = 0x2
  } else
    autostart = 0;  // we autostart this one, but not next time
  
  // ***** MAKE THE MAGIC HAPPEN *****
  // registers already be loaded, so write straight to PORTB
  asm volatile ("output: sw $t4, 0($t0)\n\t");
  // a nop to make the minimum pulse time an integer number of instructions
  //asm volatile ("nop\n\t");
  // blink the indicator (equivalent to LATAINV = 0x4)
  asm volatile ("lw $t8, 0($t1)");
  // wait for the delay time
  asm volatile ("wait_loop: bne $t3, $zero, wait_loop\n\t");
    asm volatile ("addiu $t3, -1\n\t");  // decrement within branch slot
  // increment our instruction pointer
  asm volatile ("addi $t2, 4\n\t");
  // load the time in
  asm volatile ("lh $t3, 2($t2)\n\t");
  // repeat the loop unless a stop instruction
  asm volatile ("bne $t3, $zero, output\n\t");
    // load the the next delay time in:
    asm volatile ("lh $t4, 0($t2)\n\t"); // load value within branch slot
  
  // *** stop instruction ***
  // if the value is also zero, it's all over!
  asm volatile ("beq $t4, $zero, end\n\t");
  // load the next values (note: don't care about branch slot this time)
  asm volatile ("lh $t3, 2($t2)\n\t");
  asm volatile ("lh $t4, 0($t2)\n\t");
  // wait for hardware trig 
  asm volatile ("j trig_wait\n\t");
  
  // *** all done ***
#if HOLD_FINAL_INSTRUCTION
  asm volatile ("end: nop\n\t");
#else
  asm volatile ("end: sw $zero, 0($t0)\n\t");
#endif
}

void readline( ) {
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

void setup( ) {
  // disable the hardware trigger (for now)
  IPC0 = 0;
  // configure the digital ports
  TRISB = 0;      // set PORTB to become entirely outputs
  LATB = 0;       // set PORTB to LO
  TRISACLR = 0x7; // set bits 0 and 1 of PORTA to be outputs
  LATACLR = 0x7;  // set those bits to LO
  // start the serial interface
  Serial.begin(57600);
  Serial.println("ready");
  // light up the LED
  pinMode(PIN_LED1,OUTPUT);
  digitalWrite(PIN_LED1,HIGH);
  pinMode(PIN_LED2,OUTPUT);
  digitalWrite(PIN_LED2,LOW);
}

int set(int i, uint32_t val, uint32_t ts)
{
  if (i >= MAX_INSTR)
    Serial.println("invalid address");
  else if (ts == 0) {
    // either a stop or a wait instruction
    instructions[i] = 0;
    if (val == 0) {
      // stop instruction
      instructions[i] = 0;
      return 0;
    } else if (val == 1) {
      // wait instruction:
      instructions[i] = 0x00FF;
      return 0;
    } else
      Serial.println("invalid stop instruction");
  }
  else if (ts < MIN_PULSE)
    Serial.println("timestep too short");
  else if (ts > 65535)
    Serial.println("timestep too long");
  else if (val > 65535)
    Serial.println("invalid value");
  else {
    // it's a regular instruction! HI word is the timesteps, LO word is the port value
    ts -= MIN_PULSE-1;    // account for overhead
    instructions[i] = (ts<<16)|val;
    return 0;
  }
  return 1;
}

int get(int i, uint32_t *val, uint32_t *len)
{
  if (!val || !len)
    return -1;
  if (i >= MAX_INSTR) {
    Serial.println("invalid address");
    return 1;
  }
  *len = instructions[i] >> 16;   // high-word is timesteps
  if (*len) *len += MIN_PULSE-1;  // correct for overhead
  *val = instructions[i] & 0xFF;  // low-word is data
  return 0;
}

void loop( ) {
  uint32_t i, val, ts;
  // wait for a command
  readline();
  // check what the command was
  if (strcmp(cmdstr, "hello") == 0)
    Serial.println("hello");
  else if (strcmp(cmdstr, "hwstart") == 0)
    start(0);
  else if (strcmp(cmdstr, "hwrepeat") == 0)
    start(2);
  else if (strcmp(cmdstr, "start") == 0)
    start(1);
  else if (strcmp(cmdstr, "repeat") == 0)
    start(3);
  else if (strncmp(cmdstr, "load ", 5) == 0)
  {
    // expect a HEX string of length 4N containing all the instructions (limited by buffer size)
    char *p = cmdstr+5;
    int success = 1;
    for (i=0; *p; p+=4, ++i)
    {
      // parse the instruction
      if (sscanf(p, "%02x%02x", &val, &ts) != 2) {
        Serial.println("invalid instruction");
        success = 0;
        break;
      }
      // load it into the array
      if (set(i,val,ts)) {
        success = 0;
        break;
      }
    }
    // terminate the sequence
    if (success)
      instructions[i] = 0;  // append STOP just in case
    else
      instructions[0] = 0;  // wipe the list
    // respond to host
    if (success)
      Serial.println("ok");
  }
  else if (strcmp(cmdstr, "dump") == 0)
  {
    // dump instructions array as a HEX string
    char buffer[5];
    for (i=0; instructions[i]; ++i)
    {
      if (get(i,&val,&ts)) break;
      sprintf(buffer, "%02X%02X", val, ts);
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
      if (!set(i, val, ts))
        Serial.println("ok");
  }
  else if (strncmp(cmdstr, "get ", 4) == 0) {
    uint32_t i;
    if (sscanf(cmdstr, "%*s %u", &i) != 1)
      Serial.println("invalid request");
    else {
      get(i,&val,&ts);
      Serial.print(val,HEX);
      Serial.print(" ");
      Serial.println(ts,HEX);
    }
  }
  else if (strcmp(cmdstr, "len") == 0) {
    for (i = 0; i < MAX_INSTR; ++i)
      if (!instructions[i])  // stop instruction
        break;
    Serial.println(i);
  }
  else if ((strcmp(cmdstr, "go high") == 0)||(strncmp(cmdstr, "hi", 2) == 0)) {
    // write entire port HI
    LATB = 0xFFFF;
    Serial.println("ok");
  }
  else if ((strcmp(cmdstr, "go low") == 0)||(strncmp(cmdstr, "lo", 2) == 0)) {
    // write entire port LO
    LATB = 0;
    Serial.println("ok");
  }
  else if (strcmp(cmdstr, "reset") == 0) {
    // soft-reboot system
    Serial.println("ok");
    asm volatile ("j reset\n\t");
  }
  else{
    Serial.println("invalid request");
  }
}


