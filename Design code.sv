module req_ack (
    input  logic       clk,
    input  logic       reset_n, // Asynchronous reset
    input  logic       req,
    input  logic [7:0] data_in,
    
    output logic       ack,
    output logic [7:0] intern_register,
    output logic [4:0] wr_pointer
);

    // Memory: 32 entries of 8-bit each
    logic [7:0] mem [31:0];

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ack             <= 1'b0;
            intern_register <= 8'h00;
            wr_pointer      <= 5'h00;
        end else begin
            if (req && !ack) begin
                ack             <= 1'b1;
                mem[wr_pointer] <= data_in; // Using pointer for memory address
                wr_pointer      <= wr_pointer + 1'b1;
                intern_register <= data_in; // Assuming you want to store the last data
            end else if (!req) begin
                ack             <= 1'b0;
            end
        end
    end

endmodule

Interface req_ack (input bit clk); 

Logic clk; //positive edge clk 
Logic reset_n; // A-Sychronic reset, active low 
Logic req; // active high 
Logic ack; // active high 
Logic [7:0] data; // 2^8 = 0-255 

Property p_data_stability
@(posedge clk) disable iff (!reset_n || !assertions_en) // after clk, disable reset only if
(req && !ack) |=> $stable(data) throughout (ack [->1]);
endproperty 

Property p_no_spurious_ack;
@(posedge clk) disable iff (!reset_n || !assertions_en) // after clk, disable this test only if reset is active
$rose(ack) -> req;
Endproperty

Property p_req_persistence; 
@(posedge clk) disable iff (!reset_n || !assertions_en)
(req && !ack) | => req;
Endpropery

// Assertion Directives 

Assert_data_stability: assert property (p_data_stability) // condition that must be in the system.
Else $error (“[SVA ERROR] DATA toggled while waiting for ACK”);

Assert_act_vaild: assert property (p_no_spurious_ack);
Else $error “([SVA ERROR] ACK rose without a valid REQ!”);


Assert_req_persistence assert property (p_req_persistence);
Else $error “([SVA ERROR] REQ dropped before ACK was received!”);

Endinterface
   
    
    
      
  

    
