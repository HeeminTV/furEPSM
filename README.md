# furEPSM

A ***WIP*** NES [EPSM](https://www.nesdev.org/wiki/Expansion_Port_Sound_Module) music driver for Furnace.

Yes, finally a public EPSM driver that *isn't* [FamiStudio](https://famistudio.org/). Waited a long time, tracker users.

## Usage

The driver is particularly intended to use with bankswitched songs. You should write your own bankswitching logic. Just, the update routine has to be called with the correct bank set right before.

The bytecode converter accepts Furnace .txt export and generates one header file and track sequence data for each subsongs.

shit i'm gonna complete this somewhen