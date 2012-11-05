const int max_program_length = 1024;

void receive_program(int length){
  int i;
  for (i=0,i<length,i++){
    while(1)

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
  Serial.begin(115200);
  Serial.println("hello, bilbo!");
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

