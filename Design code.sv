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
   
    
    
      
  

    
