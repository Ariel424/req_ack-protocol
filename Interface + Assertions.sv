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
endproperty

Property p_req_persistence; 
@(posedge clk) disable iff (!reset_n || !assertions_en)
(req && !ack) |=> req until_with ack;
endproperty

// Assertion Directives 

Assert_data_stability: assert property (p_data_stability) // condition that must be in the system.
Else $error (“[SVA ERROR] DATA toggled while waiting for ACK”);

Assert_act_vaild: assert property (p_no_spurious_ack);
Else $error “([SVA ERROR] ACK rose without a valid REQ!”);


Assert_req_persistence assert property (p_req_persistence);
Else $error “([SVA ERROR] REQ dropped before ACK was received!”);

endinterface
