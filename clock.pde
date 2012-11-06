const int max_program_length = 102310;
byte * program_start_addr;
  
void start(int autostart){
  Serial.println("about to jump...");
  // Load the RAM address of the start of the program into a temporary register:
  __asm__("lui $t0, 0xa000\n\t");
  __asm__("ori $t0, 0x7000\n\t");
  // Jump to the address in that register, and "link" (store a return
  // address in $ra so we can get back here):
  __asm__("jalr $t0\n\t");
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

