Use MPIDE (available on the ChipKIT github) to compile and uppload the code to the ChipKIT MAX32.

One modification is required: compiler optimisations must be disabled. This is required so that the compiler
doesn't produce unpredictable code, or multiple code paths for the same bit of source code. So we do this to
ensure our code is deterministic.

To disable compiler optimisations, edit <MPIDE_folder>/hardware/pic32/platforms.txt and replace all instances of '-O3' with '-O0'.
