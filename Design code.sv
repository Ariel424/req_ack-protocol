module req_ack_with_mem (
  
input logic clk, 
input logic reset_n, // A-Sychronize reset
input logic ack, 
input logic [7:0] data_in, // 2^8 = 256 = 0-255

output logic req,
output logic internal_reg [7:0],
output logic wr_ptr [4:0] // pointer that saying what is the next adress in the memory, 2^5 =

);

logic [7:0] mem [31:0]; // define memory 
  
// Sequential Logic 

  always_ff @(posedge clk or negedge reset_n) begin 
  if (!reset_n) begin 
  ack <= 1'b0;
  wr_ptr <= 5'b00;
  internal_reg <= 8'b00;
  end
  else begin 
  if (req && !ack) begin 
  ack <= 1'b1; // Permission to act
  mem [wr_ptr] <= data_in;
  internal_reg <= data_in;
    wr_ptr <= wr_ptr +  1;
  end
    else if (!req) begin 
      ack <= 1'b0;
    end 
  end 
    endmodule

    interface req_ack_if (input logic clk);
    logic clk, 
    logic reset_n, // A-Sychronize reset
    logic ack, 
    logic [7:0] data_in, // 2^8 = 256 = 0-255

    logic req,
    logic internal_reg [7:0],
    logic wr_ptr [4:0] // pointer that saying what is the next adress in the memory, 2^5 =

    // בדיקה שהדאטה לא משתנה בזמן Handshake
    property p_stable_data;
        @(posedge clk) (req && !ack) |=> $stable(data_in) throughout (ack [->1]);
    endproperty

    assert_data_stability: assert property (p_stable_data)
        else $error("ERROR: Data changed while waiting for ACK!");

    // בדיקה שה-ACK לא עולה בפתאומיות בלי REQ
    property p_no_spurious_ack;
        @(posedge clk) $rose(ack) |-> req;
    endproperty

    assert_ack_valid: assert property (p_no_spurious_ack)
        else $error("ERROR: ACK rose without a valid REQ!");

endinterface
   
    
    
      
  

    
