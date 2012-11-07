const int max_program_length = 102310;
byte * program_start_addr;

void start(int autostart){
  // temporarily disable all interrupts:
  int temp_IPC0 = IPC0;
  int temp_IPC6 = IPC6;
  IPC0 = 0;
  IPC6 = 0;
  attachInterrupt(0,0,RISING);
  // Load the RAM address of the start of the program into a temporary
  // register. We'll jump to it in a sec:
  asm volatile ("lui $t0, 0xa000\n\t");
  asm volatile ("ori $t0, 0x7000\n\t");
  asm volatile ("nop\n\t");
  if(autostart==0){
      // wait for it....
      asm volatile ("wait\n\t");
  }
  // disable all interrupts now:
  asm volatile("di\n\t");
  // go!
  asm volatile ("jalr $t0\n\t");
  // branch delay slot:
  asm volatile ("nop\n\t");
  // Restore other interrupts to their previous state:
  IPC0 = temp_IPC0;
  IPC6 = temp_IPC6;
  // detach our interrupt:
  detachInterrupt(0);
  // re-enable global interrupts"
  asm volatile("ei\n\t");
  Serial.println("got back ok!");
}

void receive_program(int length){
  int i;
  byte b;
  for (i=0;i<length;i++){
    while(1){
      if (Serial.available() > 0){
        b = Serial.read();
        memcpy(program_start_addr + i, &b, 1);
        break;
      }
    }
  }
  Serial.println("ok");
}

String readline(){
  String readstring = "";
  char c;
  byte crfound = 0;
  while (1){
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
  // Partitioning RAM,
  // see s3.4.3 of the PIC32 reference for details:
  BMXDKPBA = BMXDRMSZ - max_program_length;
  BMXDUDBA = BMXDRMSZ;
  BMXDUPBA = BMXDRMSZ;
  // Get a pointer to the start of program RAM (using 
  // KSEG1, see s3.4.3.2 of the PIC32 reference for details):
  program_start_addr = (byte *)(BMXDKPBA + 0xA0000000); 
  Serial.begin(115200);
}

void loop(){
  Serial.println("in loop!");
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
  else if (readstring.startsWith("program ")){
    int firstspace = readstring.indexOf(' ');;
    if (firstspace == -1){
      Serial.println("invalid request");
      return;
    }
    int length = readstring.substring(firstspace+1).toInt();
    
    if (length >= max_program_length){
      Serial.println("program is too long");
    }
    else{
      Serial.println("ok");
      receive_program(length);
    }
  }
  else{
    Serial.println("invalid request");
  }
}

