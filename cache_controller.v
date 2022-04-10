module cache_controller (
	clock,
	reset_n,

    // Declaring CPU signals
	cpu_req_addr,
	cpu_req_datain,
	cpu_req_dataout,
	cpu_req_rw,
	cpu_req_valid,

    // Declaring Cache ready signal
	cache_ready,

    // Declaring Main memory signals	
	mem_req_addr,  
	mem_req_datain,
	mem_req_dataout,
	mem_req_rw,
	mem_req_valid,
	mem_req_ready
);

// Declaring the FSM states
parameter IDLE        = 2'b00;
parameter COMPARE_TAG = 2'b01;
parameter ALLOCATE    = 2'b10;
parameter WRITE_BACK  = 2'b11;

// Initial inputs
input clock;
input reset_n;

// Declaring the inputs and outputs for CPU requests to cache controller
input [31:0] cpu_req_addr;
input [127:0] cpu_req_datain;
input cpu_req_rw; // For cpu writes, the value is 1 & for cpu reads, its 0
input cpu_req_valid;

output [31:0] cpu_req_dataout;

// Declraing the inputs and outputs for Main Memory Requests from cache controller
input [127:0] mem_req_datain;
input mem_req_ready;

output [31:0] mem_req_addr;
output [31:0] mem_req_dataout;
output mem_req_rw;
output mem_req_valid;

// For cache ready
output cache_ready;

// Cache Memory = Tag Memory + Data Memory

// Tag Memory = tag + valid bit + dirty bit
reg [19:0] tag_mem [1023:0];

// Data part of the cache
reg [127:0] data_mem [1023:0];

// Declaring the necessary temporary variables as wire
wire [17:0] cpu_addr_tag;
wire [9:0] cpu_addr_index;
wire [1:0] cpu_addr_blk_offset;
wire [1:0] cpu_addr_byte_offset;
wire [19:0] tag_mem_entry;
wire [127:0] data_mem_entry;
wire hit;

// Declaring the required variables as register
reg [1:0] present_state, next_state;
reg [31:0] cpu_req_dataout, next_cpu_req_dataout;
reg [31:0] cache_read_data;
reg cache_ready, next_cache_ready;
reg [31:0] mem_req_addr, next_mem_req_addr;
reg mem_req_rw, next_mem_req_rw;
reg mem_req_valid, next_mem_req_valid;
reg [127:0] mem_req_dataout, next_mem_req_dataout;

reg write_datamem_mem; // Write operation from Main Memory
reg write_datamem_cpu; // Write operation from CPU
reg tagmem_enable;
reg valid_bit, dirty_bit;

reg [31:0] cpu_req_addr_reg, next_cpu_req_addr_reg;
reg [127:0] cpu_req_datain_reg, next_cpu_req_datain_reg;
reg cpu_req_rw_reg, next_cpu_req_rw_reg;

// Defining the range of various parts of CPU Address
// CPU Address = tag + index + block offset + byte offset
assign cpu_addr_tag = cpu_req_addr_reg[31:14];
assign cpu_addr_index = cpu_req_addr_reg[13:4];
assign cpu_addr_blk_offset = cpu_req_addr_reg[3:2];
assign cpu_addr_byte_offset = cpu_req_addr_reg[1:0];

assign tag_mem_entry = tag_mem[cpu_addr_index];
assign data_mem_entry = data_mem[cpu_addr_index];
assign hit = tag_mem_entry[19] && (cpu_addr_tag == tag_mem_entry[17:0]);

// Loading initial values for Data memory and Tag memory
initial begin
$readmemh("data_memory.mem", data_mem);
end

initial begin
$readmemh("tag_memory.mem", tag_mem);
end

always @ (posedge clock or negedge reset_n)
begin
  if(!reset_n)
  begin
	tag_mem[cpu_addr_index]  <= tag_mem[cpu_addr_index];
	data_mem[cpu_addr_index] <= data_mem[cpu_addr_index];
	present_state   	     <= IDLE;
	cpu_req_dataout 	     <= 32'd0;
	cache_ready     	     <= 1'b0;
	mem_req_addr    	     <= 32'd0;
	mem_req_rw      	     <= 1'b0;
	mem_req_valid   	     <= 1'b0;
	mem_req_dataout 	     <= 128'd0;
	cpu_req_addr_reg	     <= 1'b0;
	cpu_req_datain_reg       <= 128'd0;
	cpu_req_rw_reg  	     <= 1'b0;
  end
  else
  begin
    tag_mem[cpu_addr_index]  <= tagmem_enable ? {4'd0,valid_bit,dirty_bit,cpu_addr_tag} : tag_mem[cpu_addr_index];
   	data_mem[cpu_addr_index] <= write_datamem_mem ? mem_req_datain : write_datamem_cpu ? cpu_req_datain_reg : data_mem[cpu_addr_index];
	present_state   	     <= next_state;
	cpu_req_dataout 	     <= next_cpu_req_dataout;
	cache_ready     	     <= next_cache_ready;
	mem_req_addr    	     <= next_mem_req_addr;
	mem_req_rw      	     <= next_mem_req_rw;
	mem_req_valid   	     <= next_mem_req_valid;
	mem_req_dataout 	     <= next_mem_req_dataout;
	cpu_req_addr_reg	     <= next_cpu_req_addr_reg;
	cpu_req_datain_reg       <= next_cpu_req_datain_reg;
	cpu_req_rw_reg  	     <= next_cpu_req_rw_reg;
  end
 end

always @ (*)
begin
    write_datamem_mem       = 1'b0;
    write_datamem_cpu       = 1'b0;
    valid_bit               = 1'b0;
    dirty_bit               = 1'b0;
    tagmem_enable           = 1'b0;
    next_state              = present_state;
    next_cpu_req_dataout    = cpu_req_dataout;
    next_cache_ready        = 1'b1;
    next_mem_req_addr       = mem_req_addr;
    next_mem_req_rw         = mem_req_rw;
    next_mem_req_valid      = mem_req_valid;
    next_mem_req_dataout    = mem_req_dataout;
    next_cpu_req_addr_reg   = cpu_req_addr_reg;
    next_cpu_req_datain_reg = cpu_req_datain_reg;
    next_cpu_req_rw_reg     = cpu_req_rw_reg;

case (cpu_addr_blk_offset)
	2'b00: cache_read_data   = data_mem_entry[31:0];
	2'b01: cache_read_data   = data_mem_entry[63:32];
	2'b10: cache_read_data   = data_mem_entry[95:64];
	2'b11: cache_read_data   = data_mem_entry[127:96];
	default: cache_read_data = 32'd0;
endcase

case(present_state)
  IDLE:
  begin
    if (cpu_req_valid)
    begin
        next_cpu_req_addr_reg    = cpu_req_addr;
        next_cpu_req_datain_reg  = cpu_req_datain;
        next_cpu_req_rw_reg      = cpu_req_rw;
        next_cache_ready         = 1'b0;  
        next_state               = COMPARE_TAG;
    end
    else
    next_state = present_state;
  end
  
  COMPARE_TAG:
  begin
    if (hit & !cpu_req_rw_reg) // We have a Read hit here
    begin
        next_cpu_req_dataout = cache_read_data;
        next_state = IDLE;
    end
    else if (!cpu_req_rw_reg) //We have a Read miss here
    begin
      next_cache_ready = 1'b0;  
	  if (!tag_mem_entry[18]) //Here Clean bit is set, Now we read new block from the memory
	  begin
        next_mem_req_addr = cpu_req_addr_reg;
        next_mem_req_rw = 1'b0;
        next_mem_req_valid = 1'b1;
        next_state = ALLOCATE;
	  end
	  else
      //Here Dirty bit is set, Write cache block to Old Memory Address, then read this block with current address
	  begin
        // Set Old Tag, Current Index, Offset to 00
        next_mem_req_addr = {tag_mem_entry[17:0],cpu_addr_index,4'd0};
        next_mem_req_dataout = data_mem_entry;
        next_mem_req_rw = 1'b1;
        next_mem_req_valid = 1'b1;
        next_state = WRITE_BACK;
	  end
    end
    else
    //Here we perform Write Operation
    begin
        valid_bit = 1'b1;
        dirty_bit = 1'b1;
        tagmem_enable = 1'b1;
        write_datamem_cpu = 1'b1;
        next_state = IDLE;
    end
  end
  
  ALLOCATE: 
  begin
    next_mem_req_valid = 1'b0;
    next_cache_ready = 1'b0;

    // Wait for Main Memory to be ready with Read Data
	if(!mem_req_valid && mem_req_ready)
	begin
        // Write to Data Memory
	    write_datamem_mem = 1'b1;

        // Make the Tag Memory entry valid
    	valid_bit = 1'b1;
    	dirty_bit = 1'b0;
    	tagmem_enable = 1'b1;
	    next_state = COMPARE_TAG;
	end
	else
	begin
	next_state = present_state;
	end
  end
  
  WRITE_BACK:
  begin
    next_cache_ready = 1'b0;  
    next_mem_req_valid = 1'b0;

    // Write operation is finished, now we perform Read operation
	if(!mem_req_valid && mem_req_ready)  
	begin
        valid_bit = 1'b1;
        dirty_bit = 1'b0;
        tagmem_enable = 1'b1;
        next_mem_req_addr = cpu_req_addr_reg;
        next_mem_req_rw = 1'b0;
        next_mem_req_valid = 1'b1;
        next_state = ALLOCATE;
	end
	else
	begin
        next_state = present_state;
	end
  end
endcase
end
endmodule