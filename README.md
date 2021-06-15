# microSD_logger
Basic code for writing to a microSD card from DE0-CV FPGA. sd_controller.v and basic state machine taken from http://web.mit.edu/6.111/volume2/www/f2019/tools/

On my board, the SD card can write at ~1.5MB/sec, so the continuous sampling rate must be less than this.
