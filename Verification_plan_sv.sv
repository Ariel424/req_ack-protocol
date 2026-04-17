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

class transaction 

rand logic [7:0] data_in; 
rand int delay; // paramer for delay;

constraint data_c {data_in inside {[8'h00 : 9'hFF]}; }
constraint delay_c {delay inside {[1 : 5]}; } 

function transaction copy();
copy = new(); // memory access 
copy.data_in = this.data_in;
copy.delay = this.delay 
endfunction 

// פונקציית הדפסה לדיבאג
  function void display(string name);
    $display("[%s] Time: %0t | Data: 0x%h | Delay: %0d", name, $time, data_in, delay);
  endfunction
endclass

class generator;
  transaction trans;
  mailbox gen2drv;

  function new(mailbox gen2drv, transaction trans);
    this.gen2drv = gen2drv;
    this.trans = trans;
  endfunction

  task main();
    repeat(32) begin // לופ שממלא את כל הזיכרון שלך
      trans = new();
      if (!trans.randomize()) $fatal("Randomization failed");
      gen2drv.put(trans); // שולח את החבילה לדרייבר
      trans.display("Generator");
    end
  endtask
endclass

class driver
  transaction trans; // object 
  mailbox gen2drv; // getting the data from the transaction 
  virtual req_ack_if vif; // connecting to the interface 

  function new (mailbox gen2drv, virtual req_ack_if vif); 
    this.gen2drv = gen2drv;
    this.vif = vif;
  endfunction

  task main (); 
    forever begin 
      gen2drv.get(trans);
      $display ("[Driver] Received Transaction: Data = 0x%h", trans.data_in);
      @(posedge vif.clk); // waiting for one clock 
      vif.data_in <= trans.data_in; // השמת הדאטה בקו
      vif.req <= 1'b1; // הרמת בקשה
      wait (vif.ack == 1'b1);
      @(posedge vif.clk); // waiting for another clocking 
      vif.req <= 1'b0; 
      wait (vif.ack == 1'b0);
      $display ("[Driver]: Transaction Finished successfully");
    end
  endtask 
endclass 

class monitor;
  transaction trans;
  mailbox mon2scb;      // הצינור ל-Scoreboard
  virtual req_ack_if vif;

  function new(mailbox mon2scb, virtual req_ack_if vif);
    this.mon2scb = mon2scb;
    this.vif = vif;
  endfunction

  task main();
    forever begin
      @(posedge vif.clk);
      if (vif.ack == 1'b1) begin
        trans = new();
        trans.data_in = vif.internal_reg; 
        mon2scb.put(trans);
        $display("[Monitor] Detected Transaction: Data = 0x%h, Write Ptr = %0d", vif.internal_reg, vif.wr_ptr);        
        wait(vif.ack == 1'b0);
      end
    end
  endtask
endclass

class scoreboard;
  mailbox mon2scb;       // מקבל נתונים מהמוניטור
  mailbox gen2scb;       // מקבל את הנתונים המקוריים מהגנרטור (ליצירת ה-Expected Data)
  
  transaction exp_trans; // החבילה שציפינו לה
  transaction act_trans; // החבילה שקיבלנו בפועל
  
  int pass_cnt = 0;      // מונה הצלחות
  int fail_cnt = 0;      // מונה כשלונות

  function new(mailbox mon2scb, mailbox gen2scb);
    this.mon2scb = mon2scb;
    this.gen2scb = gen2scb;
  endfunction

  task main();
    forever begin
      // שליפת הנתונים משני המקורות
      gen2scb.get(exp_trans);
      mon2scb.get(act_trans);

      // השוואה בין הנתונים
      if (exp_trans.data_in == act_trans.data_in) begin
        $display("[Scoreboard] PASS! Expected: 0x%h, Actual: 0x%h", exp_trans.data_in, act_trans.data_in);
        pass_cnt++;
      end else begin
        $error("[Scoreboard] FAIL! Expected: 0x%h, Actual: 0x%h", exp_trans.data_in, act_trans.data_in);
        fail_cnt++;
      end
    end
  endtask
endclass

class environment;
  generator  gen;
  driver     drv;
  monitor    mon;
  scoreboard scb;

  // תיבות דואר (Mailboxes) לקישור בין הרכיבים
  mailbox gen2drv;
  mailbox mon2scb;
  mailbox gen2scb; // צינור נוסף מהגנרטור לסקורבורד בשביל ההשוואה

  virtual req_ack_if vif;

  function new(virtual req_ack_if vif);
    this.vif = vif;
    
    // יצירת התיבות
    gen2drv = new();
    mon2scb = new();
    gen2scb = new();

    // בניית הרכיבים
    gen = new(gen2drv, gen2scb); // נעדכן את הגנרטור שישלח גם לסקורבורד
    drv = new(gen2drv, vif);
    mon = new(mon2scb, vif);
    scb = new(mon2scb, gen2scb);
  endfunction

  task test();
    // הרצת כל הרכיבים במקביל
    fork
      gen.main();
      drv.main();
      mon.main();
      scb.main();
    join_any // מסיימים כשהגנרטור מסיים את 32 הטרנזקציות
  endtask

  task post_test();
    $display("---------------------------------------");
    $display("Test Finished! Passes: %0d, Fails: %0d", scb.pass_cnt, scb.fail_cnt);
    $display("---------------------------------------");
  endtask
endclass

module tb_top;
  bit clk;
  bit reset_n;

  // יצירת שעון
  always #5 clk = ~clk;

  // אינטרפייס
  req_ack_if vif(clk);
  
  // הדיזיין (DUT)
  req_ack_with_mem dut (
    .clk(vif.clk),
    .reset_n(vif.reset_n),
    .req(vif.req),
    .data_in(vif.data_in),
    .ack(vif.ack),
    .internal_reg(vif.internal_reg),
    .wr_ptr(vif.wr_ptr)
  );

  environment env;

  initial begin
    reset_n = 0;
    vif.reset_n = 0;
    #20 reset_n = 1;
    vif.reset_n = 1;

    env = new(vif);
    env.test();
    env.post_test();
    $finish;
  end
endmodule
      
      
