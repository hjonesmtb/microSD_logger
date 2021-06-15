module controller_fifo(input clk_50mhz, output SD_SCK, output SD_CMD, 
	inout [3:0] SD_DAT, output [9:0] LED, input KEY0);

	// Clock the SD card at 25 MHz.
	reg clk_25mhz;
	always@(posedge clk_50mhz) 
			clk_25mhz <= ~clk_25mhz;

    wire rst = ~KEY0;
    wire spiClk;
    wire spiMiso;
    wire spiMosi;
    wire spiCS;

    // MicroSD SPI/SD Mode/DE0-CV
    // 1: Unused / DAT2 / SD_DAT[2]
    // 2: CS / DAT3 / SD_DAT[3]
    // 3: MOSI / CMD / SD_CMD
	 
    // 5: SCLK / SCLK / SD_SCK
	 
    // 7: MISO / DAT0 / SD_DAT[0]
    // 8: UNUSED / DAT1 / SD_DAT[1]
	 
    assign SD_DAT[2] = 1;
    assign SD_DAT[3] = spiCS;
    assign SD_CMD = spiMosi;
    assign SD_SCK = spiClk;
    assign spiMiso = SD_DAT[0];
    assign SD_DAT[1] = 1;
    
    reg rd = 0;
    reg wr = 0;
	 reg [7:0] din;
    reg [7:0] data = 0;
    wire [7:0] dout;
    wire byte_available;
    wire ready;
    wire ready_for_next_byte;
    reg [27:0] adr = 27'd0; // 256 MB 
    
    reg [15:0] bytes = 0;
    reg [1:0] bytes_read = 0;
	 
	 reg last_ready_for_next_byte;
    
    parameter STATE_INIT = 0;
    parameter STATE_START = 1;
    parameter STATE_WAIT = 2;
    parameter STATE_WRITE = 3;
    parameter STATE_READ = 4;
	 parameter STATE_DONE = 5;
	 
    reg [2:0] test_state = STATE_INIT; 
    assign LED = adr[27:18];
    assign done = (adr == 5120);
	 
    sd_controller sdcont(
				.cs(spiCS), .mosi(spiMosi), .miso(spiMiso),
            .sclk(spiClk), .rd(rd), .wr(wr), .reset(rst),
            .din(din), .dout(dout), .byte_available(byte_available),
            .ready(ready), .address(adr), 
            .ready_for_next_byte(ready_for_next_byte), .clk(clk_25mhz)
	
	);
	
	reg [7:0] write_block [511:0];
	reg [7:0] read_block [511:0];
	
	reg [9:0] write_index, read_index;
	
	reg reading = 1'b1;
	reg last_reading;
	
	reg block_ready;
	
	reg [6:0] clk_count;
	reg clk_slow;
	always@(posedge clk_25mhz) begin
		if (&clk_count) begin
			clk_count <= 0;
			clk_slow <= ~clk_slow;
		end
		
		else
			clk_count <= clk_count + 1;
	end
	
	// write one 512 MB block at a time
	always@(posedge clk_slow) begin
		
		data <= data + 1;
		
		write_block[write_index] <= data;	
		write_index <= (write_index == 511) ? 0 : write_index + 1;
		
		block_ready <= write_index == 511;
		
		if (block_ready) begin
			integer i;
			for (i = 0; i < 512; i = i + 1) begin
				read_block[i] <= write_block[i];
			end
			reading <= ~reading;
		end		
	end	

    always @(posedge clk_25mhz) begin
        if(rst) begin
            bytes <= 0;
            bytes_read <= 0;
            wr <= 0;
            rd <= 0;
            test_state <= STATE_INIT; 
        end
        else begin
				last_ready_for_next_byte <= ready_for_next_byte;
				last_reading <= reading;
				
            case (test_state)
                STATE_INIT: begin
                    if(ready) begin
                        test_state <= STATE_WAIT;
                        wr <= 0;
                    end
                end
                STATE_WAIT: begin
							if (reading != last_reading) begin // wait until a new block is being written to
								wr <= 1;
								test_state <= STATE_START;
							end
                end				 
					 STATE_START: begin // Ready goes low when write operation begins
					     if(!ready) begin
                        test_state <= STATE_WRITE;
                        wr <= 0;
								read_index <= 0;
								adr <= adr + 512;
                    end
					 end
                STATE_WRITE: begin // keep writing until ready goes high (sector is full)
                    if(ready) begin
                        test_state <= done ? STATE_DONE : STATE_WAIT;
                    end
                    else if(ready_for_next_byte && !last_ready_for_next_byte) begin

								din <= read_block[read_index];
							
								read_index <= (read_index == 511) ? 511 : read_index + 1;
								
                    end
                end
                STATE_READ: begin
                    if(byte_available) begin
                        rd <= 0;
                        if(bytes_read == 0) begin
                            bytes_read <= 1;
                            bytes[15:8] <= dout;
                        end
                        else if(bytes_read == 1) begin
                            bytes_read <= 2;
                            bytes[7:0] <= dout;
                            
                        end
                    end
                end
					 STATE_DONE: begin
							test_state <= STATE_DONE;
					 end
					 default: test_state <= STATE_INIT;
            endcase
        end
    end
endmodule