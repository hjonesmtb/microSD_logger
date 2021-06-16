module mcp3001_master( 
							 input clk_50,				// 50MHz internal clock
							 input miso,					// bitstream from ADC. Pin 2 of GPIO1.
							 output reg [15:0] output_data, // full sample from ADC (10 miso bits)
							 output reg cs,					// active low chip select - bring low for > 13 cycles to read ADC output. Pin 4 of GPIO1.
							 output reg spi_clk // 1MHz master clock for SPI. (Max clock rate is 1.05MHz)
							 );
	
	reg [3:0] bit_count; // to count bits from ADC
	reg [5:0] clock_count;// clock division
	reg[9:0] rx_data;
	
	// Generate 1MHz SPI clock
	always@(negedge clk_50)
	begin
		if (clock_count == 25)
		begin
			spi_clk <= ~spi_clk;
			clock_count <= 1;
		end
		
		else
		begin
			clock_count <= clock_count + 1;
		end	
	end
		
	// Pulse cs and read data from ADC
	always@(negedge spi_clk)
	begin				
		if (bit_count >= 4 && bit_count <= 13) // sample these 8 bits
		begin
			rx_data[13 - bit_count] <= miso;
		end		
		cs <= (bit_count == 13)? 1'b1 : 1'b0; // pulse cs every 14 clocks
	end
	
	// count spi_clk
	// store data after each full cycle
	always@(negedge spi_clk)
	begin
		if (cs)
		begin
			bit_count <= 1; 
			output_data <= {6'b000000,rx_data};
		end
		
		else
		begin
			bit_count <= bit_count + 1;
		end
	end
endmodule