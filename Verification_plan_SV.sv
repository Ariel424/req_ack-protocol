class my_transaction 

rand logic [7:0] data_in; 
rand int delay; // paramer for delay;

constraint data_c {data_in inside {[8'h00 : 8'hFF]}; }
constraint delay_c {delay inside {[1 : 10]}; } 

function transaction copy();
copy = new(); // memory access 
copy.data_in = this.data_in;
copy.delay = this.delay 
endfunction 

function void display(string name);
    $display("[%s] Time: %0t | Data: 0x%h | Delay: %0d", name, $time, data_in, delay);
  endfunction
endclass

class generator;
  mailbox #(my_transaction) gen2drv;
  int repeat_count = 10;
  event done;

  function new(mailbox #(my_transaction) gen2drv);
    this.gen2drv = gen2drv;
  endfunction

  task main();
    repeat(repeat_count) begin
      my_transaction tr = new();
      if (!tr.randomize()) $fatal("Gen randomization failed");
      gen2drv.put(tr);
    end
    -> done;
  endtask
endclass

 class my_driver;
  virtual my_interface vif;
  mailbox #(my_transaction) gen2drv;
  mailbox #(my_transaction) drv2sb; 

  function new(virtual my_interface vif, mailbox #(my_transaction) gen2drv, mailbox #(my_transaction) drv2sb);
    this.vif = vif;
    this.gen2drv = gen2drv;
    this.drv2sb = drv2sb;
  endfunction

  task reset();
    vif.reset_n <= 0;
    vif.req     <= 0;
    repeat(5) @(posedge vif.clk);
    vif.reset_n <= 1;
  endtask

  task main();
    forever begin
      my_transaction tr;
      gen2drv.get(tr);
      drv2sb.put(tr);

      @(posedge vif.clk);
      vif.req  <= 1;
      vif.data <= tr.data;

      fork
        begin: wait_ack
          wait(vif.ack == 1);
        end
        begin: timeout
          repeat(100) @(posedge vif.clk);
          $error("TIMEOUT! No ACK");
        end
      join_any
      disable fork;

      repeat(tr.delay) @(posedge vif.clk);
      vif.req <= 0;
    end
  endtask
endclass

class my_monitor;
  virtual my_interface vif;
  mailbox #(my_transaction) mon2sb;

  function new(virtual my_interface vif, mailbox #(my_transaction) mon2sb);
    this.vif = vif;
    this.mon2sb = mon2sb;
  endfunction

  task main();
    forever @(posedge vif.clk) begin
      if (vif.reset_n && vif.req && vif.ack) begin
        my_transaction tr = new();
        tr.data = vif.data;
        mon2sb.put(tr);
      end
    end
  endtask
endclass

  class my_scoreboard;
  mailbox #(my_transaction) drv2sb;
  mailbox #(my_transaction) mon2sb;
  my_transaction exp_queue[$];

  function new(mailbox #(my_transaction) drv2sb, mailbox #(my_transaction) mon2sb);
    this.drv2sb = drv2sb;
    this.mon2sb = mon2sb;
  endfunction

  task main();
    fork
      // תהליך שאוסף ציפיות
      forever begin
        my_transaction tr;
        drv2sb.get(tr);
        exp_queue.push_back(tr);
      end
      // תהליך שבודק ביצוע בפועל
      forever begin
        my_transaction act, exp;
        mon2sb.get(act);
        if (exp_queue.size() > 0) begin
          exp = exp_queue.pop_front();
          if (act.data == exp.data) $display("MATCH! Data: %h", act.data);
          else $error("MISMATCH! Exp: %h, Got: %h", exp.data, act.data);
        end else $error("Unexpected monitor data!");
      end
    join
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
      
      
