PineBlasterv2: Under Development
==========================================

This is an experimental version of the PineBlaster code that merges the functionality of the original PineBlaster with the functionality of the BitBlaster.
It also adds support for both the original ChipKit MAX32 board and the ChipKit Wifire board and compilation through the standard Arduino IDE (after the [ChipKit Core](http://chipkit.net/wiki/index.php?title=ChipKIT_core) has been installed in the IDE).
Note that you still need to disable the compiler optimisations for the ChipKit Core as per the [PineBlasterv1 instructions](https://github.com/labscript-suite/pineblaster) (note that for me, this file was located in C:\Users\<username>\AppData\Local\Arduino15\packages\chipKIT\hardware\pic32\1.3.1\platform.txt, but your location may vary)

This code was primarily tested on the ChipKit WiFire board, but should also work on the ChipKit MAX32 board. 
Using an external trigger has been tested to work, but we have not yet verified the consistency of the timing of the trigger.

We encourage uses to contact us on the [labscript suite mailing list](https://groups.google.com/forum/#!forum/labscriptsuite) to discuss the development of this project!

Note: This project was forked from the BitBlaster which was in turn forked from the PineBlaster.
