const unsigned int max_instructions = 200;

// These must be global so they can be read 
// by the interpreter in run() and written to
// by the server in loop():
unsigned int array_delay_time[max_instructions];
unsigned int array_reps[max_instructions];

// These must be global so they can be set by the 
// start() function, but subsequently used by the 
// run() function, which is called as an interrupt
// in the case of a hardware-triggered run:
// TODO: ensure being global doesn't increase variable access time

void start(byte autostart){
  // set the values required by the firt iteration of the loop in run():
  unsigned int delay_time = array_delay_time[0];
  unsigned int delay_counter = 0; 
  unsigned int reps = array_reps[0];
  unsigned int j = 0;
  Serial.println("ok");
  // disable all interrupts:
  while (1){
    // Go high:
    LATA = 0x08;
    // Wait:
    while(1){__asm__(" ");if (++delay_counter==delay_time){break;}}
    // Go low:
    LATA = 0;
    while(1){__asm__(" ");if (--delay_counter==0){break;}}
    // Done enough clock ticks yet?
    if (--reps==0){
      // Load in the next round of clock ticks:
      ++j;
      delay_time = array_delay_time[j];
      reps = array_reps[j];
      if (reps==0){break;}
    }
    else{
      // Some no-ops here to ensure all ticks are as slow as the last tick
      __asm__("nop\n\t");
      __asm__("nop\n\t");
      __asm__("nop\n\t");
      __asm__("nop\n\t");
      __asm__("nop\n\t");
      __asm__("nop\n\t");
    }
  }
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
      array_delay_time[addr] = delay_time;
      array_reps[addr] = reps;
      Serial.println("ok");
    }
  }
  else{
    Serial.println("invalid request");
  }
}


