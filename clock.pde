const unsigned int max_instructions = 200;

// These must be global so they can be read 
// by the interpreter in run() and written to
// by the server in loop():
unsigned int instructions[max_instructions];

// These must be global so they can be set by the 
// start() function, but subsequently used by the 
// run() function, which is called as an interrupt
// in the case of a hardware-triggered run:
// TODO: ensure being global doesn't increase variable access time

void start(int autostart){
  // set the values required by the firt iteration of the loop in run():
  unsigned int delay_counter = 0; 
  Serial.println("ok");
  // disable all interrupts:
  //int temp_IPC0 = IPC0;
  //int temp_IPC6 = IPC6;
  //IPC0 = 0;
  //IPC6 = 0;
  // except our one:
  // attachInterrupt(0,0,RISING);
  // wait for it....
  //asm volatile ("nop\n\t");
  //asm volatile ("wait\n\t");
  //detachInterrupt(0);
  //Serial.println("woke up!");
 
  // don't fill our branch delay slots with nops, thank you very much:
  asm volatile (".set noreorder\n\t");
  // load the value 0xff into register $t0:
  asm volatile ("addi $t0, 0xff\n\t");
  // load the ram address of LATAINV into register $t1:
  asm volatile ("li $t1, 0xBF88602C\n\t");
  // load the address of the instruction array into register $t2:
  asm volatile ("la $t2, instructions\n\t");
  // load the delay time into register $t3:
  asm volatile ("lw $t3, 0($t2)\n\t"); 
  // load the reps into register $t4:
  asm volatile ("lw $t4, 4($t2)\n\t"); 
  // load the delay loop counter (initially zero) into register $t5:
  asm volatile ("li $t5, 0x0\n\t");
  // store one into register $t6:
  asm volatile ("li $t6, 0x1\n\t");
  // start of the while loop:
  // go high by writing the contents of $t0 (0xff) to the RAM address in $t1 (that of LATAINV):
  asm volatile ("again: nop\n\t");
  asm volatile ("nop\n\t");
  asm volatile ("nop\n\t");
  asm volatile ("nop\n\t");
  asm volatile ("nop\n\t");
  asm volatile ("nop\n\t");
  asm volatile ("top_of_loop: sw $t0, 0($t1)\n\t"); 
  // wait for delay_time ($t3) (actually 2*$t3 + 2 instructions):
  asm volatile ("high_delay: bne $t5, $t3, high_delay\n\t");
  asm volatile ("addi $t5, 1\n\t");
  // go low by writing the contents of $t0 (0xff) to the RAM address in $t1 (that of LATAINV):
  asm volatile ("sw $t0, 0($t1)\n\t"); 
  // wait for delay_time ($t3):
  asm volatile ("low_delay: bne $t5, $t6, low_delay\n\t");
  asm volatile ("addi $t5, -1");
  // break if reps is 1:
  asm volatile ("bne $t4, $t6, again\n\t");
  asm volatile ("addi $t4, -1\n\t");
  // load the the next reps in:
  asm volatile ("lw $t4, 12($t2)\n\t"); 
  // increment our instruction pointer:
  asm volatile ("addi $t2, 8\n\t");
  // go to the top of the loop if it's not a stop instruction:
  asm volatile ("bne $t4, $zero, top_of_loop\n\t");
  // load the next delay time in:
  asm volatile ("lw $t3, 0($t2)\n\t");
  // go low:
  asm volatile ("sw $t0, 0($t1)\n\t"); 

  //while (1){
  //  // Go high:
  //  LATAINV = 0xff;
  //  // Wait:
  //  while(1){__asm__(" ");if (++delay_counter==delay_time){break;}}
  //  // Go low:
  //  LATAINV = 0xff;
  //  while(1){__asm__(" ");if (--delay_counter==0){break;}}
  //  // Done enough clock ticks yet?
  //  if (--reps==0){
  //    // Load in the next round of clock ticks:
  //    ++j;
  //    delay_time = array_delay_time[j];
  //    reps = array_reps[j];
  //    if (reps==0){break;}
  //  }
  //  else{
  //    // Some no-ops here to ensure all ticks are as slow as the last tick
  //    __asm__("nop\n\t");
  //    __asm__("nop\n\t");
  //    __asm__("nop\n\t");
  //  }
  //}
  // Restore other interrupts to their previous state:
  //IPC0 = temp_IPC0;
  //IPC6 = temp_IPC6;
}


String readline(){
  String readstring = "";
  char c;
  byte crfound = 0;
  while (true){
    if (Serial.available() > 0){
      char c = Serial.read();
      if (c == '\r'){
        crfound = 1;
      }
      else if (c == '\n'){
        if (crfound == 1){
          return readstring;
        }
        else{
          readstring += '\n';
        }
      }
      else if (crfound){
        crfound = 0;
        readstring += '\r';
        readstring += c;
      }
      else{
        readstring += c;
      }
    }
  }
}

void setup(){
  Serial.begin(115200);
  pinMode(13, OUTPUT);
  digitalWrite(13,LOW);
  pinMode(3, INPUT);
  digitalWrite(3,LOW);
}

void loop(){
  String readstring = readline();
  if (readstring == "hello"){
    Serial.println("hello");
  }
  else if (readstring == "hwstart"){
    start(0);
  }
  else if ((readstring == "start") || (readstring == "")){
    start(1);
  }
  else if (readstring.startsWith("set ")){
    int firstspace = readstring.indexOf(' ');;
    int secondspace = readstring.indexOf(' ', firstspace+1);
    int thirdspace = readstring.indexOf(' ', secondspace+1);
    if (secondspace == -1 || thirdspace == -1){
      Serial.println("invalid request");
      return;
    }
    unsigned int addr = readstring.substring(firstspace+1, secondspace).toInt();
    unsigned int delay_time = readstring.substring(secondspace+1, thirdspace).toInt();
    unsigned int reps = readstring.substring(thirdspace+1).toInt();
    if (addr >= max_instructions){
      Serial.println("invalid address");
    }
    else{
      instructions[2*addr] = delay_time;
      instructions[2*addr+1] = reps;
      Serial.println("ok");
    }
  }
  else{
    Serial.println("invalid request");
  }
}


