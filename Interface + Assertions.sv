interface my_intercace (input Logic clk); 

logic reset_n; // A-Sychronic reset, active low 
logic req; // active high 
logic ack; // active high 
logic [7:0] data; // 2^8 = 0-255 

interface my_interface(input logic clk);
  logic req, ack;
  logic [31:0] data;
  logic reset_n;

  // Clocking Block - Preponed Region
  clocking mon_cb @(posedge clk);
    default input #1step; 
    input req, ack, data, reset_n;
  endclocking

  // Clocking Block - Hold violations
  clocking drv_cb @(posedge clk);
    default input #1step output #1ns;
    output req, data;
    input  ack, reset_n;
  endclocking

  // Modports 
  modport MONITOR (clocking mon_cb);
  modport DRIVER  (clocking drv_cb);
endinterface
  
endinterface 

property p_data_stability
@(posedge clk) disable iff (!reset_n || !assertions_en) // after clk, disable reset only if
(req && !ack) |=> $stable(data) throughout (ack [->1]);
endproperty 

property p_no_spurious_ack;
@(posedge clk) disable iff (!reset_n || !assertions_en) // after clk, disable this test only if reset is active
$rose(ack) -> req;
endproperty

property p_req_persistence; 
@(posedge clk) disable iff (!reset_n || !assertions_en)
(req && !ack) |=> req until_with ack;
endproperty

// Assertion Directives 

assert_data_stability: assert property (p_data_stability) // condition that must be in the system.
Else $error (“[SVA ERROR] DATA toggled while waiting for ACK”);
             
assert_act_vaild: assert property (p_no_spurious_ack);
Else $error “([SVA ERROR] ACK rose without a valid REQ!”);

assert_req_persistence assert property (p_req_persistence);
Else $error “([SVA ERROR] REQ dropped before ACK was received!”);

endinterface
