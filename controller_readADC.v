module controller_readADC(
				input clk_50mhz,
				input[3:0] KEY, 
				output SD_SCK, 
				output SD_CMD, 
				inout [3:0] SD_DAT, 
				output [9:0] LED, 
				output [6:0] HEX0,
				output [6:0] HEX1,
				output [6:0] HEX2,
				output [6:0] HEX3,
				output [6:0] HEX4,
				output [6:0] HEX5,
				input miso, 
				output cs, 
				output spi_clk
			);
						
	hex_display hex0(.digit(one), .hex_code(HEX0));
	hex_display hex1(.digit(ten), .hex_code(HEX1));
	hex_display hex2(.digit(hun), .hex_code(HEX2));
	hex_display hex3(.digit(thou), .hex_code(HEX3));
	hex_display hex4(.digit(ten_thou), .hex_code(HEX4));
	hex_display hex5(.digit(hun_thou), .hex_code(HEX5));
	
	reg [3:0] one, ten, hun, thou, ten_thou, hun_thou;


	// Clock the SD card at 25 MHz.
	reg clk_25mhz;
	always@(posedge clk_50mhz) begin
	
		one <= (adr >> 9) % 10;
		ten <= ((adr >> 9)/10) % 10;
		hun <= ((adr >> 9)/100) % 10;
		thou <= ((adr >> 9)/1000) % 10;
		ten_thou <= ((adr >> 9)/10000) % 10;
		hun_thou <= ((adr >> 9)/100000) % 10;

		clk_25mhz <= ~clk_25mhz;			
	end

    reg running;
	 wire rst = ~KEY[1];
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

    wire [7:0] dout;
    wire byte_available;
    wire sd_ready;
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
    assign LED = {data[9:2],adr >= 512,running};
	 
    sd_controller sdcont(
					.cs(spiCS), .mosi(spiMosi), .miso(spiMiso),
					.sclk(spiClk), .rd(rd), .wr(wr), .reset(rst),
					.din(din), .dout(dout), .byte_available(byte_available),
					.ready(sd_ready), .address(adr), 
					.ready_for_next_byte(ready_for_next_byte), .clk(clk_25mhz)
	);
	
	wire [15:0] data;
	mcp3001_master ADC(
						.clk_50(clk_50mhz),
						.miso(miso),
						.output_data(data),
						.cs(cs),
						.spi_clk(spi_clk)
			);
			
	// FIFO 	
	reg [7:0] write_block [511:0];
	reg [7:0] read_block [511:0];
	reg [8:0] write_index, read_index; 
	
	// 
	reg reading = 1'b1;
	reg last_reading;
	
	// write one 512 MB block at a time
	always@(negedge cs) begin
		
		//data <= data + 1;
		
		{write_block[write_index], write_block[write_index+1]} <= data;
			
		write_index <= write_index + 2;
		
		if (write_index == 0) begin
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
				running <= 0;
        end
        else begin
				last_ready_for_next_byte <= ready_for_next_byte;
				last_reading <= reading;
				running <= running?1'b1 : ~KEY[0]; // stay on after one button press
				
            case (test_state)
                STATE_INIT: begin
                    if(sd_ready) begin
                        test_state <= STATE_WAIT;
                        wr <= 0;
                    end
                end
                STATE_WAIT: begin
							if ((reading != last_reading)  && running) begin // wait until a new block is being written to
								wr <= 1;
								test_state <= STATE_START;
							end
                end				 
					 STATE_START: begin // sd_ready goes low when write operation begins
					     if(!sd_ready) begin					
								test_state <= STATE_WRITE;
								wr <= 0;
								read_index <= 0;
								adr <= adr + 512;
                    end
					 end					 
                STATE_WRITE: begin // keep writing until sd_ready goes high (sector is full)
                    if(sd_ready) begin
                        test_state <= STATE_WAIT;
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

module hex_display(
				input[3:0] digit,
				output reg[6:0] hex_code
				);
	always@(digit)	begin
		case (digit)
			9: hex_code = 7'b0011000;
				
			8: hex_code = 7'b0000000;		
					
			7: hex_code = 7'b1111000;		
			
			6: hex_code = 7'b0000010;		
			
			5: hex_code = 7'b0010010;		
			
			4: hex_code = 7'b0011001;		
			
			3: hex_code = 7'b0110000;		
			
			2: hex_code = 7'b0100100;		

			1: hex_code = 7'b1111001;		

			0: hex_code = 7'b1000000;		

			default: hex_code = 7'b1111111;
		endcase
	end
				
endmodule
				