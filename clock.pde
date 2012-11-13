//#include <SPI.h>
//#include <Ethernet.h>

//byte mac[] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
//byte ip[] = { 192,168,1, 177 };
//Server server(8000);

const unsigned int max_instructions = 200;

// These must be global so they can be read 
// by the interpreter in run() and written to
// by the server in loop():
unsigned int instructions[max_instructions];

void start(int autostart){
  digitalWrite(3,LOW);
  // set the values required by the firt iteration of the loop in run():
  Serial.println("ok");
  noInterrupts();
    
  LATA = 0xffff;
  asm volatile ("nop\n\t");
  LATA = 0;
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
  asm volatile ("nop\n\t");
  asm volatile ("nop\n\t");
  // don't fill our branch delay slots with nops, thank you very much:
  asm volatile (".set noreorder\n\t");
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
  interrupts();
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
  //pinMode(3, INPUT);
  //digitalWrite(3,LOW);
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
      instructions[2*addr] = delay_time - 1;
      instructions[2*addr+1] = delay_time*reps - 4;
      Serial.println("ok");
    }
  }
  else if (readstring == "go high"){
    digitalWrite(3,HIGH);
    Serial.println("ok");
  }
  else if (readstring == "go low"){
    digitalWrite(3,LOW);
    Serial.println("ok");
  }
  
  else{
    Serial.println("invalid request");
  }
}


