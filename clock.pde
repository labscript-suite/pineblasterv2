#include <plib.h>
//#include <SPI.h>
//#include <Ethernet.h>

//byte mac[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
//byte ip[] = { 192,168,1, 177 };
//Server server(8000);

const unsigned int max_instructions = 200;
int autostart;
unsigned int instructions[max_instructions];

void __attribute__((naked, at_vector(3), nomips16)) ExtInt0Handler(void){
  asm volatile (".set noreorder\n\t");
  asm volatile ("j foo\n\t");
  asm volatile ("nop\n\t");
}

void __attribute__((naked, nomips16)) Foo(void){
  asm volatile (".set noreorder\n\t");
  asm volatile ("foo:\n\t");
  // interrupt prelude code:
  asm volatile ("addiu	$sp, $sp,-24\n\t"); // push in the stack (enough for six register's worth)

  asm volatile ("li     $k1, 0x101001\n\t"); // the modified status we need to write to acknowledge that we're servicing the interrupt
  asm volatile ("mtc0	$k1, $12\n\t"); // set our modified Status as the system Status
  asm volatile ("sw	$v1, 8($sp)\n\t"); // save $v1 (function return registers..?) to the stack
  asm volatile ("sw	$v0, 4($sp)\n\t"); // save $v2 to the stack

  
  // clear the bit saying we've handled the interrupt:
  asm volatile ("lui	$v1, 0xbf88\n\t"); // load half of the address of IFS0
  asm volatile ("lw	$v0, 4144($v1)\n\t"); // load in IFS0
  asm volatile ("ins	$v0, $zero,0x3,0x1\n\t"); // flip the appropriate bit in our copy of IFS0
  asm volatile ("sw	$v0, 4144($v1)\n\t"); // write this back 
  
  // actual interrupt code:
  asm volatile ("la $v1, LATAINV\n\t");
  asm volatile ("ori $v0, $zero, 0xffff\n\t");
  asm volatile ("sw $v0, 0($v1)\n\t");  // toggle the led
  
  
  
  asm volatile ("lw	$v1, 8($sp)\n\t"); // restore v1
  asm volatile ("lw	$v0, 4($sp)\n\t"); // restore v2
  asm volatile ("li	$k1, 0x100003\n\t"); // The status we need to write back to say we've finished the interrupt
  asm volatile ("addiu	$sp, $sp,24\n\t"); // pop out of the stack
  asm volatile ("mtc0	$k1, $12\n\t"); // restore Status
  asm volatile ("eret\n\t"); // return

}

void start(){
  // set the values required by the first iteration of the loop in run():
  Serial.println("ok");
  // temporarily disable all interrupts:
  int temp_IPC0 = IPC0;
  int temp_IPC6 = IPC6;
  IPC0 = 0;
  IPC6 = 0;
  
  // except for our one:
  attachInterrupt(0,0,RISING);

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
  
  // don't fill our branch delay slots with nops, thank you very much:
  asm volatile (".set noreorder\n\t":::"t0","t1","t2","t3","t4", "t5");
  // load the ram address of PR2 into register $t0:
  asm volatile ("la $t0, PR2\n\t");
  // load the ram address of OC2R into register $t1:
  asm volatile ("la $t1, OC2R\n\t");
  // load the address of the instruction array into register $t2:
  asm volatile ("la $t2, instructions\n\t");
  // load the half-period time into register $t3:
  asm volatile ("lw $t3, 0($t2)\n\t"); 
  // load the delay time into register $t4:
  asm volatile ("lw $t4, 4($t2)\n\t"); 
  // load the the autostart flag into register $t5:
  asm volatile ("la $t5, autostart\n\t");
  asm volatile ("lw $t5, 0($t5)\n\t");
  
  // if we're set to autostart, jump right in:
  asm volatile ("bne $t5, $zero, top\n\t");
  asm volatile ("nop\n\t");
  
  // otherwise wait for it...
  asm volatile ("wait\n\t");
    
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
  // turn everything off:
  OC2CON = 0; 
  // Restore other interrupts to their previous state:
  IPC0 = temp_IPC0;
  IPC6 = temp_IPC6;
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
  // start the Ethernet connection and the server:
  //Ethernet.begin(mac, ip);
  //server.begin();
  Serial.begin(115200);
  int i = 0;
  for (i=0;i<86;i++){
    pinMode(i, OUTPUT);
    digitalWrite(i,LOW);
  }
  // disable all interrupts:
  //IPC0 = 0;
  //IPC6 = 0;
  // except ours:
  attachInterrupt(0,0,RISING);
}

volatile int status_;
  
void loop(){
  String readstring = readline();
  Serial.println(status_, HEX);
}
//  Serial.println("in mainloop!");
//  String readstring = readline();
//  if (readstring == "hello"){
//    Serial.println("hello");
//  }
//  else if (readstring == "hwstart"){
//    autostart = 0;
//    start();
//  }
//  else if ((readstring == "start") || (readstring == "")){
//    autostart = 1;
//    start();
//  }
//  else if (readstring.startsWith("set ")){
//    int firstspace = readstring.indexOf(' ');;
//    int secondspace = readstring.indexOf(' ', firstspace+1);
//    int thirdspace = readstring.indexOf(' ', secondspace+1);
//    if (secondspace == -1 || thirdspace == -1){
//      Serial.println("invalid request");
//      return;
//    }
//    unsigned int addr = readstring.substring(firstspace+1, secondspace).toInt();
//    unsigned int delay_time = readstring.substring(secondspace+1, thirdspace).toInt();
//    unsigned int reps = readstring.substring(thirdspace+1).toInt();
//    if (addr >= max_instructions){
//      Serial.println("invalid address");
//    }
//    else if (delay_time < 4){
//      Serial.println("period too short");
//    }
//    else{
//      instructions[2*addr] = delay_time - 1;
//      instructions[2*addr+1] = delay_time*reps - 4;
//      Serial.println("ok");
//    }
//  }
//  else if (readstring == "go high"){
//    digitalWrite(5,HIGH);
//    Serial.println("ok");
//  }
//  else if (readstring == "go low"){
//    digitalWrite(5,LOW);
//    Serial.println("ok");
//  }
//  
//  else{
//    Serial.println("invalid request");
//  }
//}


